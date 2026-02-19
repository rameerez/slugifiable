# frozen_string_literal: true

require "test_helper"

# PostgreSQL-specific integration coverage for INSERT-time slug collisions.
#
# This test is optional and only runs when:
# - the `pg` gem is available, and
# - `SLUGIFIABLE_TEST_POSTGRES_URL` is set.
#
# It verifies that `retry_create_on_slug_unique_violation` wraps create attempts
# in `requires_new` transactions, so the outer transaction remains healthy after
# a unique-constraint collision.
class Slugifiable::PostgresqlInsertRaceRetryTest < Minitest::Test
  POSTGRES_URL_ENV = "SLUGIFIABLE_TEST_POSTGRES_URL"

  def setup
    ensure_pg_driver!
    ensure_postgres_url!
    establish_postgres_connection!
    ensure_postgres_schema!
    postgres_strict_slug_model.delete_all
  end

  def teardown
    return unless defined?(@postgres_base)

    @postgres_base.connection_pool.disconnect!
  rescue StandardError
    nil
  end

  def test_insert_retry_keeps_outer_transaction_usable_after_collision
    race_model = build_postgres_race_model do
      class_attribute :insert_attempts, instance_accessor: false, default: 0
      class_attribute :injected_once, instance_accessor: false, default: false

      before_create do
        self.class.insert_attempts += 1
        next if self.class.injected_once

        self.class.injected_once = true
        conn = self.class.connection
        now = Time.current

        conn.execute(
          <<~SQL
            INSERT INTO pg_strict_slug_models (title, slug, created_at, updated_at)
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

    first_record = nil
    second_record = nil

    race_model.transaction do
      first_record = race_model.create!(title: "Acme")
      second_record = race_model.create!(title: "Outer Tx Healthy")
    end

    assert first_record.persisted?
    assert second_record.persisted?
    assert_equal 2, race_model.insert_attempts, "expected one failed INSERT then one successful retry"
    assert_equal 2, race_model.where(title: ["Acme", "Outer Tx Healthy"]).count,
      "outer transaction should stay usable after collision retry"
  end

  private

  def ensure_pg_driver!
    require "pg"
  rescue LoadError
    skip "PostgreSQL integration test skipped: install the `pg` gem."
  end

  def ensure_postgres_url!
    return unless postgres_url.empty?

    skip "PostgreSQL integration test skipped: set #{POSTGRES_URL_ENV}."
  end

  def establish_postgres_connection!
    postgres_base.establish_connection(postgres_url)
    postgres_base.connection
  rescue StandardError => e
    skip "PostgreSQL integration test skipped: #{e.class}: #{e.message}"
  end

  def ensure_postgres_schema!
    conn = postgres_base.connection

    conn.create_table :pg_strict_slug_models, force: true do |t|
      t.string :title
      t.string :slug, null: false
      t.timestamps
    end
    conn.add_index :pg_strict_slug_models, :slug, unique: true
  end

  def postgres_url
    ENV.fetch(POSTGRES_URL_ENV, "").strip
  end

  def postgres_base
    @postgres_base ||= Class.new(ActiveRecord::Base) do
      self.abstract_class = true
    end
  end

  def postgres_strict_slug_model
    @postgres_strict_slug_model ||= Class.new(postgres_base) do
      include Slugifiable::Model

      self.table_name = "pg_strict_slug_models"

      generate_slug_based_on :title
      before_validation :ensure_slug_for_insert, on: :create

      private

      def ensure_slug_for_insert
        self.slug = compute_slug if slug.blank?
      end
    end
  end

  def build_postgres_race_model(&block)
    klass = Class.new(postgres_strict_slug_model) do
      self.table_name = "pg_strict_slug_models"
    end

    klass.class_eval(&block) if block
    klass
  end
end
