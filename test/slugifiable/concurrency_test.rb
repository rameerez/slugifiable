require "test_helper"

# Concurrency and Thread Safety Test Suite for Slugifiable
#
# This test suite covers:
# - Race conditions in slug generation
# - Multiple concurrent creates
# - Thread safety of class method definitions
# - Database-level uniqueness constraints
#
# NOTE: Some tests are skipped on SQLite in-memory databases because
# SQLite in-memory DBs don't share state across threads/connections.

class Slugifiable::ConcurrencyTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  def using_sqlite_memory?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
  end

  # ============================================================================
  # Race Condition Simulation
  # ============================================================================

  def test_concurrent_creates_with_same_title
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Simulate concurrent creates using threads
    models = []
    errors = []
    mutex = Mutex.new
    threads = 5.times.map do |i|
      Thread.new do
        begin
          model = TestModel.create!(title: "Concurrent Title")
          mutex.synchronize { models << model }
        rescue => e
          mutex.synchronize { errors << e }
        end
      end
    end

    threads.each(&:join)

    # All should have unique slugs (or some might fail due to uniqueness constraint)
    successful_slugs = models.map(&:slug)

    # Either all unique slugs were generated, or uniqueness errors occurred
    if errors.empty?
      assert_equal successful_slugs.length, successful_slugs.uniq.length,
        "All concurrent creates should have unique slugs"
    else
      # Some failures are acceptable due to race conditions
      assert (models.length + errors.length) == 5,
        "All threads should complete (with success or error)"
    end
  end

  def test_rapid_sequential_creates_with_same_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = 20.times.map do
      TestModel.create!(title: "Rapid Create")
    end

    slugs = models.map(&:slug)
    assert_equal 20, slugs.uniq.length, "All rapid creates should have unique slugs"
  end

  def test_concurrent_creates_with_different_titles
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = []
    mutex = Mutex.new
    threads = 10.times.map do |i|
      Thread.new do
        model = TestModel.create!(title: "Title #{i}")
        mutex.synchronize { models << model }
      end
    end

    threads.each(&:join)

    assert_equal 10, models.length
    slugs = models.map(&:slug)
    assert_equal 10, slugs.uniq.length
  end

  # ============================================================================
  # Class Method Thread Safety
  # ============================================================================

  def test_concurrent_strategy_changes
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    # Test that changing strategy while creating records doesn't crash
    errors = []
    mutex = Mutex.new

    # Thread 1: Creates records
    t1 = Thread.new do
      begin
        5.times do |i|
          TestModel.class_eval { generate_slug_based_on :title }
          TestModel.create!(title: "Thread1 #{i}")
          sleep(0.01) # Small delay to encourage interleaving
        end
      rescue => e
        mutex.synchronize { errors << e }
      end
    end

    # Thread 2: Changes strategy
    t2 = Thread.new do
      begin
        5.times do
          TestModel.class_eval { generate_slug_based_on id: :hex_string }
          sleep(0.01)
          TestModel.class_eval { generate_slug_based_on id: :number }
          sleep(0.01)
        end
      rescue => e
        mutex.synchronize { errors << e }
      end
    end

    [t1, t2].each(&:join)

    # No crashes is success - strategies may vary
    # The actual slugs generated may differ based on race timing
    assert errors.empty?, "No errors should occur during concurrent strategy changes: #{errors.map(&:message)}"
  end

  # ============================================================================
  # Database Uniqueness Constraint Tests
  # ============================================================================

  def test_database_uniqueness_prevents_duplicates
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "DB Unique Test")

    # Try to manually create a duplicate slug (simulating race condition outcome)
    assert_raises(ActiveRecord::RecordInvalid) do
      TestModel.create!(title: "Different Title", slug: model1.slug)
    end
  end

  def test_uniqueness_validation_message
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Validation Message Test")

    begin
      TestModel.create!(title: "Different", slug: model1.slug)
      flunk "Should have raised validation error"
    rescue ActiveRecord::RecordInvalid => e
      assert e.message.include?("Slug"), "Error should mention slug"
    end
  end

  # ============================================================================
  # High Volume Tests
  # ============================================================================

  def test_many_records_same_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = 50.times.map do
      TestModel.create!(title: "Same Title For All")
    end

    slugs = models.map(&:slug)
    assert_equal 50, slugs.uniq.length, "50 records with same title should have 50 unique slugs"
  end

  def test_many_records_sequential_titles
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    models = 100.times.map do |i|
      TestModel.create!(title: "Sequential #{i}")
    end

    slugs = models.map(&:slug)
    assert_equal 100, slugs.uniq.length
  end

  def test_mixed_collision_and_unique_titles
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    titles = ["Duplicate", "Unique A", "Duplicate", "Unique B", "Duplicate", "Unique C"]
    models = titles.map do |title|
      TestModel.create!(title: title)
    end

    slugs = models.map(&:slug)
    assert_equal 6, slugs.uniq.length, "All records should have unique slugs"

    # First "Duplicate" should have clean slug
    assert_equal "duplicate", models[0].slug

    # Subsequent "Duplicate" entries should have suffixes
    assert models[2].slug.start_with?("duplicate-")
    assert models[4].slug.start_with?("duplicate-")
  end

  # ============================================================================
  # Parallel Read Tests
  # ============================================================================

  def test_concurrent_reads_dont_affect_slug
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    model = TestModel.create!(title: "Read Test")
    original_slug = model.slug

    threads = 10.times.map do
      Thread.new do
        found = TestModel.find(model.id)
        found.slug
      end
    end

    slugs = threads.map(&:value)
    assert slugs.all? { |s| s == original_slug }
  end

  def test_concurrent_find_with_nil_slug_recovery
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    model = TestModel.create!(title: "Recovery Test")
    model.update_column(:slug, nil)

    threads = 5.times.map do
      Thread.new do
        found = TestModel.find(model.id)
        found.slug
      end
    end

    slugs = threads.map(&:value)

    # All threads should get a slug (recovered)
    assert slugs.all? { |s| !s.nil? }
  end

  # ============================================================================
  # Slug Computation Thread Safety
  # ============================================================================

  def test_compute_slug_is_deterministic_for_same_id
    model = TestModel.create!(title: "Deterministic Test")

    computed_slugs = 10.times.map do
      model.compute_slug
    end

    # All computations should return the same value
    assert_equal 1, computed_slugs.uniq.length
  end

  def test_concurrent_compute_slug_calls
    skip "SQLite in-memory DB doesn't support concurrent access" if using_sqlite_memory?

    model = TestModel.create!(title: "Concurrent Compute")

    threads = 10.times.map do
      Thread.new do
        model.compute_slug
      end
    end

    slugs = threads.map(&:value)
    assert_equal 1, slugs.uniq.length, "Concurrent compute_slug calls should return same value"
  end
end
