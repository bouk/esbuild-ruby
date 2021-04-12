module Esbuild
  module Flags
    extend self

    class OneOf
      def initialize(*classes)
        @classes = classes
      end

      def ===(other)
        @classes.any? { |klass| klass === other }
      end

      def to_s
        @classes.join(" or ")
      end

      def self.[](*classes)
        new(*classes)
      end
    end

    BOOL = OneOf[true, false]
    STRING_OR_ARRAY = OneOf[String, Array]
    STRING_OR_OBJECT = OneOf[String, Hash]
    BOOL_OR_OBJECT = OneOf[BOOL, Hash]
    STRING_OR_BOOL = OneOf[String, BOOL]
    STRING_OR_SYMBOL = OneOf[String, Symbol]
    ARRAY_OR_OBJECT = OneOf[Array, Hash]

    def flags_for_transform_options(options)
      flags = []
      options = options.dup
      push_log_flags(flags, options, :silent)
      push_common_flags(flags, options)
      get_flag(options, :source_map, STRING_OR_BOOL) { |v| flags << "--source-map=#{v == true ? "external" : v}" if v }
      get_flag(options, :tsconfig_raw, STRING_OR_OBJECT) { |v| flags << "--tsconfig-raw=#{v.is_a?(String) ? v : JSON.dump(v)}" }
      get_flag(options, :source_file, String) { |v| flags << "--sourcefile=#{v}" }
      get_flag(options, :loader, STRING_OR_SYMBOL) { |v| flags << "--loader=#{v}" }
      get_flag(options, :banner, String) { |v| flags << "--banner=#{v}" }
      get_flag(options, :footer, String) { |v| flags << "--footer=#{v}" }
      raise ArgumentError, "Invalid option in transform() call: #{options.keys.first}" unless options.empty?
      flags
    end

    def flags_for_build_options(options)
      flags = []
      options = options.dup
      push_log_flags(flags, options, :info)
      push_common_flags(flags, options)
      get_flag(options, :source_map, STRING_OR_BOOL) { |v| flags << "--source-map#{v == true ? "" : "=#{v}"}" if v }
      get_flag(options, :bundle, BOOL) { |v| flags << "--bundle" if v }
      watch_mode = nil
      get_flag(options, :watch, BOOL_OR_OBJECT) do |v|
        break unless v
        flags << "--watch"
        watch_mode = {}
        unless v == true
          watch_options = v.dup
          get_flag(watch_options, :on_rebuild, Proc) { |v| watch_mode[:on_rebuild] = v }
          raise ArgumentError, "Invalid option in watch options: #{watch_options.keys.first}" unless watch_options.empty?
        end
      end
      get_flag(options, :splitting, BOOL) { |v| flags << "--splitting" if v }
      get_flag(options, :preserve_symlinks, BOOL) { |v| flags << "--preserve-symlinks" if v }
      get_flag(options, :metafile, BOOL) { |v| flags << "--metafile" if v }
      get_flag(options, :outfile, String) { |v| flags << "--outfile=#{v}" }
      get_flag(options, :outdir, String) { |v| flags << "--outdir=#{v}" }
      get_flag(options, :outbase, String) { |v| flags << "--outbase=#{v}" }
      get_flag(options, :platform, String) { |v| flags << "--platform=#{v}" }
      get_flag(options, :tsconfig, String) { |v| flags << "--tsconfig=#{v}" }
      get_flag(options, :resolve_extensions, Array) do |v|
        exts = v.map do |ext|
          ext = ext.to_s
          raise ArgumentError, "Invalid resolve extension: #{ext}" if ext.include?(",")
          ext
        end
        flags << "--resolve-extensions=#{exts.join(",")}"
      end
      get_flag(options, :public_path, String) { |v| flags << "--public-path=#{v}" }
      get_flag(options, :entry_names, String) { |v| flags << "--entry-names=#{v}" }
      get_flag(options, :chunk_names, String) { |v| flags << "--chunk-names=#{v}" }
      get_flag(options, :asset_names, String) { |v| flags << "--asset-names=#{v}" }
      get_flag(options, :main_fields, Array) do |v|
        values = v.map do |value|
          value = value.to_s
          raise ArgumentError, "Invalid main field: #{value}" if value.include?(",")
          value
        end
        flags << "--main-fields=#{values.join(",")}"
      end
      get_flag(options, :conditions, Array) do |v|
        values = v.map do |value|
          value = value.to_s
          raise ArgumentError, "Invalid condition: #{value}" if value.include?(",")
          value
        end
        flags << "--conditions=#{values.join(",")}"
      end
      get_flag(options, :external, Array) { |v| v.each { |name| flags << "--external:#{name}" } }
      get_flag(options, :banner, Hash) do |v|
        v.each do |type, value|
          raise ArgumentError, "Invalid banner file type: #{type}" if type.include?("=")
          flags << "--banner:#{type}=#{value}"
        end
      end
      get_flag(options, :footer, Hash) do |v|
        v.each do |type, value|
          raise ArgumentError, "Invalid footer file type: #{type}" if type.include?("=")
          flags << "--footer:#{type}=#{value}"
        end
      end
      get_flag(options, :inject, Array) { |v| v.each { |name| flags << "--inject:#{name}" } }
      get_flag(options, :loader, Hash) do |v|
        v.each do |ext, loader|
          raise ArgumentError, "Invalid loader extension: #{ext}" if ext.include?("=")
          flags << "--loader:#{ext}=#{loader}"
        end
      end
      get_flag(options, :out_extension, Hash) do |v|
        v.each do |ext, extension|
          raise ArgumentError, "Invalid out extension: #{ext}" if ext.include?("=")
          flags << "--out-extension:#{ext}=#{extension}"
        end
      end
      entries = []
      get_flag(options, :entry_points, ARRAY_OR_OBJECT) do |v|
        if v.is_a?(Array)
          v.each { |entry_point| entries << ["", entry_point] }
        else
          v.each { |key, entry_point| entries << [key.to_s, entry_point.to_s] }
        end
      end
      stdin_resolve_dir = nil
      stdin_contents = nil
      get_flag(options, :stdin, Hash) do |v|
        stdin_options = v.dup
        stdin_contents = ""
        get_flag(stdin_options, :contents, String) { |v| stdin_contents = v }
        get_flag(stdin_options, :resolve_dir, String) { |v| stdin_resolve_dir = v }
        get_flag(stdin_options, :sourcefile, String) { |v| flags << "--sourcefile=#{v}" }
        get_flag(stdin_options, :loader, String) { |v| flags << "--loader=#{v}" }
        raise ArgumentError, "Invalid option in stdin options: #{stdin_options.keys.first}" unless stdin_options.empty?
      end
      node_paths = []
      get_flag(options, :node_paths, Array) { |v| v.each { |path| node_paths << path.to_s } }
      write = true
      get_flag(options, :write, BOOL) { |v| write = v }
      abs_working_dir = nil
      get_flag(options, :abs_working_dir, String) { |v| abs_working_dir = v }
      incremental = false
      get_flag(options, :incremental, BOOL) { |v| incremental = v }
      raise ArgumentError, "Invalid option in build() call: #{options.keys.first}" unless options.empty?
      {
        entries: entries,
        flags: flags,
        write: write,
        stdin_contents: stdin_contents,
        stdin_resolve_dir: stdin_resolve_dir,
        abs_working_dir: abs_working_dir,
        incremental: incremental,
        node_paths: node_paths,
        watch: watch_mode
      }
    end

    def push_log_flags(flags, options, log_level_default)
      get_flag(options, :color, BOOL) { |v| flags << "--color=#{v}" if v }
      log_level = log_level_default
      get_flag(options, :log_level, STRING_OR_SYMBOL) { |v| log_level = v }
      flags << "--log-level=#{log_level}"
      log_limit = 0
      get_flag(options, :log_limit, Numeric) { |v| log_limit = v }
      flags << "--log-limit=#{log_limit}"
    end

    def push_common_flags(flags, options)
      get_flag(options, :source_root, String) { |v| flags << "--source-root=#{v}" }
      get_flag(options, :sources_content, BOOL) { |v| flags << "--sources-content=#{v}" }
      get_flag(options, :target, STRING_OR_ARRAY) do |v|
        v = [v] unless Array === v
        targets = v.map do |t|
          t = t.to_s
          raise ArgumentError, "Invalid target: #{t}" if t.include?(",")
          t
        end
        flags << "--target=#{targets.join(",")}"
      end
      get_flag(options, :format, String) { |v| flags << "--format=#{v}" }
      get_flag(options, :global_name, String) { |v| flags << "--global-name=#{v}" }
      get_flag(options, :minify, BOOL) { |v| flags << "--minify" if v }
      get_flag(options, :minify_syntax, BOOL) { |v| flags << "--minify-syntax" if v }
      get_flag(options, :minify_whitespace, BOOL) { |v| flags << "--minify-whitespace" if v }
      get_flag(options, :minify_identifiers, BOOL) { |v| flags << "--minify-identifiers" if v }
      get_flag(options, :charset, String) { |v| flags << "--charset=#{v}" }
      get_flag(options, :tree_shaking, STRING_OR_BOOL) { |v| flags << "--tree-shaking=#{v}" if v != true }
      get_flag(options, :jsx_factory, String) { |v| flags << "--jsx-factory=#{v}" }
      get_flag(options, :jsx_fragment, String) { |v| flags << "--jsx-fragment=#{v}" }
      get_flag(options, :define, Hash) do |v|
        v.each do |key, value|
          raise "Invalid define: #{key}" if key.include? "="
          flags << "--define:#{key}=#{value}"
        end
      end
      get_flag(options, :pure, Array) do |v|
        v.each { |fn| flags << "--pure:#{fn}" }
      end
      get_flag(options, :keep_names, BOOL) { |v| flags << "--keep-names" if v }
    end

    def get_flag(options, sym, check)
      return unless options.has_key?(sym)
      value = options.delete(sym)
      raise "#{sym} must be #{check}" unless check === value
      yield value
    end
  end
end
