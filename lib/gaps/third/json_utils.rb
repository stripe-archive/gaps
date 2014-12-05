require 'json'

module Gaps::Third
  module JSONUtils
    ESCAPED_CHARS = {
      '>'    =>  '\u003E',
      '<'    =>  '\u003C',
      '&'    =>  '\u0026'
    }

    ESCAPE_REGEX = /[<>&]/

    # This method is SECURITY CRITICAL.
    def self.make_json_safe!
      JSON.instance_eval do
        # Don't allow JSON to instantiate arbitrary types. Why would
        # you ever want your JSON parser to do that?!?
        alias unsafe_parse parse
        def parse(json, args={})
          unsafe_parse(json, args.merge(:create_additions => false))
        end

        # Your browser will stop parsing a <script> tag as soon as it
        # hits a </script>. So we should make sure to escape
        # </script>s, in case someone echos a user-controlled JSON
        # blob into a page.
        alias unsafe_pretty_generate pretty_generate
        def pretty_generate(obj)
          Gaps::Third::JSONUtils.escape_entities(unsafe_pretty_generate(obj))
        end

        alias unsafe_dump dump
        def dump(obj)
          Gaps::Third::JSONUtils.escape_entities(unsafe_dump(obj))
        end

        alias unsafe_generate generate
        def generate(obj, *args)
          Gaps::Third::JSONUtils.escape_entities(unsafe_generate(obj, *args))
        end
      end
    end

    def self.escape_entities(json_string)
      json_string.gsub(ESCAPE_REGEX) { |s| ESCAPED_CHARS[s] }
    end
  end
end
