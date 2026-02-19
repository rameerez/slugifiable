# frozen_string_literal: true

require "test_helper"

# Regression tests for slug_unique_violation? detection across different
# database adapters and error message formats.
class Slugifiable::SlugUniqueViolationDetectionTest < Minitest::Test
  def setup
    @model = TestModel.new(title: "Test")
  end

  # ==========================================================================
  # SQLite error format tests
  # ==========================================================================

  def test_detects_sqlite_slug_violation
    error = ActiveRecord::RecordNotUnique.new(
      "UNIQUE constraint failed: test_models.slug"
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect SQLite slug constraint violation"
  end

  def test_does_not_detect_sqlite_other_column_violation
    error = ActiveRecord::RecordNotUnique.new(
      "UNIQUE constraint failed: test_models.email"
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect SQLite violation on non-slug column"
  end

  # ==========================================================================
  # PostgreSQL error format tests
  # ==========================================================================

  def test_detects_postgresql_slug_violation_via_detail
    # PostgreSQL includes DETAIL line with the column name
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: ERROR: duplicate key value violates unique " \
      "constraint \"index_users_on_slug\"\nDETAIL: Key (slug)=(my-slug) already exists."
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect PostgreSQL slug violation via DETAIL line"
  end

  def test_detects_postgresql_slug_violation_via_constraint_name
    # Even without DETAIL, constraint name contains "on_slug"
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: ERROR: duplicate key value violates unique " \
      "constraint \"index_users_on_slug\""
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect PostgreSQL slug violation via index name"
  end

  def test_does_not_detect_postgresql_other_column_violation
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: ERROR: duplicate key value violates unique " \
      "constraint \"index_users_on_email\"\nDETAIL: Key (email)=(test@example.com) already exists."
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect PostgreSQL violation on non-slug column"
  end

  # ==========================================================================
  # MySQL error format tests
  # ==========================================================================

  def test_detects_mysql_slug_violation
    # MySQL format with Rails-default index name
    error = ActiveRecord::RecordNotUnique.new(
      "Duplicate entry 'my-slug' for key 'index_posts_on_slug'"
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect MySQL slug violation via index name"
  end

  def test_detects_mysql_slug_column_directly
    # MySQL might also show column name directly in some cases
    error = ActiveRecord::RecordNotUnique.new(
      "Duplicate entry 'my-slug' for key 'slug'"
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect MySQL slug violation via column name"
  end

  def test_does_not_detect_mysql_other_column_violation
    error = ActiveRecord::RecordNotUnique.new(
      "Duplicate entry 'test@example.com' for key 'index_users_on_email'"
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect MySQL violation on non-slug column"
  end

  # ==========================================================================
  # False positive prevention tests - CRITICAL
  # These test that columns ending in "_slug" don't trigger false matches
  # ==========================================================================

  def test_does_not_detect_canonical_slug_violation
    error = ActiveRecord::RecordNotUnique.new(
      "UNIQUE constraint failed: posts.canonical_slug"
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect violation on 'canonical_slug' column (false positive)"
  end

  def test_does_not_detect_parent_slug_violation
    error = ActiveRecord::RecordNotUnique.new(
      "UNIQUE constraint failed: categories.parent_slug"
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect violation on 'parent_slug' column (false positive)"
  end

  def test_does_not_detect_original_slug_violation
    error = ActiveRecord::RecordNotUnique.new(
      "Duplicate entry 'foo' for key 'index_posts_on_original_slug'"
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect MySQL violation on 'original_slug' index (false positive)"
  end

  def test_does_not_detect_user_slug_violation
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: ERROR: duplicate key value violates unique " \
      "constraint \"index_comments_on_user_slug\"\nDETAIL: Key (user_slug)=(foo) already exists."
    )
    refute @model.send(:slug_unique_violation?, error),
      "Should NOT detect PostgreSQL violation on 'user_slug' column (false positive)"
  end

  # ==========================================================================
  # Edge cases
  # ==========================================================================

  def test_handles_nil_error_message
    error = ActiveRecord::RecordNotUnique.new(nil)
    refute @model.send(:slug_unique_violation?, error),
      "Should handle nil error message gracefully"
  end

  def test_handles_empty_error_message
    error = ActiveRecord::RecordNotUnique.new("")
    refute @model.send(:slug_unique_violation?, error),
      "Should handle empty error message gracefully"
  end

  def test_detects_via_cause_message
    # Some adapters wrap the original error
    cause = StandardError.new("Key (slug)=(my-slug) already exists")
    error = ActiveRecord::RecordNotUnique.new("Wrapped error")
    error.define_singleton_method(:cause) { cause }

    assert @model.send(:slug_unique_violation?, error),
      "Should detect slug violation via error.cause.message"
  end

  def test_case_insensitive_detection
    error = ActiveRecord::RecordNotUnique.new(
      "UNIQUE CONSTRAINT FAILED: TEST_MODELS.SLUG"
    )
    assert @model.send(:slug_unique_violation?, error),
      "Should detect slug violation case-insensitively"
  end
end
