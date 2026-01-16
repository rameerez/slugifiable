require "test_helper"

# Collision Resolution Test Suite for Slugifiable
#
# This test suite thoroughly tests slug collision resolution:
# - Multiple records with same title
# - Collision suffix generation
# - Timestamp fallback after max attempts
# - Edge cases in collision detection

class Slugifiable::CollisionResolutionTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # ============================================================================
  # Basic Collision Resolution
  # ============================================================================

  def test_two_records_same_title_have_different_slugs
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Duplicate Title")
    model2 = TestModel.create!(title: "Duplicate Title")

    refute_equal model1.slug, model2.slug
  end

  def test_second_record_slug_has_suffix
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Same Name")
    model2 = TestModel.create!(title: "Same Name")

    assert_equal "same-name", model1.slug
    assert model2.slug.start_with?("same-name-"), "Second slug should have suffix"
  end

  def test_many_records_same_title_all_unique
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = 20.times.map do
      TestModel.create!(title: "Common Title")
    end

    slugs = models.map(&:slug)
    assert_equal slugs.length, slugs.uniq.length, "All slugs should be unique"
  end

  def test_collision_with_similar_but_not_identical_titles
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Test")
    model2 = TestModel.create!(title: "test")  # Different case
    model3 = TestModel.create!(title: "TEST")  # All caps

    # All should have same base slug "test"
    assert_equal "test", model1.slug
    # model2 and model3 should have suffixes
    assert model2.slug.start_with?("test-")
    assert model3.slug.start_with?("test-")

    # All unique
    slugs = [model1.slug, model2.slug, model3.slug]
    assert_equal 3, slugs.uniq.length
  end

  # ============================================================================
  # Suffix Generation
  # ============================================================================

  def test_suffix_is_numeric
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    TestModel.create!(title: "Suffix Test")  # First record gets "suffix-test"
    model2 = TestModel.create!(title: "Suffix Test")

    suffix = model2.slug.sub("suffix-test-", "")
    assert suffix.match?(/^\d+$/), "Suffix should be numeric: got #{suffix}"
  end

  def test_suffix_is_random_number
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    TestModel.create!(title: "Random Suffix")  # First record takes "random-suffix"
    model2 = TestModel.create!(title: "Random Suffix")

    # The suffix is now a truly random number (SecureRandom), not id-based
    # Just verify it has the expected format: base-slug-<digits>
    assert_match(/\Arandom-suffix-\d+\z/, model2.slug)
    assert model2.slug.start_with?("random-suffix-")
  end

  # ============================================================================
  # Timestamp Fallback
  # ============================================================================

  def test_timestamp_fallback_after_max_attempts
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Mock exists? to always return true (simulate perpetual collision)
    TestModel.define_singleton_method(:exists?) do |_conditions|
      true
    end

    begin
      # Freeze time for predictable timestamp
      frozen_time = Time.current.to_i
      Time.stub(:current, Time.at(frozen_time)) do
        model = TestModel.create!(title: "Timestamp Test")
        # Timestamp fallback now includes random suffix for extra uniqueness
        assert_match(/\Atimestamp-test-#{frozen_time}-\d+\z/, model.slug)
      end
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
    end
  end

  def test_max_attempts_constant_is_reasonable
    max_attempts = Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
    assert max_attempts >= 5, "MAX_SLUG_GENERATION_ATTEMPTS should be at least 5"
    assert max_attempts <= 100, "MAX_SLUG_GENERATION_ATTEMPTS should not be excessive"
  end

  def test_attempt_count_reaches_max_before_timestamp
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    attempt_tracker = []

    TestModel.define_singleton_method(:exists?) do |conditions|
      attempt_tracker << conditions[:slug]
      true  # Always collide
    end

    begin
      TestModel.create!(title: "Attempt Tracking")

      # First check is for "attempt-tracking"
      # Then MAX_SLUG_GENERATION_ATTEMPTS checks with suffix
      expected_checks = Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS + 1
      assert_equal expected_checks, attempt_tracker.length
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
    end
  end

  # ============================================================================
  # Edge Cases in Collision Detection
  # ============================================================================

  def test_collision_with_existing_suffixed_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Pre-create a record with a suffixed slug
    model1 = TestModel.create!(title: "Edge Case")
    model1.update_column(:slug, "edge-case-123456")

    # Now create another record with same title
    model2 = TestModel.create!(title: "Edge Case")

    # Should get "edge-case" (base slug is available)
    assert_equal "edge-case", model2.slug
  end

  def test_collision_chain
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Create first record
    model1 = TestModel.create!(title: "Chain")
    assert_equal "chain", model1.slug

    # Create many more to potentially create collision chains
    models = 10.times.map do
      TestModel.create!(title: "Chain")
    end

    all_slugs = [model1.slug] + models.map(&:slug)
    assert_equal all_slugs.length, all_slugs.uniq.length, "All slugs in chain should be unique"
  end

  def test_no_collision_resolution_for_unique_titles
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Unique One")
    model2 = TestModel.create!(title: "Unique Two")
    model3 = TestModel.create!(title: "Unique Three")

    assert_equal "unique-one", model1.slug
    assert_equal "unique-two", model2.slug
    assert_equal "unique-three", model3.slug
  end

  def test_collision_with_manually_set_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Manually create a record with specific slug
    model1 = TestModel.create!(title: "Something Else")
    model1.update_column(:slug, "specific-slug")

    # Now create a record that would generate "specific-slug"
    model2 = TestModel.create!(title: "Specific Slug")

    # Should detect collision and add suffix
    assert model2.slug.start_with?("specific-slug")
    refute_equal "specific-slug", model2.slug
  end

  # ============================================================================
  # Collision Resolution Without Persistence
  # ============================================================================

  def test_model_without_slug_column_no_collision_resolution
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModelWithoutSlug.create!(title: "No Persist")
    model2 = TestModelWithoutSlug.create!(title: "No Persist")

    # Without slug column, collision resolution doesn't apply
    # Both should compute the same slug
    assert_equal model1.slug, model2.slug
    assert_equal "no-persist", model1.slug
  end

  # ============================================================================
  # generate_unique_slug Method Direct Tests
  # ============================================================================

  def test_generate_unique_slug_returns_base_when_no_collision
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Direct Test")
    result = model.send(:generate_unique_slug, "brand-new-slug")

    assert_equal "brand-new-slug", result
  end

  def test_generate_unique_slug_adds_suffix_on_collision
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Create existing record with the slug we'll test
    TestModel.create!(title: "First").tap { |m| m.update_column(:slug, "collision-slug") }

    model = TestModel.create!(title: "Test")
    result = model.send(:generate_unique_slug, "collision-slug")

    assert result.start_with?("collision-slug-")
    refute_equal "collision-slug", result
  end

  # ============================================================================
  # Collision with Special Characters in Base Slug
  # ============================================================================

  def test_collision_with_base_slug_ending_in_number
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Product 123")
    model2 = TestModel.create!(title: "Product 123")

    assert_equal "product-123", model1.slug
    assert model2.slug.start_with?("product-123-")
  end

  def test_collision_with_single_character_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "X")
    model2 = TestModel.create!(title: "X")

    assert_equal "x", model1.slug
    assert model2.slug.start_with?("x-")
  end

  def test_collision_with_very_long_base_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    long_title = "a" * 500
    model1 = TestModel.create!(title: long_title)
    model2 = TestModel.create!(title: long_title)

    refute_equal model1.slug, model2.slug
    assert model2.slug.start_with?(model1.slug)
  end

  # ============================================================================
  # Database-Level Uniqueness Constraint Simulation
  # ============================================================================

  def test_handles_database_uniqueness_error_gracefully
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # This tests that even if the database raises a uniqueness error,
    # the application handles it (through validation)
    model1 = TestModel.create!(title: "DB Unique")

    # Manually set slug to cause collision
    assert_raises(ActiveRecord::RecordInvalid) do
      TestModel.create!(title: "Different", slug: model1.slug)
    end
  end
end
