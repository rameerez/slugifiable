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
    # MAX retries + 1 fallback attempt with timestamp suffix
    assert_equal Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS + 1, race_model.update_attempts
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

  def test_compute_base_slug_returns_raw_parameterized_value
    model = TestModel.new(title: "Base Slug Test")

    # compute_base_slug should return the raw parameterized value without uniqueness suffixes
    base_slug = model.send(:compute_base_slug)

    assert_equal "base-slug-test", base_slug, "Should return raw parameterized title"
  end

  def test_compute_base_slug_handles_nil_attribute
    model = TestModel.new(title: nil)

    # Should fallback to ID-based slug (Integer) when attribute is nil
    # This matches compute_slug_based_on_attribute's fallback behavior
    base_slug = model.send(:compute_base_slug)

    assert_kind_of Integer, base_slug
  end

  def test_compute_base_slug_handles_blank_attribute
    model = TestModel.new(title: "   ")

    # Should fallback to ID-based slug (Integer) when parameterized value is blank
    # This matches compute_slug_based_on_attribute's fallback behavior
    base_slug = model.send(:compute_base_slug)

    assert_kind_of Integer, base_slug
  end

  def test_compute_base_slug_with_id_based_strategy
    # Create a model that uses default ID-based strategy
    id_based_model = Class.new(TestModel) do
      self.table_name = "test_models"

      # Override to use default ID-based strategy
      def determine_slug_generation_method
        [:compute_slug_as_string, {}]
      end
    end

    model = id_based_model.new(title: "Ignored Title")
    model.id = 123

    # For ID-based strategy, compute_base_slug delegates to compute_slug
    base_slug = model.send(:compute_base_slug)

    assert_kind_of String, base_slug
  end

  def test_compute_base_slug_when_attribute_missing
    # Create a model configured to use a non-existent attribute
    model = TestModel.new(title: "Has Title")

    # Temporarily modify the model to reference a non-existent attribute
    def model.determine_slug_generation_method
      [:compute_slug_based_on_attribute, :nonexistent_attribute]
    end

    # Should fallback to ID-based slug (Integer)
    # This matches compute_slug_based_on_attribute's fallback behavior
    base_slug = model.send(:compute_base_slug)

    assert_kind_of Integer, base_slug
  end

  # ==========================================================================
  # Regression tests for reviewer-identified issues
  # ==========================================================================

  def test_compute_base_slug_nil_fallback_matches_compute_slug_nil_fallback
    # Reviewer concern: compute_base_slug and compute_slug_based_on_attribute should
    # have consistent fallback behavior for nil attributes.
    #
    # FIXED: Both now use generate_random_number_based_on_id_hex (returns Integer)
    model = TestModel.new(title: nil)
    model.id = 123

    base_slug = model.send(:compute_base_slug)
    full_slug = model.compute_slug

    # Both should return Integer (generate_random_number_based_on_id_hex)
    assert_kind_of Integer, base_slug, "compute_base_slug should return Integer for nil"
    assert_kind_of Integer, full_slug, "compute_slug should return Integer for nil"

    # Both should return the same value for same ID
    assert_equal base_slug, full_slug, "Both methods should return same fallback value"
  end

  def test_compute_base_slug_blank_fallback_matches_compute_slug_blank_fallback
    # Test blank (whitespace-only) title behavior
    model = TestModel.new(title: "   ")
    model.id = 456

    base_slug = model.send(:compute_base_slug)
    full_slug = model.compute_slug

    # Both should return Integer (generate_random_number_based_on_id_hex)
    assert_kind_of Integer, base_slug, "compute_base_slug should return Integer for blank"
    assert_kind_of Integer, full_slug, "compute_slug should return Integer for blank"

    # Both should return the same value for same ID
    assert_equal base_slug, full_slug, "Both methods should return same fallback value"
  end

  def test_exhaustion_fallback_raises_on_continued_unique_violation
    # Test that RecordNotUnique exceptions in exhaustion fallback propagate
    always_fails_model = build_update_race_model do
      class_attribute :exhaustion_reached, instance_accessor: false, default: false

      before_update do
        # Mark when we've gone past normal retries
        if slug&.include?("-#{Time.current.to_i}-")
          self.class.exhaustion_reached = true
        end
        # Always fail
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: test_models.slug"
      end
    end

    # This should raise because even exhaustion fallback fails
    assert_raises(ActiveRecord::RecordNotUnique) do
      always_fails_model.create!(title: "Exhaustion Test")
    end

    # Verify exhaustion was actually attempted
    assert always_fails_model.exhaustion_reached,
      "Should have attempted exhaustion fallback with timestamp slug"
  end

  def test_exhaustion_fallback_uses_save_bang
    # Reviewer concern: on_exhaustion uses self.save (not save!) which might
    # silently swallow failures.
    #
    # This test verifies that save! is used (raises on failure rather than
    # returning false). We test this by checking the model source directly.
    model = TestModel.new(title: "Save Bang Test")

    # Read the source of set_slug_with_retry and verify it uses save!
    source_location = model.method(:set_slug_with_retry).source_location
    refute_nil source_location, "Should be able to locate source"

    file_path, _line = source_location
    source = File.read(file_path)

    # The on_exhaustion callback should use save! not save
    assert_match(/on_exhaustion.*\{.*self\.save!.*\}/m, source,
      "on_exhaustion should use self.save! to ensure failures propagate")
  end

  private

  def build_update_race_model(&block)
    klass = Class.new(TestModel) do
      self.table_name = "test_models"
    end

    klass.class_eval(&block) if block
    klass
  end
end
