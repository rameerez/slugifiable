# frozen_string_literal: true

require "test_helper"

# Focused behavioral tests for the race-condition retry paths.
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

  def test_sequential_creates_with_same_name_get_unique_slugs
    TestModel.generate_slug_based_on :title

    5.times { TestModel.create!(title: "Same Name") }

    slugs = TestModel.pluck(:slug)
    assert_equal 5, slugs.uniq.count
    assert slugs.all? { |slug| slug.start_with?("same-name") }
  end

  def test_sequential_creates_for_not_null_model_get_unique_slugs
    5.times { StrictSlugModel.create!(name: "Same Name") }

    slugs = StrictSlugModel.pluck(:slug)
    assert_equal 5, slugs.uniq.count
    assert slugs.all? { |slug| slug.start_with?("same-name") }
  end

  def test_slug_unique_violation_detection_sqlite
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.slug")

    assert model.send(:slug_unique_violation?, error)
  end

  def test_slug_unique_violation_detection_postgresql
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_organizations_on_slug\"")

    assert model.send(:slug_unique_violation?, error)
  end

  def test_slug_unique_violation_detection_mysql
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("Duplicate entry 'acme-corp' for key 'index_organizations_on_slug'")

    assert model.send(:slug_unique_violation?, error)
  end

  def test_non_slug_violation_does_not_match
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("Duplicate entry 'test@example.com' for key 'index_users_on_email'")

    refute model.send(:slug_unique_violation?, error)
  end

  def test_false_positive_prevention_for_slugged_table_names
    model = TestModel.new
    error = ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: slugged_items.name")

    refute model.send(:slug_unique_violation?, error)
  end

  def test_slug_column_not_null_detection
    refute TestModel.new.send(:slug_column_not_null?)
    assert StrictSlugModel.new.send(:slug_column_not_null?)
  end

  def test_retry_create_skips_nullable_slug_columns
    TestModel.generate_slug_based_on :title
    model = TestModel.new(title: "Skip")

    model.define_singleton_method(:with_slug_retry) do |for_insert: false, &_block|
      flunk("with_slug_retry should not run for nullable slug columns")
    end

    result = model.send(:retry_create_on_slug_unique_violation) { :ok }
    assert_equal :ok, result
  end

  def test_retry_create_uses_insert_mode_for_not_null_slug_columns
    model = StrictSlugModel.new(name: "Acme")
    insert_mode = nil

    model.define_singleton_method(:with_slug_retry) do |for_insert: false, &block|
      insert_mode = for_insert
      block.call(0)
    end

    result = model.send(:retry_create_on_slug_unique_violation) { :ok }
    assert_equal :ok, result
    assert_equal true, insert_mode
  end

  def test_with_slug_retry_runs_inside_savepoint
    model = TestModel.new
    transaction_depths = []

    model.send(:with_slug_retry) do |_attempts|
      transaction_depths << model.class.connection.open_transactions
      :ok
    end

    assert transaction_depths.any? { |depth| depth >= 1 }
  end

  def test_with_slug_retry_retries_slug_violation_for_insert_path
    model = StrictSlugModel.new(name: "Acme")
    block_calls = 0

    model.send(:with_slug_retry, for_insert: true) do |attempts|
      block_calls += 1
      if attempts.zero?
        raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_strict_slug_models_on_slug\"")
      end

      :ok
    end

    assert_equal 2, block_calls
    assert_match(/\Aacme/, model.slug)
  end

  def test_with_slug_retry_bubbles_non_slug_violations
    model = TestModel.new

    assert_raises(ActiveRecord::RecordNotUnique) do
      model.send(:with_slug_retry) do |_attempts|
        raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_users_on_email\"")
      end
    end
  end

  def test_with_slug_retry_raises_after_max_attempts
    model = StrictSlugModel.new(name: "Acme")
    block_calls = 0

    assert_raises(ActiveRecord::RecordNotUnique) do
      model.send(:with_slug_retry, for_insert: true) do |_attempts|
        block_calls += 1
        raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_strict_slug_models_on_slug\"")
      end
    end

    assert_equal Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS, block_calls
  end

  def test_with_slug_retry_does_not_retry_insert_after_record_is_persisted
    model = StrictSlugModel.create!(name: "Persisted")
    block_calls = 0

    assert_raises(ActiveRecord::RecordNotUnique) do
      model.send(:with_slug_retry, for_insert: true) do |_attempts|
        block_calls += 1
        raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_strict_slug_models_on_slug\"")
      end
    end

    assert_equal 1, block_calls
  end

  def test_set_slug_retries_after_slug_record_not_unique
    TestModel.generate_slug_based_on :title
    record = TestModel.create!(title: "Retry Path")
    record.update_column(:slug, nil)

    save_calls = 0
    record.define_singleton_method(:save!) do |*args, **kwargs|
      save_calls += 1
      if save_calls == 1
        raise ActiveRecord::RecordNotUnique.new("UNIQUE constraint failed: test_models.slug")
      end

      super(*args, **kwargs)
    end

    record.send(:set_slug)
    record.reload

    assert_equal 2, save_calls
    assert_match(/\Aretry-path/, record.slug)
  end

  def test_set_slug_bubbles_non_slug_record_not_unique
    TestModel.generate_slug_based_on :title
    record = TestModel.create!(title: "Retry Path")
    record.update_column(:slug, nil)

    save_calls = 0
    record.define_singleton_method(:save!) do |*args, **kwargs|
      save_calls += 1
      raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint \"index_users_on_email\"")
    end

    assert_raises(ActiveRecord::RecordNotUnique) { record.send(:set_slug) }
    assert_equal 1, save_calls
  end

  def test_after_find_repair_sets_slug_for_nil
    TestModel.generate_slug_based_on :title
    record = TestModel.create!(title: "Legacy Record")
    TestModel.where(id: record.id).update_all(slug: nil)

    reloaded = TestModel.find(record.id)

    assert_equal "legacy-record", reloaded.slug
  end

  def test_update_slug_if_nil_uses_non_bang_save
    TestModel.generate_slug_based_on :title
    record = TestModel.create!(title: "Legacy Record")
    record.update_column(:slug, nil)

    record.define_singleton_method(:save) { false }
    record.define_singleton_method(:save!) { raise "save! should not be called from update_slug_if_nil" }

    record.send(:update_slug_if_nil)

    assert record.slug.present?
  end

  def test_generate_slug_based_on_symbol_id_uses_default_string_strategy
    TestModel.generate_slug_based_on :id

    model = TestModel.create!(title: "ID Strategy")

    assert_match(/\A[0-9a-f]{11}\z/, model.slug)
  end

  def test_max_attempts_constant_exists
    assert_equal 10, Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
  end
end
