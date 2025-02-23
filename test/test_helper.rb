# frozen_string_literal: true

require "bundler/setup"
Bundler.setup

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Rails/ActiveSupport dependencies first
require "active_support"
require "active_support/concern"
require "active_support/core_ext/time"
require "active_record"
require "sqlite3"

# Then our gem
require "slugifiable"

# Finally test framework
require "minitest/autorun"

# Silence the SQL output
ActiveRecord::Base.logger = Logger.new(nil)

# Set up an in-memory database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Create a schema for testing
ActiveRecord::Schema.define do
  create_table :test_models do |t|
    t.string :title
    t.string :slug
    t.timestamps
  end

  create_table :test_models_without_slug do |t|
    t.string :title
    t.timestamps
  end
end

# Test model with slug column
class TestModel < ActiveRecord::Base
  include Slugifiable::Model
end

# Test model without slug column
class TestModelWithoutSlug < ActiveRecord::Base
  include Slugifiable::Model
  self.table_name = "test_models_without_slug"

  # Skip validation since this table doesn't have a slug column
  # Clear all validations and callbacks related to slug
  clear_validators!
  reset_callbacks :validate

  # Re-add any other validations your model might need here
  # (none in our test case)
end
