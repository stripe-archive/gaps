require 'restclient'
require 'mail'

module Gaps
  module Email
    include Chalk::Log

    def self.send_email(opts)
      mail = Mail.new(opts)

      if configatron.notify.send_email
        mail.delivery_method :sendmail
        mail.deliver!
      else
        log.info("Would have sent", email: mail.to_s)
      end
    end
  end
end
