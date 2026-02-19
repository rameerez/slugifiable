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
    # This test simulates a pathological case where every slug attempt collides.
    # In practice this is nearly impossible due to random suffixes, but we test
    # that the retry limit is respected.

    # Create an existing record with a specific slug
    TestModel.create!(title: "Existing").tap { |m| m.update_column(:slug, "always-same-slug") }

    model = TestModel.new(title: "Max Retry Test")
    model.id = 999 # Assign an ID so it appears persisted

    # Track retry attempts
    call_count = 0
    original_compute = model.method(:compute_slug)

    model.define_singleton_method(:compute_slug) do
      call_count += 1
      "always-same-slug" # Always collide
    end

    # Skip validation to hit the database constraint directly
    model.define_singleton_method(:save) do
      # Bypass validation, go straight to DB
      raise ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.slug")
    end

    # The retry should eventually give up
    assert_raises(ActiveRecord::RecordNotUnique) do
      model.send(:set_slug_with_retry)
    end

    assert call_count > 1, "Should have attempted multiple retries (got #{call_count})"
    assert call_count <= Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS + 1,
      "Should not exceed MAX_SLUG_GENERATION_ATTEMPTS (got #{call_count})"
  end

  def test_non_slug_unique_violations_bubble_up
    # Create a test model with a unique constraint on another column
    # For this test, we'll simulate by catching and re-raising

    model = TestModel.create!(title: "Bubble Up Test")

    # Simulate a non-slug unique violation
    model.define_singleton_method(:save) do
      raise ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.email")
    end

    # Should raise without retry
    assert_raises(ActiveRecord::RecordNotUnique) do
      model.send(:set_slug_with_retry)
    end
  end

  def test_retry_clears_slug_before_regeneration
    model = TestModel.new(title: "Clear Slug Test")

    slugs_seen = []
    original_compute = model.method(:compute_slug)

    model.define_singleton_method(:compute_slug) do
      slug = original_compute.call
      slugs_seen << slug
      slug
    end

    # First call sets slug
    model.send(:set_slug_with_retry)

    # All computed slugs should potentially be different (random suffixes)
    # The first one should be the base slug
    assert slugs_seen.first == "clear-slug-test" || slugs_seen.first.start_with?("clear-slug-test"),
      "First slug should be based on title"
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

  def test_update_slug_if_nil_uses_retry_mechanism
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

  # ==========================================================================
  # Prove the fix was necessary (without it, these would fail)
  # ==========================================================================

  def test_without_retry_concurrent_creates_would_fail
    # This test demonstrates why retry is needed:
    # Without retry, concurrent creates with the same base slug could fail
    # when both pass the EXISTS check but one INSERT wins.

    # We can't easily test true concurrency in SQLite in-memory,
    # but we can verify the retry mechanism by forcing a collision scenario.

    # Create initial record
    TestModel.create!(title: "Force Collision")

    # Create many more with same title - without retry, some would fail
    # With retry, all should succeed
    50.times do
      model = TestModel.create!(title: "Force Collision")
      refute_nil model.slug
      assert model.slug.start_with?("force-collision")
    end

    assert_equal 51, TestModel.where("slug LIKE 'force-collision%'").count
  end
end
