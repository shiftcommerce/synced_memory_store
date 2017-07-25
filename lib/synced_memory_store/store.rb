module SyncedMemoryStore
  class Store < ActiveSupport::Cache::MemoryStore
    def initialize(cache:, redis_url: :from_cache, subscriber: SyncedMemoryStore::Subscriber.instance, **options)
      self.persistent_store = PersistentStore.new(cache: cache, redis_url: redis_url)
      subscriber.subscribe self
      super(options)
    end

    def write_entry(key, entry, persist: true, **options)
      super.tap do |result|
        persistent_store.send(:write_entry, key, entry, options) if result && persist
      end
    end

    def fetch_multi(*names, &block)
      raise ArgumentError, "Missing block: `#{self.class.name}#fetch_multi` requires a block." unless block_given?
      options = names.extract_options!
      options = merged_options(options)
      results = read_multi(*names, options)

      missing_keys = (names - results.keys)
      return results if missing_keys.empty?
      results.merge(persistent_store.fetch_and_sync_multi(*missing_keys, &block))
    end

    def fetch(name, options = nil, &block)
      super do
        persistent_store.fetch(name, options) do
          throw :abort unless block_given? # Do not write to cache if it doesnt exist
          yield name
        end
      end
    end

    private

    def save_block_result_to_cache(name, options)
      catch(:abort) do
        super
      end
    end

    attr_accessor :persistent_store
  end
end
