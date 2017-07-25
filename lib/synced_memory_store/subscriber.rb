require 'redis'
module SyncedMemoryStore
  class Subscriber
    def self.instance
      Thread.current[:synced_memory_store] ||= new.tap do |instance|
        instance.configure
        instance.start
      end
    end

    def subscribe(cache_instance)
      subscriptions << cache_instance unless subscriptions.include?(cache_instance)
    end

    def configure
      self.subscriptions = []
    end

    def start
      self.thread = Thread.new do
        begin
          redis.subscribe(:synced_memory_store_writes) do |on|
            on.subscribe do |channel, subscriptions|
              puts "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
            end

            on.message do |channel, message|
              puts "##{channel}: #{message}"
              messages = JSON.parse(message)
              subscriptions.each do |cache_instance|
                messages.each do |message_decoded|
                  entry = ActiveSupport::Cache::Entry.new(message_decoded['entry'], message_decoded['options'])
                  cache_instance.send(:write_entry, message_decoded['key'], entry, message_decoded['options'].merge(persist: false))
                end
              end
              redis.unsubscribe if message == "exit"
            end

            on.unsubscribe do |channel, subscriptions|
              puts "Unsubscribed from ##{channel} (#{subscriptions} subscriptions)"
            end
          end
        rescue Redis::BaseConnectionError => error
          puts "#{error}, retrying in 1s"
          sleep 1
          retry
        rescue Exception => ex
          raise
        end
      end
    end

    private

    def redis
      @redis ||= Redis.new
    end

    attr_accessor :thread, :subscriptions

    private_class_method :initialize
    private_class_method :new
  end
end
redis = Redis.new

