module Esbuild
  class ServeResult
    def initialize(response, wait, stop)
      @port = response["port"]
      @host = response["host"]
      @wait = wait
      @stop = stop
      @is_stopped = false
    end

    def wait
      @wait.wait!
      @wait.value
    end

    def stop
      return if @is_stopped
      @is_stopped = true
      @stop.call
    end
  end
end
