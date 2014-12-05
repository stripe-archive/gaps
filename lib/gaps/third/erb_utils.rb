module Gaps::Third
  module ERBUtils
    module Autoescape
      def initialize(*args, &blk)
        # A bit unfortunate to require dynamically. However, this is a
        # nice interface to have.
        require 'erubis'
        Tilt.prefer(Tilt::ErubisTemplate, :erb)
        super
      end

      def erb(template, options={}, locals={})
        options.merge!(:escape_html => true)
        super
      end
    end
  end
end
