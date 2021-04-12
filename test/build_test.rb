require "test_helper"

class BuildTest < Minitest::Test
  def test_build_stdin
    result = Esbuild.build(stdin: {contents: %(export * from "./another-file"), sourcefile: "source.js"}, write: false, metafile: true)
    assert result.metafile.outputs["stdin.js"]
  end
end
