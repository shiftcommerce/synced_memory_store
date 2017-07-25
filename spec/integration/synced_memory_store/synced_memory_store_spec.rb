require 'spec_helper'
require 'synced_memory_store/store'
RSpec.describe SyncedMemoryStore::Store do
  # In the test, we wait for the subscriber to make the test more predictable
  let!(:subscriber) { SyncedMemoryStore::Subscriber.instance(wait: true) }
  let!(:redis) { Redis.new(url: ENV['REDIS_URL']).client }
  context "using two isolated instances with a redis underlying cache" do
    let(:cache_1) { ActiveSupport::Cache::RedisStore.new(ENV.fetch('REDIS_URL')) }
    let(:cache_2) { ActiveSupport::Cache::RedisStore.new(ENV.fetch('REDIS_URL')) }
    let!(:instance_1) { SyncedMemoryStore::Store.new(cache: cache_1, redis: redis, subscriber: subscriber) }
    let!(:instance_2) { SyncedMemoryStore::Store.new(cache: cache_2, redis: redis, subscriber: subscriber) }
    it "Should add to instance 2 when a new key is added to instance 1" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end

    it "Should add to instance 2 when a new key is added to instance 1 from a read miss" do
      instance_1.fetch("key_1") do
        "key_1 value"
      end
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end
  end

  context "using two isolated instances with a mocked underlying cache" do
    let(:cache_1) { ActiveSupport::Cache::MemoryStore.new }
    let(:cache_2) { ActiveSupport::Cache::MemoryStore.new }
    let!(:instance_1) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_1) }
    let!(:instance_2) { SyncedMemoryStore::Store.new(redis: redis, cache: cache_2) }
    it "Should add to instance 2 when a new key is added to instance 1 using write" do
      instance_1.write("key_1", "key_1 value")
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")
    end

    it "Should not add to instance 2 when a new key is added to instance 1 from a read miss" do
      instance_1.fetch("key_1") do
        "key_1 value"
      end
      wait_for { instance_2.fetch("key_1") }.not_to eq("key_1 value")
    end

    it "should fetch the value from underlying cache and send to others if it doesnt have it" do
      cache_1.write("key_1", "key_1 value")
      instance_1.fetch("key_1") do
        raise "It should not get here"
      end
      wait_for { instance_2.fetch("key_1") }.to eq("key_1 value")

    end


    it "should fetch multiple values from underlying cache and send to others in batch if it doesnt have some of them" do
      # Arrange - Sleep for 10 ms first to allow thread to start for the subscriber
      #expect(cache_1).to receive(:fetch_multi).with("key_1", "key_2").and_return({ 'key_1' => 'key_1 value' })
      cache_1.write("key_1", "key_1 value")
      # Act - Fetch the 2 keys
      instance_1.fetch_multi("key_1", "key_2") do |missing_key|
        "#{missing_key} value"
      end

      # Assert - Make sure both keys are available and that the key was stored in cache_1 and not cache_2
      wait_for { instance_2.fetch("key_1") }.not_to eq("key_1 value")
      wait_for { instance_2.fetch("key_2") }.not_to eq("key_2 value")

      # It should store in underlying cache for the instance where set only
      expect(cache_1.fetch("key_2")).to eq("key_2 value")
      expect(cache_2.fetch("key_2")).to be_nil
    end

    it 'should not ask underlying cache if it has values already'
    it 'should ask underylying cache for values it does not have already in a multi fetch'

  end
end