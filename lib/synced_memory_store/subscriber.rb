require 'redis'
module SyncedMemoryStore
  class Subscriber
    def self.instance(wait: false, logger: nil)
      Thread.current[:synced_memory_store] ||= new.tap do |instance|
        instance.configure(logger: logger)
        instance.start(wait: wait)
      end
    end

    def subscribe(cache_instance)
      subscriptions << cache_instance unless subscriptions.include?(cache_instance)
      log("SyncedMemoryStore instance #{cache_instance.uuid} registered for updates")
    end

    def configure(logger: nil)
      self.subscribed = false
      self.logger = logger
      self.subscriptions = []
    end

    def reset!
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
              log("Subscribed to channel #{channel}")
              self.subscribed = true
            end

            on.message do |channel, message|
              send("on_#{channel}".to_sym, message)
              redis.unsubscribe if message == "exit"
            end

            on.unsubscribe do |channel, subscriptions|
              log("Unsubscribed from channel #{channel}")
              self.subscribed = false
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

    def log(msg)
      return if logger.nil?
      if logger.respond_to?(:tagged)
        logger.tagged("synced_memory_store") { logger.info msg }
      else
        logger.info msg
      end
    end

    def on_synced_memory_store_writes(message)
      message_decoded = Marshal.load(message)
      subscribers_informed = 0
      subscriptions.each do |cache_instance|
        next if cache_instance.uuid == message_decoded[:sender_uuid]
        cache_instance.write_from_subscriber(message_decoded[:key], message_decoded[:entry], silent: true, persist: false, **message_decoded[:options])
        subscribers_informed += 1
      end
      log("Write to key #{message_decoded[:key]} shared with #{subscribers_informed} subscribers") unless subscribers_informed == 0
    end

    def on_synced_memory_store_deletes(message)
      message_decoded = Marshal.load(message)
      subscribers_informed = 0
      subscriptions.each do |cache_instance|
        next if cache_instance.uuid == message_decoded[:sender_uuid]
        cache_instance.delete(message_decoded[:key], silent: true, persist: false)
        subscribers_informed += 1
      end
      log("Delete key #{message_decoded[:key]} shared with #{subscribers_informed} subscribers") unless subscribers_informed == 0
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

    attr_accessor :thread, :subscriptions, :subscribed, :logger

    private_class_method :initialize
    private_class_method :new
  end
end
redis = Redis.new

