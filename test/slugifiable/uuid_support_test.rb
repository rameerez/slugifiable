require "test_helper"

# UUID Support Test Suite for Slugifiable
#
# The README states that slugifiable supports both `id` and `uuid`.
# This test suite verifies that UUID-based primary keys work correctly.

# Set up a table with UUID primary key for testing
ActiveRecord::Schema.define do
  create_table :test_uuid_models, id: false, force: true do |t|
    t.string :uuid, primary_key: true, null: false
    t.string :title
    t.string :slug
    t.timestamps
  end
end

# Test model with UUID primary key
class TestUuidModel < ActiveRecord::Base
  self.primary_key = :uuid
  include Slugifiable::Model

  before_create :generate_uuid

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end

class Slugifiable::UuidSupportTest < Minitest::Test
  def setup
    TestUuidModel.delete_all

    TestUuidModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # ============================================================================
  # Basic UUID Support
  # ============================================================================

  def test_default_slug_generation_with_uuid_model
    model = TestUuidModel.create!(title: "Test Title")

    refute_nil model.slug, "UUID model should generate a slug"
    assert model.slug.length > 0
  end

  def test_uuid_based_hex_string_slug
    TestUuidModel.class_eval do
      generate_slug_based_on id: :hex_string
    end

    model = TestUuidModel.create!(title: "Test")
    expected = Digest::SHA2.hexdigest(model.uuid.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  def test_uuid_based_number_slug
    TestUuidModel.class_eval do
      generate_slug_based_on id: :number
    end

    model = TestUuidModel.create!(title: "Test")
    expected_num = ((Digest::SHA2.hexdigest(model.uuid.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    assert_equal expected_num, model.slug
  end

  def test_uuid_with_custom_length
    custom_length = 8
    TestUuidModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 8
    end

    model = TestUuidModel.create!(title: "Test")
    expected = Digest::SHA2.hexdigest(model.uuid.to_s)[0, custom_length]
    assert_equal expected, model.slug
    assert_equal custom_length, model.slug.length
  end

  def test_uuid_attribute_based_slug
    TestUuidModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestUuidModel.create!(title: "My UUID Test")
    assert_equal "my-uuid-test", model.slug
  end

  def test_uuid_uniqueness_validation
    model1 = TestUuidModel.create!(title: "First")
    model2 = TestUuidModel.create!(title: "Second")

    refute_equal model1.slug, model2.slug, "UUID models should have unique slugs"
  end

  def test_uuid_slug_persistence
    TestUuidModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestUuidModel.create!(title: "Persistent Test")
    original_slug = model.slug

    # Reload from database
    model_found = TestUuidModel.find(model.uuid)
    assert_equal original_slug, model_found.slug
  end

  def test_uuid_nil_slug_recovery
    model = TestUuidModel.create!(title: "Test")
    model.update_column(:slug, nil)

    model_found = TestUuidModel.find(model.uuid)
    refute_nil model_found.slug, "After find, nil slug should be recovered"
  end

  def test_uuid_collision_resolution
    TestUuidModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestUuidModel.create!(title: "Same Title")
    model2 = TestUuidModel.create!(title: "Same Title")

    refute_equal model1.slug, model2.slug, "UUID models with same title should have different slugs"
  end

  # ============================================================================
  # UUID Format Variations
  # ============================================================================

  def test_uuid_with_dashes
    # Standard UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    model = TestUuidModel.new(title: "Test")
    model.uuid = "550e8400-e29b-41d4-a716-446655440000"
    model.save!

    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_uuid_without_dashes
    model = TestUuidModel.new(title: "Test")
    model.uuid = "550e8400e29b41d4a716446655440000"
    model.save!

    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_uuid_uppercase
    model = TestUuidModel.new(title: "Test")
    model.uuid = "550E8400-E29B-41D4-A716-446655440000"
    model.save!

    refute_nil model.slug
    assert model.slug.length > 0
  end

  # ============================================================================
  # UUID Edge Cases
  # ============================================================================

  def test_uuid_model_compute_slug_directly
    model = TestUuidModel.create!(title: "Direct Compute")
    computed_slug = model.compute_slug

    refute_nil computed_slug
    assert computed_slug.is_a?(String) || computed_slug.is_a?(Integer)
  end

  def test_uuid_model_slug_persisted_check
    model = TestUuidModel.create!(title: "Test")
    assert model.send(:slug_persisted?), "UUID model with slug column should report slug_persisted? as true"
  end
end
