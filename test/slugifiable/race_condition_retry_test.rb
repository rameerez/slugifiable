# frozen_string_literal: true

require "test_helper"

# Regression tests for slug race condition handling
#
# These tests verify that the `set_slug_with_retry` mechanism properly handles
# ActiveRecord::RecordNotUnique exceptions that occur due to concurrent slug
# generation race conditions.
#
# The fix: When `set_slug` encounters a unique constraint violation on the slug
# column, it clears the slug and retries up to MAX_SLUG_GENERATION_ATTEMPTS times.

class Slugifiable::RaceConditionRetryTest < Minitest::Test
  def setup
    TestModel.delete_all
    SlugifiableTestHelper.reset_test_model!
    TestModel.class_eval do
      generate_slug_based_on :title
    end
  end

  # ==========================================================================
  # Core Regression Tests: Prove the fix works
  # ==========================================================================

  def test_set_slug_with_retry_exists
    model = TestModel.new(title: "Test")
    assert model.respond_to?(:set_slug_with_retry, true),
      "Model should have set_slug_with_retry method"
  end

  def test_slug_unique_violation_detection
    model = TestModel.new(title: "Test")

    # Test that slug violations are detected
    slug_error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.slug")
    assert model.send(:slug_unique_violation?, slug_error),
      "Should detect slug unique violation"

    # Test that non-slug violations are not detected
    other_error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.email")
    refute model.send(:slug_unique_violation?, other_error),
      "Should not detect non-slug unique violation"
  end

  def test_retry_mechanism_regenerates_slug_on_collision
    # Create a model to occupy a slug
    existing = TestModel.create!(title: "Collision Test")
    original_slug = existing.slug

    # Create another model and simulate collision retry
    new_model = TestModel.create!(title: "Collision Test")

    # Both should exist with different slugs
    assert_equal 2, TestModel.count
    refute_equal original_slug, new_model.slug,
      "Retry should generate different slug on collision"
    assert new_model.slug.start_with?("collision-test"),
      "Retried slug should still be based on title"
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================

  def test_max_retries_exceeded_raises_error
    race_model = build_update_race_model do
      class_attribute :create_attempts, instance_accessor: false, default: 0
      class_attribute :update_attempts, instance_accessor: false, default: 0

      before_create do
        self.class.create_attempts += 1
      end

      before_update do
        self.class.update_attempts += 1
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: test_models.slug"
      end
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      race_model.create!(title: "Always Collides")
    end

    assert_equal 1, race_model.create_attempts,
      "around_create should not retry INSERT when failure comes from after_create slug save"
    assert_equal Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS, race_model.update_attempts
  end

  def test_non_slug_unique_violations_bubble_up
    race_model = build_update_race_model do
      before_update do
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: test_models.email"
      end
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      race_model.create!(title: "Bubble Up Test")
    end
  end

  def test_retry_clears_slug_before_regeneration
    race_model = build_update_race_model do
      class_attribute :slug_values_before_compute, instance_accessor: false, default: []
      class_attribute :injected_once, instance_accessor: false, default: false

      define_method(:compute_slug) do
        self.class.slug_values_before_compute += [slug]
        super()
      end

      before_update do
        next if self.class.injected_once || slug.blank?

        self.class.injected_once = true
        now = Time.current
        conn = self.class.connection

        conn.execute(
          <<~SQL
            INSERT INTO test_models (title, slug, created_at, updated_at)
            VALUES (
              #{conn.quote("Injected")},
              #{conn.quote(slug)},
              #{conn.quote(now)},
              #{conn.quote(now)}
            )
          SQL
        )
      end
    end

    race_model.create!(title: "Clear Slug Test")

    assert_equal [nil, nil], race_model.slug_values_before_compute
  end

  # ==========================================================================
  # Integration Tests: Real-world scenarios
  # ==========================================================================

  def test_sequential_creates_with_same_title_all_get_unique_slugs
    titles = ["Same Title"] * 20

    models = titles.map { |title| TestModel.create!(title: title) }
    slugs = models.map(&:slug)

    assert_equal 20, slugs.uniq.length,
      "All 20 models with same title should have unique slugs"

    # First should be clean, rest should have suffixes
    assert_equal "same-title", models.first.slug
    models[1..].each do |model|
      assert model.slug.start_with?("same-title-"),
        "Subsequent models should have suffixed slugs"
    end
  end

  def test_update_slug_if_nil_regenerates_slug
    model = TestModel.create!(title: "Nil Slug Test")
    model.update_column(:slug, nil)

    # Force a reload to trigger after_find -> update_slug_if_nil
    reloaded = TestModel.find(model.id)

    refute_nil reloaded.slug, "Slug should be regenerated"
    assert reloaded.slug.include?("nil-slug-test") || reloaded.slug.to_i > 0,
      "Regenerated slug should be based on title or ID"
  end

  def test_set_slug_called_via_after_create_hook
    # Verify the callback chain works
    model = TestModel.create!(title: "After Create Hook")

    refute_nil model.slug, "Slug should be set via after_create"
    assert_equal "after-create-hook", model.slug
  end

  # NOTE: The after_create UPDATE path retry mechanism is tested indirectly by
  # test_retry_clears_slug_before_regeneration. For direct collision testing
  # with savepoints, see test/slugifiable/insert_race_retry_test.rb which tests
  # the INSERT-time retry path for NOT NULL slug columns.

  private

  def build_update_race_model(&block)
    klass = Class.new(TestModel) do
      self.table_name = "test_models"
    end

    klass.class_eval(&block) if block
    klass
  end
end
