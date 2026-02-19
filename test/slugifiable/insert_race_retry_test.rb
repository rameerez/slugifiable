# frozen_string_literal: true

require "test_helper"

# Regression coverage for INSERT-time slug collisions.
#
# These tests validate models that persist slugs before INSERT
# (e.g., NOT NULL slug columns with before_validation slug generation).
class Slugifiable::InsertRaceRetryTest < Minitest::Test
  def setup
    StrictSlugModel.delete_all
  end

  def test_insert_retry_hook_exists
    model = StrictSlugModel.new(title: "Hook Check")

    assert model.respond_to?(:retry_create_on_slug_unique_violation, true)
  end

  def test_insert_time_slug_collision_retries_and_succeeds
    race_model = build_race_model do
      class_attribute :insert_attempts, instance_accessor: false, default: 0
      class_attribute :injected_once, instance_accessor: false, default: false

      before_create do
        self.class.insert_attempts += 1
        next if self.class.injected_once

        self.class.injected_once = true
        now = Time.current
        conn = self.class.connection

        conn.execute(
          <<~SQL
            INSERT INTO strict_slug_models (title, slug, created_at, updated_at)
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

    record = race_model.create!(title: "Acme")

    assert record.persisted?
    assert_equal 2, race_model.insert_attempts, "expected one failed INSERT then one successful retry"
    refute_equal "acme", record.slug, "retry should recompute slug after collision"
    assert record.slug.start_with?("acme-")
  end

  def test_insert_time_non_slug_record_not_unique_bubbles
    race_model = build_race_model do
      before_create do
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: strict_slug_models.external_id"
      end
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      race_model.create!(title: "Acme")
    end
  end

  def test_retry_limit_is_enforced
    race_model = build_race_model do
      class_attribute :insert_attempts, instance_accessor: false, default: 0

      before_create do
        self.class.insert_attempts += 1
        raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed: strict_slug_models.slug"
      end
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      race_model.create!(title: "Always Collides")
    end

    assert_equal Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS, race_model.insert_attempts
  end

  def test_not_null_slug_model_still_generates_unique_slugs_for_duplicate_titles
    records = 20.times.map { StrictSlugModel.create!(title: "Popular Name") }
    slugs = records.map(&:slug)

    assert_equal records.size, slugs.uniq.size
    assert_equal "popular-name", records.first.slug
    records.drop(1).each do |record|
      assert record.slug.start_with?("popular-name-")
    end
  end

  private

  def build_race_model(&block)
    klass = Class.new(StrictSlugModel) do
      self.table_name = "strict_slug_models"
    end

    klass.class_eval(&block) if block
    klass
  end
end
