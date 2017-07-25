require "spec_helper"

RSpec.describe SyncedMemoryStore do
  it "has a version number" do
    expect(SyncedMemoryStore::VERSION).not_to be nil
  end
end
