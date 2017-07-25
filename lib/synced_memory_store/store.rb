module SyncedMemoryStore
  class Store < ActiveSupport::Cache::MemoryStore
    include MonitorMixin

    def initialize(cache:, redis: Redis.new(url: ENV['REDIS_URL']).client, subscriber: SyncedMemoryStore::Subscriber.instance, **options)
      self.persistent_store = cache
      self.redis = redis
      subscriber.subscribe self
      super(options)
    end

    def write(key, entry, silent: false, persist: true, **options)
      options = merged_options(options)
      super(key, entry, options).tap do
        persistent_store.write(key, entry, options) if persist
        inform_others_of_write(normalize_key(key, options), entry, options) unless silent
      end
    end

    def fetch_multi(*names, &block)
      raise ArgumentError, "Missing block: `#{self.class.name}#fetch_multi` requires a block." unless block_given?
      options = names.extract_options!
      options = merged_options(options)
      results = read_multi(*names, options)

      missing_keys = (names - results.keys)
      return results if missing_keys.empty?
      results.merge(persistent_store.fetch_multi(*missing_keys, &block))
    end

    def fetch(name, options = nil, &block)
      super do
        persistent_store.fetch(name, options, &block)
      end
    end

    def delete(name, silent: false, persist: true, **options)
      super(name, options).tap do
        persistent_store.delete(name, options) if persist
        inform_others_of_delete(name, options) unless silent
      end
    end

    private

    def save_block_result_to_cache(name, options)
      super(name, silent: true, **options)
    end

    def inform_others_of_write(key, entry, options)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, JSON.dump([{key: key, entry: entry, options: options}])])
      end
    end

    def inform_others_of_delete(key, options)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_deletes, key])
      end
    end

    attr_accessor :persistent_store, :redis
  end
end
