# frozen_string_literal: true

require "test_helper"

# Tests for race condition handling in slug generation.
# Covers both retry paths: around_create (NOT NULL) and after_create (nullable).
#
# Note: The actual race condition occurs when two processes simultaneously:
# 1. Pass the uniqueness validation (no collision detected)
# 2. Try to INSERT, and the second fails with RecordNotUnique
#
# In single-threaded tests, we simulate this by:
# - Testing sequential creates (exercises EXISTS? collision handling)
# - Testing the violation detection logic
# - Testing that non-slug violations bubble up correctly
class RaceConditionTest < Minitest::Test
  def setup
    TestModel.delete_all
    StrictSlugModel.delete_all
    SlugifiableTestHelper.reset_test_model!
  end

  def teardown
    TestModel.delete_all
    StrictSlugModel.delete_all
    SlugifiableTestHelper.reset_test_model!
  end

  # === Sequential Creation Tests ===
  # These test the EXISTS? check collision handling in generate_unique_slug

  def test_sequential_creates_with_same_name_get_unique_slugs
    TestModel.generate_slug_based_on :title

    5.times { TestModel.create!(title: "Same Name") }

    slugs = TestModel.pluck(:slug)
    assert_equal 5, slugs.uniq.count, "Expected 5 unique slugs"
    assert slugs.all? { |s| s.start_with?("same-name") }, "All slugs should be based on 'same-name'"
  end

  def test_strict_model_sequential_creates_get_unique_slugs
    5.times { StrictSlugModel.create!(name: "Same Name") }

    slugs = StrictSlugModel.pluck(:slug)
    assert_equal 5, slugs.uniq.count, "Expected 5 unique slugs"
    assert slugs.all? { |s| s.start_with?("same-name") }, "All slugs should be based on 'same-name'"
  end

  def test_many_sequential_creates_all_get_unique_slugs
    TestModel.generate_slug_based_on :title

    20.times { TestModel.create!(title: "Popular Name") }

    slugs = TestModel.pluck(:slug)
    assert_equal 20, slugs.uniq.count, "Expected 20 unique slugs"
  end

  # === Slug Violation Detection (Core of retry logic) ===

  def test_slug_unique_violation_detection_sqlite
    model = TestModel.new
    # SQLite format
    error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.slug")
    assert model.send(:slug_unique_violation?, error)
  end

  def test_slug_unique_violation_detection_postgresql
    model = TestModel.new
    # PostgreSQL format with index name
    error = ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_organizations_on_slug\"")
    assert model.send(:slug_unique_violation?, error)
  end

  def test_slug_unique_violation_detection_postgresql_key_detail
    model = TestModel.new
    # PostgreSQL format with key detail
    error = ActiveRecord::RecordNotUnique.new("Key (slug)=(acme-corp) already exists")
    assert model.send(:slug_unique_violation?, error)
  end

  def test_slug_unique_violation_detection_mysql
    model = TestModel.new
    # MySQL format with index name
    error = ActiveRecord::RecordNotUnique.new("Duplicate entry 'acme-corp' for key 'index_organizations_on_slug'")
    assert model.send(:slug_unique_violation?, error)
  end

  def test_non_slug_violation_not_detected_email
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("Duplicate entry 'test@example.com' for key 'index_users_on_email'")
    refute model.send(:slug_unique_violation?, error)
  end

  def test_non_slug_violation_not_detected_username
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: users.username")
    refute model.send(:slug_unique_violation?, error)
  end

  def test_false_positive_prevention_slugged_items
    model = TestModel.new
    # Should NOT match "slugged_items" - the word boundary regex prevents this
    error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: slugged_items.name")
    refute model.send(:slug_unique_violation?, error)
  end

  def test_false_negative_for_custom_column_parent_slug
    model = TestModel.new
    # Custom column names like "parent_slug" are NOT matched by the regex.
    # This is a safe false-negative: the error bubbles up instead of silently retrying.
    # Pattern: \bslug\b doesn't match "parent_slug" (no word boundary before "slug")
    # Pattern: _on_slug\b doesn't match "on_parent_slug"
    error = ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_items_on_parent_slug\"")
    refute model.send(:slug_unique_violation?, error)
  end

  # === Optimization Guard ===

  def test_slug_column_not_null_detection
    # TestModel has nullable slug column
    model = TestModel.new
    refute model.send(:slug_column_not_null?)

    # StrictSlugModel has NOT NULL slug column
    strict = StrictSlugModel.new
    assert strict.send(:slug_column_not_null?)
  end

  def test_around_create_skipped_for_nullable_columns
    TestModel.generate_slug_based_on :title

    model = TestModel.new(title: "Test")
    called = false

    # The retry should be skipped for nullable columns
    model.define_singleton_method(:with_slug_retry) do |&block|
      called = true
      block.call
    end

    model.save!
    refute called, "with_slug_retry should not be called for nullable slug column"
  end

  # === after_find Repair Path ===

  def test_after_find_repair_sets_slug_for_nil
    TestModel.generate_slug_based_on :title

    # Create record with nil slug (simulating legacy data)
    record = TestModel.create!(title: "Legacy Record")

    # Manually nil the slug in DB to simulate legacy data
    TestModel.where(id: record.id).update_all(slug: nil)

    # Reload should trigger update_slug_if_nil via after_find
    reloaded = TestModel.find(record.id)

    # The slug should be set now
    assert_equal "legacy-record", reloaded.slug
  end

  def test_after_find_uses_non_bang_save
    # Verify that update_slug_if_nil calls save (not save!)
    # by checking the method implementation
    model = TestModel.new
    source = model.method(:update_slug_if_nil).source_location

    # Read the file and verify it uses `save` not `save!`
    file_content = File.read(source[0])
    method_lines = file_content.lines[source[1] - 1..source[1] + 10]
    method_content = method_lines.join

    assert_includes method_content, "save # Non-bang"
    refute_includes method_content, "save!"
  end

  # === Retry Helper Structure ===

  def test_with_slug_retry_uses_savepoint
    model = TestModel.new

    # Verify the method calls transaction with requires_new: true
    source = model.method(:with_slug_retry).source_location
    file_content = File.read(source[0])
    method_lines = file_content.lines[source[1] - 1..source[1] + 20]
    method_content = method_lines.join

    assert_includes method_content, "requires_new: true"
  end

  def test_set_slug_uses_savepoint
    TestModel.generate_slug_based_on :title
    model = TestModel.new(title: "Test")

    source = model.method(:set_slug).source_location
    file_content = File.read(source[0])
    method_lines = file_content.lines[source[1] - 1..source[1] + 20]
    method_content = method_lines.join

    assert_includes method_content, "requires_new: true"
  end

  # === compute_slug_for_retry Override Point ===

  def test_compute_slug_for_retry_can_be_overridden
    TestModel.generate_slug_based_on :title
    model = TestModel.new(title: "Test")

    custom_slug_called = false
    model.define_singleton_method(:compute_slug_for_retry) do
      custom_slug_called = true
      "custom-retry-slug"
    end

    # Trigger a path that calls compute_slug_for_retry
    # (In normal flow, this is called during retry)
    result = model.compute_slug_for_retry
    assert custom_slug_called
    assert_equal "custom-retry-slug", result
  end

  # === MAX_SLUG_GENERATION_ATTEMPTS Constant ===

  def test_max_attempts_constant_exists
    assert_equal 10, Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
  end

  # === Integration: Normal Create Flow ===

  def test_normal_create_flow_nullable_slug
    TestModel.generate_slug_based_on :title

    model = TestModel.create!(title: "Normal Create")
    assert model.persisted?
    assert_equal "normal-create", model.slug
  end

  def test_normal_create_flow_not_null_slug
    model = StrictSlugModel.create!(name: "Normal Create")
    assert model.persisted?
    assert_equal "normal-create", model.slug
  end

  def test_create_with_blank_title_falls_back_to_id_based
    TestModel.generate_slug_based_on :title

    model = TestModel.create!(title: "")
    assert model.persisted?
    # Falls back to random number based on ID
    assert_kind_of Integer, model.slug.to_i
    refute_equal 0, model.slug.to_i
  end
end
