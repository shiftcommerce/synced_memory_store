module SyncedMemoryStore
  # An in memory cache store, backed by a secondary cache and synced across processes
  #
  # This allows each process to have a rapid in memory cache, knowing that when a key is added, deleted or updated
  # by another process then it is updated automatically.
  class Store < ActiveSupport::Cache::MemoryStore
    include MonitorMixin
    attr_reader :uuid

    # Creates a new instance registered with the subscriber for updates
    # @param [ActiveSupport::Cache::Store] cache - The cache store to use for persistent storage - i.e. memcache, redis etc..
    # @param [Boolean] sync - If true (true by default) - then the store is kept in sync using redis
    # @param [Boolean] force_miss - If true (false by default) - then the store forces a cache miss on all requests
    # @param [Redis::Client] redis - The redis client to use - defaults to a new redis client with url set by ENV['REDIS_URL']
    # @param [SyncedMemoryStore::Subscriber] subscriber - The single subscriber to register itself with (defaults to a global instance)
    # @param [Hash] options - Standard options for a cache store
    def initialize(cache:, sync: true, redis: Redis.new(url: ENV['REDIS_URL']).client, subscriber: SyncedMemoryStore::Subscriber.instance, force_miss: false, **options)
      self.cache = cache
      self.sync = sync
      self.redis = redis
      self.uuid = SecureRandom.uuid
      self.force_miss = force_miss
      subscriber.subscribe self if sync
      super(options)
    end

    # Stores the value in the memory cache and in the secondary cache
    # @param [String] key - The key to cache the value against
    # @param [Object] entry - The value - will be serialized using Marshal.dump
    # @param [Boolean] persist - If set to false, the value will not be persisted in the secondary cache
    # @param [Hash] options - Normal options for a cache write
    def write(key, entry, persist: true, **options)
      options = merged_options(options)
      super(key, entry, options).tap do
        cache.write(key, entry, options) if persist
      end
    end

    # Fetches multiple values from the cache - any misses will be attempted to be fetched from
    # the secondary cache and if that misses - the block is called (if passed) or the key is not fetched
    # @param [String] key1
    # @param [String] key2
    # @param [String] key..n
    # @return [Hash] Hash containing keys and values from the cache
    def fetch_multi(*names, &block)
      raise ArgumentError, "Missing block: `#{self.class.name}#fetch_multi` requires a block." unless block_given?
      return fetch_multi_with_forced_miss(*names, &block) if force_miss
      options = names.extract_options!
      options = merged_options(options)
      results = read_multi(*names, options)

      missing_keys = (names - results.keys)
      return results if missing_keys.empty?
      results.merge(cache.fetch_multi(*missing_keys, &block))
    end

    # Fetches a single key from the cache - a miss will then be attempted from the secondary cache
    # and a miss from that, the block will be called or nil returned
    # @param [String] name - The key to fetch
    # @param [Hash] options - The options for a standard fetch from any cache
    def fetch(name, options = nil, &block)
      return yield if force_miss
      super do
        cache.fetch(name, options, &block)
      end
    end

    # Deletes a key from the cache and the secondary cache
    # also informs other registered cache instances to do the same
    # @param [String] name - The key to delete
    # @param [Boolean] silent - If true (defaults to false) then no other instances are told of this delete
    # @param [Boolean] persist - If true (defaults to true) then the delete will also be done on the secondary cache
    # @param [Hash] options - Standard cache options
    def delete(name, silent: false, persist: true, **options)
      super(name, options).tap do
        cache.delete(name, options) if persist
        inform_others_of_delete(name, options) unless silent or !sync
      end
    end

    def clear(silent: false, persist: true, **options)
      super(options).tap do
        cache.clear if persist
        inform_others_of_clear(options) unless silent or !sync
      end
    end

    # Used internally as a public interface to write_entry - this is used by the subscriber
    # @private
    # @param [String] key - The key
    # @param [ActiveSupport::Cache::Entry] value - The value
    # @param [Hash] options - Standard cache options
    def write_from_subscriber(key, value, options)
      write_entry(key, value, options)
    end

    private

    def fetch_multi_with_forced_miss(*names, &block)
      names.inject({}) do |acc, key|
        acc[key] = yield key
        acc
      end
    end

    def write_entry(key, entry, silent: false, **options)
      super(key, entry, options).tap do
        inform_others_of_write(key, entry, options) unless silent or !sync
      end
    end

    def save_block_result_to_cache(name, options)
      super(name, silent: true, **options)
    end

    def inform_others_of_write(key, entry, options)
      return unless sync
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_writes, Marshal.dump({key: key, entry: entry, options: options, sender_uuid: uuid})])
      end
    end

    def inform_others_of_delete(key, options)
      return unless sync
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_deletes, Marshal.dump({key: key, sender_uuid: uuid})])
      end
    end

    def inform_others_of_clear(options)
      return unless sync
      mon_synchronize do
        redis.call([:publish, :synced_memory_store_clears, Marshal.dump({sender_uuid: uuid})])
      end
    end

    attr_accessor :cache, :redis, :sync, :force_miss
    attr_writer :uuid
  end
end
