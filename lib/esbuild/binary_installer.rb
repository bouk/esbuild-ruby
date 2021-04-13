require_relative "version"
require "fileutils"
require "open3"
require "net/https"

module Esbuild
  class BinaryInstaller
    KNOWN_UNIX_LIKE_PACKAGES = {
      "arm64-darwin20" => "esbuild-darwin-arm64",
      "x86_64-linux" => "esbuild-linux-64",
      "x86_64-darwin" => "esbuild-darwin-64"
    }

    attr_reader :platform, :path
    def initialize(platform, path)
      package = KNOWN_UNIX_LIKE_PACKAGES[platform]
      raise ArgumentError, "Unknown platform #{platform}" unless package
      @package = package
      @path = path
    end

    def install
      tempfile = "#{@path}__"
      if ENV["ESBUILD_BINARY_PATH"]
        FileUtils.cp(ENV["ESBUILD_BINARY_PATH"], tempfile)
      else
        # TODO: use cache
        download(tempfile)
      end

      validate_binary_version!(tempfile)
      FileUtils.mv(tempfile, @path)
    end

    private

    def download(target)
      url = "https://unpkg.com/#{@package}@#{ESBUILD_VERSION}/bin/esbuild"
      warn "Downloading esbuild binary from #{url}"

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.start do
        request = Net::HTTP::Get.new uri
        http.request(request) do |response|
          File.open(target, "wb", 0o755) do |f|
            response.read_body(f)
          end
        end
      end
    end

    def validate_binary_version!(path)
      version, _ = Open3.capture2(path, "--version")
      version = version.strip
      raise "Expected #{ESBUILD_VERSION} but got #{version}" unless ESBUILD_VERSION == version
    end
  end
end
