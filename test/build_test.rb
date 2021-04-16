require "test_helper"

class BuildTest < Minitest::Test
  def test_build_stdin
    result = Esbuild.build(stdin: {contents: %(export * from "./another-file"), sourcefile: "source.js"}, write: false, metafile: true)
    assert result.metafile.outputs["stdin.js"]
  end

  def test_build_not_found
    error = assert_raises Esbuild::BuildFailureError do
      Esbuild.build(entry_points: ["non-existent"])
    end
    assert_equal <<~ERROR.strip, error.message
      Build failed with 1 error:
      error: Could not resolve "non-existent"
    ERROR
  end
end
