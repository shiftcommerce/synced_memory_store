require 'redis'
module SyncedMemoryStore
  class Subscriber
    def self.instance(wait: false)
      Thread.current[:synced_memory_store] ||= new.tap do |instance|
        instance.configure
        instance.start(wait: wait)
      end
    end

    def subscribe(cache_instance)
      subscriptions << cache_instance unless subscriptions.include?(cache_instance)
    end

    def configure
      self.subscribed = false
      self.subscriptions = []
    end

    def start(wait: false)
      start_thread
      if wait
        wait_for_subscription
      end
    end

    def start_thread
      self.thread = Thread.new do
        begin
          redis.subscribe(:synced_memory_store_writes, :synced_memory_store_deletes) do |on|
            on.subscribe do |channel, subscriptions|
              puts "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
              self.subscribed = true
            end

            on.message do |channel, message|
              puts "##{channel}: #{message}"
              send("on_#{channel}".to_sym, message)
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

    def on_synced_memory_store_writes(message)
      messages = JSON.parse(message)
      subscriptions.each do |cache_instance|
        messages.each do |message_decoded|
          cache_instance.write(message_decoded['key'], message_decoded['entry'], silent: true, persist: false, **message_decoded['options'])
        end
      end
    end

    def on_synced_memory_store_deletes(message)
      subscriptions.each do |cache_instance|
        cache_instance.delete(message, silent: true, persist: false)
      end
    end

    def subscribed?
      subscribed
    end

    def wait_for_subscription
      start = Time.now
      while Time.now < (start + 10.seconds)
        break if subscribed?
        sleep 0.1
      end
      raise "Could not subscribe to redis in 10 seconds" unless subscribed?
    end

    def redis
      @redis ||= Redis.new
    end

    attr_accessor :thread, :subscriptions, :subscribed

    private_class_method :initialize
    private_class_method :new
  end
end
redis = Redis.new

