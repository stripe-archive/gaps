require 'uri'
require 'rack'

module Gaps::Third
  module URIUtils
    # Use this instead of building URIs by hand.
    #
    # Query strings:
    #
    # >> Gaps::Third::URIUtils.build('/hello/there', :foo => 'bar')
    # => "/hello/there?foo=bar"
    #
    # (Also supports nested query strings, such as {:foo => {:bar => 'baz'}}.)
    #
    # Concatenating path components:
    #
    # >> Gaps::Third::URIUtils.build('/hello/there', 'malicious/data', 'rest', 'of', 'path')
    # => "/hello/there/malicious%2Fdata/rest/of/path"
    def self.build(base, *components)
      # Really want 'base, *components, query={}'
      if components.last.kind_of?(Hash)
        query = components.last
        components = components[0...-1]
      else
        query = {}
      end

      path = [base] + components.map {|c| Rack::Utils.escape(c)}
      joined_path = path.join('/')

      built = build_nested_query(query)
      if built && built.length > 0
        uri = URI.parse(joined_path)
        qs = (uri.query.nil? ? '?' : '&') + built
      else
        qs = ''
      end

      joined_path + qs
    end

    private

    # Forked from Rack's build_nested_query, because theirs:
    # a) just drops non-String values
    # b) doesn't handle nil nicely
    def self.build_nested_query(value, prefix = nil)
      case value
      when Array
        mapped = value.map { |v|
          build_nested_query(v, "#{prefix}[]")
        }.compact
        if mapped.length > 0
          mapped.join("&")
        else
          nil
        end
      when Hash
        mapped = value.map { |k, v|
          build_nested_query(v, prefix ? "#{prefix}[#{Rack::Utils.escape(k)}]" : Rack::Utils.escape(k))
        }.compact
        if mapped.length > 0
          mapped.join("&")
        else
          nil
        end
      when nil
        nil
      else
        raise ArgumentError, "value must be a Hash" if prefix.nil?
        value = value.to_s
        "#{prefix}=#{Rack::Utils.escape(value)}"
      end
    end
  end
end
