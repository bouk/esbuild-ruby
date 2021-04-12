require "forwardable"

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
        @metafile = JSON.parse(response["metafile"], symbolize_names: true)
      end
    end
  end
end
