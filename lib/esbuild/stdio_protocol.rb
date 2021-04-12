require "esbuild/packet"

module Esbuild
  module StdioProtocol
    extend self

    class PacketDecoder
      attr_reader :offset

      def initialize(buf, offset, size)
        @buf = buf
        @offset = offset
        @end = offset + size
      end

      def decode_packet
        id = read32
        is_request = (id & 1) == 0
        id >>= 1

        value = visit
        Packet.new(id, is_request, value)
      end

      def visit
        kind = read8
        case kind
        when 0
          # Null
          nil
        when 1
          # Bool
          !!read8
        when 2
          # Integer
          read32
        when 3
          # String
          read_string.force_encoding(Encoding::UTF_8)
        when 4
          # Bytes
          read_string
        when 5
          # Array
          size = read32
          size.times.map { visit }
        when 6
          # Object
          result = {}
          size = read32
          size.times do
            key = read_string.force_encoding(Encoding::UTF_8)
            result[key] = visit
          end
          result
        else
          raise ArgumentError, "Invalid packet #{kind}"
        end
      end

      def read_string
        size = read32
        result = @buf.byteslice(@offset, size)
        @offset += size
        result
      end

      def read8
        raise ArgumentError, "Reading past buffer" if @offset >= @end
        byte = @buf.getbyte(@offset)
        @offset += 1
        byte
      end

      def read32
        read8 | (read8 << 8) | (read8 << 16) | (read8 << 24)
      end
    end

    class PacketEncoder
      def initialize
        @format = ""
        @elements = []
        @size = 0
      end

      def encode_packet(packet)
        write32 0
        write32((packet.id << 1) | (packet.is_request ? 0 : 1))
        visit(packet.value)
        @elements[0] = @size - 4
        @elements.pack(@format)
      end

      def visit(value)
        case value
        when nil
          write8 0
        when true, false
          write8 1
          write8(value ? 1 : 0)
        when Integer
          write8 2
          write32 value
        when String
          if value.encoding == Encoding::BINARY
            write8 4
            write_string value
          else
            write8 3
            value = value.encode(Encoding::UTF_8) unless value.encoding == Encoding::UTF_8
            write_string value
          end
        when Array
          write8 5
          write32 value.size
          value.each { |item| visit(item) }
        when Hash
          write8 6
          write32 value.size
          value.each do |key, val|
            write_string key
            visit val
          end
        else
          raise ArgumentError, "Don't know how to encode #{value.inspect}"
        end
      end

      def write_string(string)
        string = string.to_s
        write32 string.bytesize
        @elements << string
        @format << "a*"
        @size += string.bytesize
      end

      def write32(value)
        @elements << value
        @format << "L<"
        @size += 4
      end

      def write8(value)
        @elements << value
        @format << "C"
        @size += 1
      end
    end
  end
end
