module Gaps::DB
  class State < Base
    set_collection_name 'state'

    key :key, String
    key :value, String

    def self.build_index
      self.ensure_index([[:google_id]], unique: true)
    end

    def self.mark_initialized
      log.info('Successfully initialized group database')
      # Ignore errors if a duplicate is created
      self.create(key: 'initialized', value: 'yes')
    end

    def self.initialized?
      self.exists?(key: 'initialized', value: 'yes')
    end
  end
end
