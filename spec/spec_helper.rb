require "bundler/setup"
require "rspec/wait"
require "synced_memory_store"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.wait_timeout = 10 # seconds
end
