require "forwardable"
require "json"

module Esbuild
  class BuildResult
    extend Forwardable

    class OutputFile
      attr_reader :path
      attr_reader :contents

      def initialize(path, contents)
        @path = path
        @contents = contents
      end

      def text
        @text ||= contents.dup.force_encoding(Encoding::UTF_8)
      end
    end

    class Metafile
      class Input < Struct.new(:bytes, :imports)
        def initialize(hash)
          super(hash["bytes"], hash["imports"])
        end
      end

      class Output < Struct.new(:imports, :exports, :entry_point, :inputs)
        class Input < Struct.new(:bytes_in_output)
          def initialize(hash)
            super(hash["bytesInOutput"])
          end
        end

        def initialize(hash)
          inputs = hash["inputs"].transform_values! { |v| Input.new(v) }
          super(hash["imports"], hash["exports"], hash["entryPoint"], inputs)
        end
      end

      attr_reader :inputs
      attr_reader :outputs

      def initialize(json)
        hash = JSON.parse(json)
        @inputs = hash["inputs"].transform_values! { |v| Input.new(v) }
        @outputs = hash["outputs"].transform_values! { |v| Output.new(v) }
      end
    end

    attr_reader :warnings
    attr_reader :output_files
    attr_reader :metafile
    def_delegators :@state, :stop, :rebuild, :dispose

    def initialize(response, state)
      @state = state
      @warnings = response["warnings"] # TODO: symbolize keys

      if response["outputFiles"]
        @output_files = response["outputFiles"].map { |f| OutputFile.new(f["path"], f["contents"]) }
      end

      if response["metafile"]
        @metafile = Metafile.new(response["metafile"])
      end
    end
  end
end
