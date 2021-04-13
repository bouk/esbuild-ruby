# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rake/testtask"
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task :download_binary do
  require_relative "lib/esbuild/binary_installer"
  esbuild_bin = File.join(__dir__, "bin", "esbuild")
  installer = Esbuild::BinaryInstaller.new(RUBY_PLATFORM, esbuild_bin)
  installer.install
end

task default: :download_binary
