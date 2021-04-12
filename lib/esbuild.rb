# frozen_string_literal: true

require_relative "esbuild/version"
require_relative "esbuild/packet"
require_relative "esbuild/stdio_protocol"
require_relative "esbuild/service"

module Esbuild
  class << self
    def build(options)
      service.build_or_serve(options)
    end

    def serve(serve_options, build_options)
      service.build_or_serve(build_options, serve_options)
    end

    def transform(input, options = {})
      service.transform(input, options)
    end

    private

    def service
      @service ||= Service.new
    end
  end
end
