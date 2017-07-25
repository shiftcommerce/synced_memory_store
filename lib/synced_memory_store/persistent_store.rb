require 'json'
module SyncedMemoryStore
  class PersistentStore < ActiveSupport::Cache::Store
    include MonitorMixin

    def initialize(cache:, redis_url: :from_cache, **options)
      self.cache = cache
      self.redis_url = redis_url
      super(options)
    end

    def read_multi(*names)
      cache.read_multi(*names)
    end

    def fetch_and_sync_multi(*names, &block)
      raise ArgumentError, "Missing block: `#{self.class.name}#fetch_and_sync_multi` requires a block." unless block_given?

      options = names.extract_options!
      options = merged_options(options)

      fetch_multi(*names, &block).tap do |h|
        writes = h.inject([]) do |memo, (key, entry)|
          memo << {key: key, entry: entry, options: options}
        end
        inform_others_of_writes(writes)
      end
    end

    private

    attr_accessor :cache, :redis_url

    def write_entry(key, entry, options)
      cache.send(:write_entry, key, entry, options).tap do |result|
        inform_others_of_write(key, entry, options)
      end
    end

    def read_entry(key, options)
      cache.send(:read_entry, key, options)
    end


    def inform_others_of_write(key, entry, options)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, JSON.dump([{key: key, entry: entry.value, options: options}])])
      end
    end

    def inform_others_of_writes(writes)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, JSON.dump(writes)])
      end
    end

    def redis
      @redis ||= if redis_url == :from_cache
        cache.data.client
      else
        Redis.new(url: redis_url).client
      end
    end
  end
end