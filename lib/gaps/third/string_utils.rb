require 'securerandom'

module Gaps::Third
  module StringUtils
    def self.random(len=10, opts={})
      regexp = if opts[:alpha]
                 /[^A-Za-z]/
               elsif opts[:numeric]
                 /[^0-9]/
               else
                 /[^A-Za-z0-9]/
               end

      str = SecureRandom.random_bytes(len * 24).gsub(regexp, '')
      if str.size >= len
        str[0..(len-1)]
      else
        # should basically never happen
        random(len, opts)
      end
    end
  end
end
