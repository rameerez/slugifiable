require "test_helper"

class Slugifiable::ModelTest < Minitest::Test
  def setup
    # Clear the database before each test
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    # Reset any previous slug generation strategy
    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # --- Default Behavior Tests ---

  def test_default_slug_generation
    model = TestModel.create!(title: "Test Title")
    expected_slug = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected_slug, model.slug, "Default slug should be the SHA2 digest truncated to default length"
  end

  def test_after_find_callback_updates_nil_slug
    model = TestModel.create!
    # Manually set slug to nil bypassing validations/callbacks
    model.update_column(:slug, nil)
    model_found = TestModel.find(model.id)
    refute_nil model_found.slug, "After find, nil slug should be updated"
  end

  # --- Attribute-Based Slug Tests ---

  def test_slug_based_on_db_attribute
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "My Test Title")
    assert_equal "my-test-title", model.slug
  end

  def test_nil_attribute_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: nil)
    expected_slug = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    model.reload
    assert_equal expected_slug, model.slug, "Nil attribute should fall back to random number based slug"
  end

  def test_empty_attribute_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "   ")
    expected_slug = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    model.reload
    assert_equal expected_slug, model.slug, "Blank attribute should fall back to random number based slug"
  end

  # --- Method-Based Slug Tests ---

  def test_slug_based_on_method
    TestModel.class_eval do
      generate_slug_based_on :custom_title

      def custom_title
        "#{title} Custom"
      end
    end

    model = TestModel.create!(title: "My Test")
    assert_equal "my-test-custom", model.slug
  end

  def test_method_returning_nil_fallback
    TestModel.class_eval do
      generate_slug_based_on :nil_method

      def nil_method
        nil
      end
    end

    model = TestModel.create!(title: "Test")
    expected_slug = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    model.reload
    assert_equal expected_slug, model.slug, "Nil method should fall back to random number based slug"
  end

  def test_private_method_slug_generation
    TestModel.class_eval do
      generate_slug_based_on :private_title

      private

      def private_title
        "Private #{title}"
      end
    end

    model = TestModel.create!(title: "Test")
    assert_equal "private-test", model.slug
  end

  def test_protected_method_slug_generation
    TestModel.class_eval do
      generate_slug_based_on :protected_title

      protected

      def protected_title
        "Protected #{title}"
      end
    end

    model = TestModel.create!(title: "Test")
    assert_equal "protected-test", model.slug
  end

  # --- Collision Resolution Tests ---

  def test_collision_resolution
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Create first record
    model1 = TestModel.create!(title: "Same Title")
    base_slug = model1.slug

    # Override exists? to force collisions
    original_exists = TestModel.method(:exists?)
    collision_counter = 0
    TestModel.define_singleton_method(:exists?) do |conditions|
      if conditions[:slug]&.start_with?(base_slug) && collision_counter < Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
        collision_counter += 1
        true
      else
        original_exists.call(conditions)
      end
    end

    begin
      model2 = TestModel.create!(title: "Same Title")
      refute_equal model1.slug, model2.slug, "Collision should result in different slugs"
      assert model2.slug.start_with?("#{base_slug}-"), "Collision should append a suffix"
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
    end
  end

  def test_collision_resolution_with_timestamp_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Force collisions to trigger timestamp fallback
    original_exists = TestModel.method(:exists?)
    begin
      TestModel.define_singleton_method(:exists?) { |_conditions| true }
      model = TestModel.create!(title: "Test")
      assert_match(/\Atest-\d{10,}\z/, model.slug, "Should fall back to timestamp after max attempts")
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
      TestModel.define_singleton_method(:exists?, original_exists) # Restore original method
    end
  end

  # --- Internal Method Tests ---

  def test_determine_slug_generation_method_default
    model = TestModel.create!
    method_sym, options = model.send(:determine_slug_generation_method)
    assert_equal :compute_slug_as_string, method_sym, "Default strategy should be compute_slug_as_string"
    assert_equal({}, options, "Default options should be empty")
  end

  def test_determine_slug_generation_method_attribute
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Test")
    method_sym, strategy = model.send(:determine_slug_generation_method)
    assert_equal :compute_slug_based_on_attribute, method_sym
    assert_equal :title, strategy
  end

  def test_compute_slug_as_string_with_length
    model = TestModel.create!
    slug = model.send(:compute_slug_as_string, 5)
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, 5]
    assert_equal expected, slug, "Should respect custom length"
  end

  def test_compute_slug_as_number_with_length
    model = TestModel.create!
    slug = model.send(:compute_slug_as_number, 4)
    expected = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** 4))
    assert_equal expected, slug, "Should respect custom length"
  end

  # --- Special Cases ---

  def test_model_without_slug_column
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    model = TestModelWithoutSlug.create!(title: "No Persist")
    assert_equal "no-persist", model.slug
  end
end
