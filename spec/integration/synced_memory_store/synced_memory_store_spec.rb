require 'spec_helper'
require 'synced_memory_store/store'
require 'active_support/cache/redis_store'
require 'active_support/tagged_logging'
require 'ostruct'
# The following tests are divided into 2 contexts
# First, with a secondary cache which is backed by a central store (redis is used)
#  this proves that we can get values from it and write to it when needed
# Second, with a secondary cache that is in memory and therefore isolated
#  this is used when proving the synchronisation as there is no other place
#  for the data to have come from, so synchronisation must have worked.
RSpec.describe SyncedMemoryStore::Store do
  # In the test, we wait for the subscriber to make the test more predictable
  let(:logger) { ActiveSupport::TaggedLogging.new(Logger.new(STDOUT)) }
  let!(:subscriber) { SyncedMemoryStore::Subscriber.instance().tap {|i| i.configure(logger: logger).start(wait: true)} }
  let!(:redis) { Redis.new(url: ENV['REDIS_URL']).tap { |r| r.flushdb }.client }
  before(:each) { subscriber.reset! }

  context "using two isolated instances with a redis underlying cache" do
    let(:cache_1) { ActiveSupport::Cache::RedisStore.new(ENV['REDIS_URL']) }
    let(:cache_2) { ActiveSupport::Cache::RedisStore.new(ENV['REDIS_URL']) }
    let!(:instance_1) { SyncedMemoryStore::Store.new(cache: cache_1, redis: redis, subscriber: subscriber) }
    let!(:instance_2) { SyncedMemoryStore::Store.new(cache: cache_2, redis: redis, subscriber: subscriber) }

    it "Should add to instance 2 when a new key is added to instance 1" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end

    it "should remove from instance 2 if a key is removed from instance 1" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
      instance_1.delete("key_1")
      wait_for { instance_2.fetch("key_1") }.not_to eq("key_1 value")
    end

    it "should update instance 2 if instance 1 has a key updated" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
      instance_1.write("key_1", "key_1 updated_value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 updated_value")
    end

    it "should fetch new cached value from redis when a new key is added to instance 1 from a read miss" do
      instance_1.fetch("key_1") do
        "key_1 value"
      end
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end
  end

  context "using two isolated instances with isolated memory caches" do
    let(:cache_1) { ActiveSupport::Cache::MemoryStore.new }
    let(:cache_2) { ActiveSupport::Cache::MemoryStore.new }
    let!(:instance_1) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_1) }
    let!(:instance_2) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_2) }
    it "Should add to instance 2 when a new key is added to instance 1 using write" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end

    it "should fetch the value from underlying cache and send to others if it doesnt have it" do
      cache_1.write("key_1", "key_1 value")
      instance_1.fetch("key_1") do
        raise "It should not get here"
      end
    end

    it "should fetch multiple values from underlying cache" do
      cache_1.write("key_1", "key_1 value")
      # Act - Fetch the 2 keys
      instance_1.fetch_multi("key_1", "key_2") do |missing_key|
        "#{missing_key} value"
      end

      # Assert - It should store in underlying cache for the instance where set only
      expect(cache_1.fetch("key_2")).to eq("key_2 value")
      expect(cache_2.fetch("key_2")).to be_nil
    end

    it "should add an object to instance 2 when a new key is added to instance 1" do
      value = OpenStruct.new(name: "Im an openstruct", big_value: ("*" * 2048))
      instance_1.write("key_1", value, compress: true, compress_threshold: 2.kilobytes)
      wait_for { instance_2.fetch("key_1") }.to eq value
    end

    it "should remove from instance 2 if a key is removed from instance 1" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
      instance_1.delete("key_1")
      wait_for { instance_2.fetch("key_1") }.not_to eq("key_1 value")
    end

    it "should update instance 2 if instance 1 has a key updated" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
      instance_1.write("key_1", "key_1 updated_value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 updated_value")
    end

    it "should reset instance 2 if instance 1 is cleared" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
      instance_1.clear
      wait_for { instance_2.fetch("key_1") }.not_to eq("key_1 value")
    end
  end

  context "using two isolated instances with isolated memory caches with force miss set to true" do
    let(:cache_1) { ActiveSupport::Cache::MemoryStore.new }
    let(:cache_2) { ActiveSupport::Cache::MemoryStore.new }
    let!(:instance_1) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_1, force_miss: true) }
    let!(:instance_2) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_2, force_miss: true) }
    it "should return the value of the block without accessing the cache using fetch" do
      instance_1.write("key_1", "old value")
      value = instance_1.fetch("key_1") do
        "correct_value"
      end
      expect(value).to eql "correct_value"
    end

    it "should return the values from the block without accessing the cache using fetch_multi" do
      instance_1.write("key_1", "old_value_1")
      instance_1.write("key_2", "old_value_2")
      values = instance_1.fetch_multi("key_1", "key_2") do |key|
        "correct_value_for_#{key}"
      end
      expect(values).to eql("key_1" => "correct_value_for_key_1", "key_2" => "correct_value_for_key_2")
    end
  end
end
