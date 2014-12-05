module Gaps::DB
  class Cache < Base
    include Chalk::Log
    set_collection_name 'cache'

    key :key, String
    key :value, Object
    key :expires, Time

    @cache = {}
    @mutex = Mutex.new
    @cache_lookup = Thread.channel

    def self.thread_pool
      @thread_pool ||= Thread::Pool.new(configatron.cache.pool_size)
    end

    def self.warm_cache
      self.find_each do |entry|
        @cache[entry.key] = entry
      end
    end

    def self.start_cache_lookup
      Thread.new do
        warm_cache

        pending = {}

        while lookup = @cache_lookup.receive
          key, blk, optimistic, final = lookup
          cache_lookup(pending, key, blk, optimistic, final)
        end
      end
    end

    def self.cache_lookup(pending, key, blk, optimistic, final)
      entry = nil

      @mutex.synchronize do
        entry = @cache[key] ||= self.new(key: key)

        # If the cache entry is still active, just be done with it.
        if entry.active?
          optimistic << entry.value
          final << entry.value
          return
        end

        on_complete = pending[key] ||= []

        if entry.populated?
          # We have an old cached value to return optimistically
          optimistic << entry.value
          on_complete << final
        else
          # Sorry we've got nothing; going to have to wait
          on_complete << optimistic
          on_complete << final
        end
      end

      # Refresh the value in a separate thread
      task = self.thread_pool.process do
        log.info('Refreshing cache', key: key)

        begin
          value = blk.call
        rescue Exception => e
          # TODO: make the thread pool library have better
          # error-handling
          e.message << ' (raised from thread pool)'
          Thread.main.raise(e)
        end

        @mutex.synchronize do
          entry.persist!(value)

          pending = pending.delete(key)
          pending.each {|promise| promise << value}
        end
      end
    end

    def persist!(value)
      self.value = value
      self.expires = Time.now + 60 * 60 + rand * 60
      self.save!
    end

    def self.with_cache_key(key, &blk)
      optimistic = Thread.promise
      final = Thread.promise

      @cache_lookup.send([key, blk, optimistic, final])

      # Block on the cache entry completing if needed
      if configatron.cache.allow_stale
        ~optimistic
      else
        ~final
      end
    end

    def self.purge!
      log.info("Purging entire cache")

      @mutex.synchronize do
        @cache = {}
        self.collection.drop
        build_index
      end
    end

    def self.build_index
      self.ensure_index([[:key, -1]], unique: true)
    end

    def active?
      expires && Time.now < expires
    end

    def populated?
      expires
    end
  end
end
