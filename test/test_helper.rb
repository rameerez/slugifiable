# frozen_string_literal: true

require "bundler/setup"
Bundler.setup

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# SimpleCov must be loaded BEFORE any application code
# Configuration is auto-loaded from .simplecov file
require "simplecov"

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
require "minitest/mock"

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

  create_table :strict_slug_models do |t|
    t.string :title
    t.string :slug, null: false
    t.timestamps
  end
  add_index :strict_slug_models, :slug, unique: true
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

# Model that requires a slug before INSERT (NOT NULL schema).
# This mirrors the organizations gem integration mode.
class StrictSlugModel < ActiveRecord::Base
  include Slugifiable::Model
  generate_slug_based_on :title

  before_validation :ensure_slug_for_insert, on: :create

  private

  def ensure_slug_for_insert
    self.slug = compute_slug if slug.blank?
  end
end

# Helper module for resetting test model state
module SlugifiableTestHelper
  # List of methods that tests might define on TestModel that need cleanup
  CUSTOM_TEST_METHODS = %i[
    generate_slug_based_on
    custom_title
    custom_slug_method
    private_title
    protected_title
    nil_method
    numeric_title
    slug_source
    virtual_attribute
    title_with_location
  ].freeze

  def self.reset_test_model!
    CUSTOM_TEST_METHODS.each do |method_name|
      TestModel.class_eval do
        remove_method(method_name) if method_defined?(method_name)
        remove_method(method_name) if private_method_defined?(method_name)
        remove_method(method_name) if protected_method_defined?(method_name)
      end
    end

    CUSTOM_TEST_METHODS.each do |method_name|
      TestModelWithoutSlug.class_eval do
        remove_method(method_name) if method_defined?(method_name)
        remove_method(method_name) if private_method_defined?(method_name)
        remove_method(method_name) if protected_method_defined?(method_name)
      end
    end
  end
end
