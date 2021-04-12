module Esbuild
  class TransformResult
    attr_reader :code, :map, :warnings

    def initialize(result)
      @code = read_file(result["codeFS"], result["code"])
      @map = read_file(result["mapFS"], result["map"])
      @warnings = result["warnings"]
    end

    private

    # If the files are too big, esbuild will create a tempfile to pass back the result
    # We need to delete it
    def read_file(fs, name)
      if fs
        contents = File.read(name)
        File.delete(name)
        contents
      else
        name
      end
    end
  end
end
