require 'json'
module SyncedMemoryStore
  class PersistentStore < ActiveSupport::Cache::Store
    def initialize(cache:, **options)
      self.cache = cache
      super(options)
    end

    def read_multi(*names)
      cache.read_multi(*names)
    end

    private

    attr_accessor :cache

    def write_entry(key, entry, options)
      cache.send(:write_entry, key, entry, options)
    end

    def read_entry(key, options)
      cache.send(:read_entry, key, options)
    end


  end
end