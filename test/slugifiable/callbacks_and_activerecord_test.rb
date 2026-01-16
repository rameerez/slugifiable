require "test_helper"

# Callbacks and ActiveRecord Integration Test Suite for Slugifiable
#
# This test suite covers:
# - after_create callback behavior
# - after_find callback behavior
# - Validation behavior
# - Save and update lifecycle
# - Database persistence
# - Transaction behavior

class Slugifiable::CallbacksAndActiveRecordTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # ============================================================================
  # after_create Callback Tests
  # ============================================================================

  def test_slug_is_set_after_create
    model = TestModel.create!(title: "Test Title")
    refute_nil model.slug, "Slug should be set after create"
  end

  def test_slug_is_saved_to_database_after_create
    model = TestModel.create!(title: "Test Title")
    model_from_db = TestModel.find(model.id)
    assert_equal model.slug, model_from_db.slug, "Slug should be persisted to database"
  end

  def test_after_create_only_fires_once
    # Track how many times set_slug is called
    call_count = 0
    original_set_slug = TestModel.instance_method(:set_slug)

    TestModel.class_eval do
      define_method(:set_slug) do
        call_count += 1
        original_set_slug.bind(self).call
      end
    end

    begin
      TestModel.create!(title: "Test")
      assert_equal 1, call_count, "set_slug should only be called once during create"
    ensure
      TestModel.class_eval do
        define_method(:set_slug, original_set_slug)
      end
    end
  end

  def test_slug_not_regenerated_on_update
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Original Title")
    original_slug = model.slug

    model.update!(title: "Updated Title")
    model.reload

    assert_equal original_slug, model.slug, "Slug should not change on update"
  end

  # ============================================================================
  # after_find Callback Tests
  # ============================================================================

  def test_after_find_recovers_nil_slug
    model = TestModel.create!(title: "Test")
    model.update_column(:slug, nil)

    model_found = TestModel.find(model.id)
    refute_nil model_found.slug, "after_find should recover nil slug"
  end

  def test_after_find_does_not_change_existing_slug
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    model_found = TestModel.find(model.id)
    assert_equal original_slug, model_found.slug, "after_find should not change existing slug"
  end

  def test_after_find_with_where_query
    model = TestModel.create!(title: "Unique Title For Query")
    model.update_column(:slug, nil)

    model_found = TestModel.where(title: "Unique Title For Query").first
    refute_nil model_found.slug, "after_find should work with where queries"
  end

  def test_after_find_with_find_by
    model = TestModel.create!(title: "Test Find By")
    model.update_column(:slug, nil)

    model_found = TestModel.find_by(id: model.id)
    refute_nil model_found.slug, "after_find should work with find_by"
  end

  # ============================================================================
  # Validation Tests
  # ============================================================================

  def test_slug_uniqueness_validation
    TestModel.create!(title: "First", slug: "unique-slug")

    assert_raises(ActiveRecord::RecordInvalid) do
      TestModel.create!(title: "Second", slug: "unique-slug")
    end
  end

  def test_slug_uniqueness_case_sensitivity
    # Default ActiveRecord uniqueness is case-sensitive
    model1 = TestModel.create!(title: "First", slug: "my-slug")

    # This might pass depending on database collation
    # SQLite is case-sensitive by default
    begin
      model2 = TestModel.create!(title: "Second", slug: "MY-SLUG")
      refute_equal model1.slug, model2.slug
    rescue ActiveRecord::RecordInvalid
      # Case-insensitive collation in database
      pass
    end
  end

  def test_auto_generated_slug_is_unique
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Same Title")
    model2 = TestModel.create!(title: "Same Title")

    refute_equal model1.slug, model2.slug, "Auto-generated slugs should be unique"
  end

  def test_validation_passes_with_nil_slug_before_create
    # The slug is nil before after_create runs
    # Validation should not fail because of nil slug
    model = TestModel.new(title: "Test")
    assert model.valid?, "Model should be valid before create even with nil slug"
  end

  # ============================================================================
  # Save and Update Lifecycle Tests
  # ============================================================================

  def test_create_then_save_does_not_duplicate_slug
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    model.title = "Updated Title"
    model.save!

    assert_equal original_slug, model.slug
  end

  def test_update_attribute_without_affecting_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Original")
    original_slug = model.slug

    model.update_attribute(:title, "Changed")
    assert_equal original_slug, model.slug
  end

  def test_reload_preserves_slug
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    model.reload
    assert_equal original_slug, model.slug
  end

  def test_touch_does_not_change_slug
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    model.touch
    assert_equal original_slug, model.slug
  end

  # ============================================================================
  # Persistence and Database Tests
  # ============================================================================

  def test_slug_survives_database_round_trip
    model = TestModel.create!(title: "Database Test")
    original_slug = model.slug

    # Force reload from database
    model_from_db = TestModel.find(model.id)
    assert_equal original_slug, model_from_db.slug
  end

  def test_slug_stored_as_correct_type
    model = TestModel.create!(title: "Type Test")
    model_from_db = TestModel.find(model.id)

    assert model_from_db.slug.is_a?(String), "Slug should be a String"
  end

  def test_slug_column_can_be_queried
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Queryable Test")
    found_model = TestModel.find_by(slug: model.slug)

    assert_equal model.id, found_model.id
  end

  def test_multiple_records_with_unique_slugs
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = 10.times.map do |i|
      TestModel.create!(title: "Title #{i}")
    end

    slugs = models.map(&:slug)
    assert_equal slugs.uniq.length, slugs.length, "All slugs should be unique"
  end

  # ============================================================================
  # Model Without Slug Column Tests
  # ============================================================================

  def test_model_without_slug_column_computes_slug
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    model = TestModelWithoutSlug.create!(title: "No Column Test")
    assert_equal "no-column-test", model.slug
  end

  def test_model_without_slug_column_slug_not_persisted
    model = TestModelWithoutSlug.create!(title: "Test")

    # Verify slug is computed on demand, not persisted
    refute model.attributes.key?("slug"), "Model without slug column should not have slug attribute"

    # But calling .slug should work
    refute_nil model.slug
  end

  def test_model_without_slug_column_no_uniqueness_constraint
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModelWithoutSlug.create!(title: "Same")
    model2 = TestModelWithoutSlug.create!(title: "Same")

    # Both can have the same computed slug since it's not persisted
    assert_equal model1.slug, model2.slug
  end

  def test_model_without_slug_column_slug_persisted_returns_false
    model = TestModelWithoutSlug.create!(title: "Test")
    refute model.send(:slug_persisted?), "slug_persisted? should return false"
  end

  # ============================================================================
  # Transaction Behavior Tests
  # ============================================================================

  def test_slug_rollback_on_transaction_failure
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    begin
      ActiveRecord::Base.transaction do
        TestModel.create!(title: "Transaction Test")
        raise ActiveRecord::Rollback
      end
    rescue
      # Expected
    end

    assert_equal 0, TestModel.count, "Record should be rolled back"
  end

  def test_slug_survives_nested_transaction
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    outer_model = nil
    inner_model = nil

    ActiveRecord::Base.transaction do
      outer_model = TestModel.create!(title: "Outer")

      ActiveRecord::Base.transaction(requires_new: true) do
        inner_model = TestModel.create!(title: "Inner")
      end
    end

    assert_equal 2, TestModel.count
    refute_nil outer_model.slug
    refute_nil inner_model.slug
  end

  # ============================================================================
  # set_slug Method Tests
  # ============================================================================

  def test_set_slug_only_sets_when_blank
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    # Manually call set_slug - should not change existing slug
    model.send(:set_slug)
    model.reload

    assert_equal original_slug, model.slug
  end

  def test_set_slug_sets_when_nil
    model = TestModel.create!(title: "Test")
    model.update_column(:slug, nil)

    model.send(:set_slug)
    model.reload

    refute_nil model.slug
  end

  def test_set_slug_respects_slug_persisted_check
    # For model without slug column, set_slug should be a no-op
    model = TestModelWithoutSlug.create!(title: "Test")

    # Should not raise
    model.send(:set_slug)
  end

  # ============================================================================
  # update_slug_if_nil Method Tests
  # ============================================================================

  def test_update_slug_if_nil_works
    model = TestModel.create!(title: "Test")
    model.update_column(:slug, nil)

    model.send(:update_slug_if_nil)
    model.reload

    refute_nil model.slug
  end

  def test_update_slug_if_nil_no_op_when_slug_exists
    model = TestModel.create!(title: "Test")
    original_slug = model.slug

    model.send(:update_slug_if_nil)
    model.reload

    assert_equal original_slug, model.slug
  end

  def test_update_slug_if_nil_no_op_for_model_without_slug_column
    model = TestModelWithoutSlug.create!(title: "Test")

    # Should not raise
    model.send(:update_slug_if_nil)
  end
end
