require 'rack-flash'

module Rack
  class Flash
    class FlashHash
      def [](key)
        key = key.to_s
        cache[key] ||= values.delete(key)
      end

      def []=(key,val)
        key = key.to_s
        cache[key] = values[key] = val
      end
    end
  end
end
