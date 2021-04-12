require "test_helper"

class TransformTest < Minitest::Test
  def test_transform_ts
    result = Esbuild.transform("let x: number = 1", loader: :ts)
    assert_equal "let x = 1;\n", result.code
  end
end
