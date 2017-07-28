# SyncedMemoryStore

An active support cache store that can be synced across processes using redis.

The use case for this gem is to work alongside a rails cache for 'high priority' 
entries that should stay in sync across all processes using the shared cache.

So, imagine you had 10 web processes all asking for a logged in user or an access key
from the database.  If you were to cache this in memory normally and changed
a user or access key in one process - the cache would then be stale in the other 9.
So, you could use a memcache based cache or redis based - but then you are hitting
memcache or redis on every request for something that doesnt change often.

SyncedMemoryStore to the rescue

It is an in memory cache in front of a secondary cache for persistence.  But
the in memory cache is synced using redis - so as long as your REDIS_URL environment
variable is set to the same URL - or you can configure your own redis adapter - then
it will just work.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'synced_memory_store'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install synced_memory_store

## Usage

In an irb console in terminal window 1

```ruby
    persistent_cache = ActiveSupport::Cache::RedisStore.new(ENV.fetch('REDIS_URL'))
    cache = SyncedMemoryStore::Store.new(cache: cache_1, redis: redis)
```

In an irb console in terminal window 2

```ruby
    persistent_cache = ActiveSupport::Cache::RedisStore.new(ENV.fetch('REDIS_URL'))
    cache = SyncedMemoryStore::Store.new(cache: cache_1, redis: redis)
```


Then, to write a value to the cache in terminal window 1

```ruby
    cache.write("key", "it works")
```

Then, check it in terminal window 2

```ruby
    cache.fetch("key")
    >> "it works"
```

And it has done this without querying the persistent cache - you can
prove this by replacing the RedisStore with a MemoryStore.

See the specs for more details

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/synced_memory_store.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

