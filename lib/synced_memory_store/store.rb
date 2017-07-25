module SyncedMemoryStore
  class Store < ActiveSupport::Cache::MemoryStore
    include MonitorMixin

    def initialize(cache:, redis: Redis.new(url: ENV['REDIS_URL']).client, subscriber: SyncedMemoryStore::Subscriber.instance, **options)
      self.persistent_store = cache
      self.redis = redis
      subscriber.subscribe self
      super(options)
    end

    def write(key, entry, options = {})
      options = merged_options(options)
      super.tap do
        persistent_store.write(key, entry, options)
        inform_others_of_write(normalize_key(key, options), entry, options)
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
        persistent_store.fetch(name, options) do
          if block_given?
            value = yield name
            throw :abort, value
          else
            throw :abort, nil # Do not write to cache if it doesnt exist
          end

        end
      end
    end

    private

    def save_block_result_to_cache(name, options)
      catch(:abort) do
        super
      end
    end

    def inform_others_of_write(key, entry, options)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, JSON.dump([{key: key, entry: entry, options: options}])])
      end
    end

    def inform_others_of_writes(writes)
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, JSON.dump(writes)])
      end
    end

    attr_accessor :persistent_store, :redis
  end
end
