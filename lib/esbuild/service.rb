require "concurrent"
require "esbuild/stdio_protocol"
require "esbuild/flags"
require "esbuild/build_result"
require "esbuild/serve_result"
require "esbuild/build_state"

module Esbuild
  class Service
    # TODO: plugins
    ESBUILD_VERSION = "0.11.8"

    def initialize
      @request_id = 0
      @serve_id = 0
      @build_key = 0
      @first_packet = true
      @response_callbacks = Concurrent::Map.new
      @plugin_callbacks = Concurrent::Map.new
      @watch_callbacks = Concurrent::Map.new
      @serve_callbacks = Concurrent::Map.new
      @buffer = String.new(encoding: Encoding::BINARY)

      child_read, child_stdout = IO.pipe
      child_stdin, @child_write = IO.pipe
      pid = spawn("npx", "esbuild", "--service=#{ESBUILD_VERSION}", "--ping", out: child_stdout, err: :err, in: child_stdin)
      child_stdin.close
      child_stdout.close

      Thread.new { worker_thread(pid, child_read) }
    end

    def build_or_serve(options, serve_options = nil)
      key = @build_key
      @build_key += 1
      opts = Flags.flags_for_build_options(options)
      on_rebuild = opts[:watch]&.fetch(:on_rebuild, nil)

      request = {
        command: "build",
        key: key,
        entries: opts[:entries],
        flags: opts[:flags],
        write: opts[:write],
        stdinContents: opts[:stdin_contents],
        stdinResolveDir: opts[:stdin_resolve_dir],
        absWorkingDir: opts[:abs_working_dir] || Dir.pwd,
        incremental: opts[:incremental],
        nodePaths: opts[:node_paths],
        hasOnRebuild: !!on_rebuild
      }
      serve = serve_options && build_serve_data(serve_options, request)

      response = send_request(request)
      if serve
        ServeResult.new(response, serve[:wait], serve[:stop])
      else
        build_state = BuildState.new(self, on_rebuild)
        build_state.response_to_result(response)
      end
    end

    def start_watch(watch_id, proc)
      @watch_callbacks[watch_id] = proc
    end

    def stop_watch(watch_id)
      @watch_callbacks.delete(watch_id)
      send_request(command: "watch-stop", watchID: watch_id)
    end

    def transform(input, options)
      flags = Flags.flags_for_transform_options(options)
      send_request(
        command: "transform",
        flags: flags,
        inputFS: false,
        input: input
      )
    end

    def send_request(request)
      @request_id += 1
      id = @request_id
      encoder = StdioProtocol::PacketEncoder.new
      encoded = encoder.encode_packet(Packet.new(id, true, request))
      @child_write.write encoded
      ivar = Concurrent::IVar.new
      @response_callbacks[id] = ivar
      ivar.wait!
      ivar.value
    end

    private

    def read_from_stdout(chunk)
      @buffer << chunk
      offset = 0
      while offset + 4 < @buffer.bytesize
        size = @buffer.getbyte(offset) | (@buffer.getbyte(offset + 1) << 8) | (@buffer.getbyte(offset + 2) << 16) | (@buffer.getbyte(offset + 3) << 24)
        if offset + 4 + size > @buffer.bytesize
          break
        end
        offset += 4
        handle_incoming_packet(@buffer, offset, size)
        offset += size
      end
      @buffer.slice!(0, offset)
    end

    def send_response(id, response)
      encoder = StdioProtocol::PacketEncoder.new
      encoded = encoder.encode_packet(Packet.new(id, false, response))
      @child_write.write encoded
    end

    def build_serve_data(options, request)
      serve_id = @serve_id
      @serve_id += 1
      options = options.dup
      on_request = nil
      Flags.get_flag(options, :port, Numeric) { |v| request[:port] = v }
      Flags.get_flag(options, :host, String) { |v| request[:host] = v }
      Flags.get_flag(options, :serve_dir, String) { |v| request[:serveDir] = v }
      Flags.get_flag(options, :on_request, Proc) { |v| on_request = v }
      raise ArgumentError, "Invalid option in serve() call: #{options.keys.first}" unless options.empty?
      request[:serve] = {serveID: serve_id}
      wait = Concurrent::IVar.new
      @serve_callbacks[serve_id] = {
        on_request: on_request,
        on_wait: ->(error) do
          @serve_callbacks.delete(serve_id)
          if error
            wait.fail StandardError.new(error)
          else
            wait.set
          end
        end
      }

      {
        wait: wait,
        stop: -> do
          send_request(command: "serve-stop", serveID: serve_id)
        end
      }
    end

    def handle_request(id, request)
      case request["command"]
      when "ping"
        send_response(id, {})
      when "resolve", "load"
        callback = @plugin_callbacks[request["key"]]
        response = {}
        if callback
          response = callback.call(request)
        end
        send_response(id, response)
      when "serve-request"
        callback = @serve_callbacks[request["serveID"]]
        if callback && callback[:on_request]
          on_request = callback[:on_request]
          if on_request.arity == 1
            on_request.call(request["args"])
          else
            on_request.call
          end
        end
        send_response(id, {})
      when "serve-wait"
        callback = @serve_callbacks[request["serveID"]]
        if callback && callback[:on_wait]
          callback[:on_wait].call(request["error"])
        end
        send_response(id, {})
      when "watch-rebuild"
        callback = @watch_callbacks[request["watchID"]]
        callback&.call(nil, request["args"])
        send_response(id, {})
      else
        raise "Unknown command #{request["command"]}"
      end
    rescue => e
      send_response(id, {errors: [{text: e.message}]})
    end

    def handle_incoming_packet(bytes, offset, size)
      if @first_packet
        @first_packet = false
        version = bytes.slice(offset, size)
        raise "Version mismatch #{ESBUILD_VERSION} != #{version}" if ESBUILD_VERSION != version

        return
      end

      decoder = StdioProtocol::PacketDecoder.new(bytes, offset, size)
      packet = decoder.decode_packet

      if packet.is_request
        handle_request packet.id, packet.value
      else
        callback = @response_callbacks.delete(packet.id)
        if packet.value["error"]
          callback.fail(StandardError.new(packet.value["error"]))
        else
          callback.set(packet.value)
        end
      end
    end

    def worker_thread(pid, child_read)
      buffer = String.new(encoding: Encoding::BINARY)
      loop do
        done = Process.waitpid(pid, Process::WNOHANG)
        if done
          error = StandardError.new("Closed")
          close_callbacks(error)
          break
        end

        begin
          chunk = child_read.read_nonblock(16384, buffer)
          read_from_stdout chunk
        rescue IO::WaitReadable
          IO.select([child_read])
          retry
        end
      end
    ensure
      @child_write.close
      child_read.close
    end

    def close_callbacks(error)
      @response_callbacks.each_value do |callback|
        callback.fail(error)
      end
      @response_callbacks.clear
    end
  end

  class BuildFailureError < StandardError
    attr_reader :errors
    attr_reader :warnings

    def initialize(errors, warnings)
      @errors = errors
      @warnings = warnings
      summary = ""
      unless errors.empty?
        limit = 5
        details = errors.slice(0, limit + 1).each_with_index.map do |error, index|
          break "\n..." if index == limit
          location = error["location"]
          break "\nerror: #{error["text"]}" unless location
          "\n#{location["file"]}:#{location["line"]}:#{location["column"]}: error: #{error["text"]}"
        end.join
        summary = "with #{errors.size} error#{errors.size > 1 ? "s" : ""}:#{details}"
      end

      super "Build failed#{summary}"
    end
  end
end
