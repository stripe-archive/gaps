module Gaps::Third
  module YAMLUtils
    def self.make_yaml_safe!
      # Make syck-based YAML safe
      require 'yaml'
      begin
        require 'syck'
        case RUBY_VERSION
        when /\A1\.8/
          syckmod = YAML
        else
          syckmod = Syck
        end

        whitelist_classes = [String, Hash, Symbol, Float, Array,
          TrueClass, FalseClass, Integer,
          Time, Date, NilClass]
        syckmod.tagged_classes.delete_if { |k,v| !whitelist_classes.include?(v) }
        syckmod.tagged_classes.freeze
      rescue LoadError
        unless RUBY_VERSION >= '2.0.0'
          raise 'Could not load Syck to patch it, but not running under Ruby >=2.0'
        end
      end

      # Make psych-based (1.9 / 2.x) YAML safe
      if defined?(Psych)
        Psych.const_set("UnsafeYAML", Class.new(StandardError))
        Psych.module_eval do
          def self.load(yaml, *args)
            result = parse(yaml, *args)
            check_safety(result)
            result ? result.to_ruby : result
          end

          private
          def self.check_safety(o)
            check_node(o)
            case o
            when Psych::Nodes::Scalar
            when Psych::Nodes::Sequence
              o.children.each {|child| check_safety(child)}
            when Psych::Nodes::Mapping
              o.children.each {|child| check_safety(child)}
            when Psych::Nodes::Document
              check_safety(o.root)
            when Psych::Nodes::Stream
              o.children.each {|child| check_safety(child)}
            when Psych::Nodes::Alias
            else
              raise Psych::UnsafeYAML.new("Found unknown node type: #{o.class}")
            end
          end

          def self.check_node(n)
            unless n.tag.nil? || ['!', '!ruby/sym', '!ruby/symbol'].include?(n.tag)
              raise Psych::UnsafeYAML.new("Found node with tag: #{n.tag}")
            end
          end
        end

        # Force the default engine back to Psych, since we require'd
        # Syck.
        YAML::ENGINE.yamler = 'psych'
      end
    end

    # Clean up an arbitrary object so that it would be safe to load.
    #
    # Current munging steps: Set => Array
    #
    # @param [Object] object The object to make safe
    # @param [Hash] options
    #
    # @option options [Boolean] :munge (true) Whether to perform munging steps
    #   on objects that are not safe but can be munged into a safe object
    #
    # @return [Object]
    #
    # @raises TypeError if object cannot be made safe for YAML
    #
    def self.clean_for_yaml(object, options={})
      options = {munge: true}.merge(options)

      case object
      when Array
        object.map {|val| clean_for_yaml(val, options) }
      when Hash
        hash = {}
        object.each_pair do |key, val|
          hash[clean_for_yaml(key)] = clean_for_yaml(val, options)
        end
        hash
      when String, Symbol, Float, Integer, TrueClass, FalseClass, Date, Time,
        NilClass
        object
      else
        if options.fetch(:munge)
          case object
          when Set
            return object.map { |val| clean_for_yaml(val) }
          end
        end
        raise TypeError.new("Invalid object for safe YAML: #{object.inspect}")
      end
    end
  end
end
