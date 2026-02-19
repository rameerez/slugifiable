# frozen_string_literal: true

require "test_helper"

# Regression tests for around_create retry behavior.
# These verify that Rails state machine (new_record?, persisted?, dirty tracking)
# works correctly when yield is called multiple times via retry.
class Slugifiable::AroundCreateStateMachineTest < Minitest::Test
  def setup
    StrictSlugModel.delete_all
  end

  # ==========================================================================
  # Rails state machine behavior during retry
  # ==========================================================================

  def test_new_record_status_correct_before_retry
    state_tracker = Class.new(StrictSlugModel) do
      self.table_name = "strict_slug_models"

      class_attribute :states_seen, instance_accessor: false, default: []
      class_attribute :should_fail_once, instance_accessor: false, default: true

      before_create do
        self.class.states_seen << {
          new_record: new_record?,
          persisted: persisted?,
          id_present: id.present?
        }

        # Simulate collision on first attempt
        if self.class.should_fail_once
          self.class.should_fail_once = false
          # Inject a row with our slug
          conn = self.class.connection
          now = Time.current
          conn.execute(
            <<~SQL
              INSERT INTO strict_slug_models (title, slug, created_at, updated_at)
              VALUES (#{conn.quote("Injected")}, #{conn.quote(slug)}, #{conn.quote(now)}, #{conn.quote(now)})
            SQL
          )
        end
      end
    end

    record = state_tracker.create!(title: "State Test")

    assert record.persisted?, "Record should be persisted after create"
    refute record.new_record?, "Record should not be new_record after create"

    # We should have seen states from multiple attempts
    assert state_tracker.states_seen.length >= 1, "Should have tracked at least one state"

    # On first attempt, should be new_record with no ID yet
    first_state = state_tracker.states_seen.first
    assert first_state[:new_record], "Should be new_record on first attempt"
    refute first_state[:persisted], "Should not be persisted on first attempt"
  end

  def test_dirty_tracking_works_across_retry_attempts
    dirty_tracker = Class.new(StrictSlugModel) do
      self.table_name = "strict_slug_models"

      class_attribute :slug_changes_seen, instance_accessor: false, default: []
      class_attribute :should_fail_once, instance_accessor: false, default: true

      before_create do
        self.class.slug_changes_seen << {
          slug_changed: slug_changed?,
          slug_was: slug_was,
          slug_current: slug
        }

        if self.class.should_fail_once
          self.class.should_fail_once = false
          conn = self.class.connection
          now = Time.current
          conn.execute(
            <<~SQL
              INSERT INTO strict_slug_models (title, slug, created_at, updated_at)
              VALUES (#{conn.quote("Injected")}, #{conn.quote(slug)}, #{conn.quote(now)}, #{conn.quote(now)})
            SQL
          )
        end
      end
    end

    record = dirty_tracker.create!(title: "Dirty Test")

    assert record.persisted?
    # Should have multiple change records if retry happened
    assert dirty_tracker.slug_changes_seen.any?, "Should have tracked slug changes"
  end

  def test_record_id_assigned_only_after_successful_insert
    id_tracker = Class.new(StrictSlugModel) do
      self.table_name = "strict_slug_models"

      class_attribute :ids_seen, instance_accessor: false, default: []

      before_create do
        self.class.ids_seen << id
      end

      after_create do
        self.class.ids_seen << id
      end
    end

    record = id_tracker.create!(title: "ID Test")

    assert record.id.present?, "Record should have ID after create"
    # Before create, ID should be nil; after create, it should be set
    assert id_tracker.ids_seen.include?(nil), "ID should be nil before INSERT"
    assert id_tracker.ids_seen.include?(record.id), "ID should be set after INSERT"
  end

  # ==========================================================================
  # Verify retry doesn't corrupt record state
  # ==========================================================================

  def test_final_record_has_correct_attributes_after_retry
    record = StrictSlugModel.create!(title: "Final State Test")

    # Verify the record is in a clean state
    assert record.persisted?
    refute record.new_record?
    assert record.id.present?
    assert record.slug.present?
    assert record.title == "Final State Test"
    refute record.changed?, "Record should not have unsaved changes after create"
  end

  def test_record_can_be_updated_after_retry_create
    record = StrictSlugModel.create!(title: "Update Test")
    original_slug = record.slug

    record.update!(title: "Updated Title")

    assert_equal "Updated Title", record.title
    assert_equal original_slug, record.slug, "Slug should not change on update"
  end

  def test_record_can_be_reloaded_after_retry_create
    record = StrictSlugModel.create!(title: "Reload Test")
    record_id = record.id

    reloaded = StrictSlugModel.find(record_id)

    assert_equal record.title, reloaded.title
    assert_equal record.slug, reloaded.slug
  end

  # ==========================================================================
  # Transaction integrity
  # ==========================================================================

  def test_failed_retry_rolls_back_cleanly
    # Create a model that always fails slug generation
    always_fails = Class.new(StrictSlugModel) do
      self.table_name = "strict_slug_models"

      class_attribute :attempt_count, instance_accessor: false, default: 0

      before_create do
        self.class.attempt_count += 1
        # Raise unique constraint error to simulate collision
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: strict_slug_models.slug"
      end
    end

    initial_count = StrictSlugModel.count

    assert_raises(ActiveRecord::RecordNotUnique) do
      always_fails.create!(title: "Will Fail")
    end

    # Verify retry mechanism was invoked the expected number of times
    assert_equal Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS, always_fails.attempt_count,
      "Should have attempted MAX_SLUG_GENERATION_ATTEMPTS times before giving up"

    # The failed record should not exist
    assert_equal initial_count, StrictSlugModel.count,
      "No records should be created after all retries fail"
    refute StrictSlugModel.exists?(title: "Will Fail"),
      "Failed record should not exist after rollback"
  end
end
