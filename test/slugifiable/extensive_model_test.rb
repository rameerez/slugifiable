require "test_helper"

class Slugifiable::ExtensiveModelTest < Minitest::Test
  def setup
    # Clear test models
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    # Reset any previous slug generation strategy on TestModel
    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)

      # Remove test-specific methods to avoid redefinition warnings
      remove_method(:custom_title) if method_defined?(:custom_title)
      remove_method(:nil_method) if method_defined?(:nil_method)
      remove_method(:numeric_title) if method_defined?(:numeric_title)
      remove_method(:private_title) if private_method_defined?(:private_title)
      remove_method(:protected_title) if protected_method_defined?(:protected_title)
    end
  end

  # ============================================================================
  # Basic/Default Behavior
  # ============================================================================

  def test_default_slug_generation
    # When no generate_slug_based_on is defined, default is based on :id.
    model = TestModel.create!(title: "Test Title")
    expected_slug = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected_slug, model.slug, "Default slug should be the SHA2 digest truncated to default length"
  end

  def test_after_find_callback_updates_nil_slug
    # After find, if slug is nil, it is recomputed.
    model = TestModel.create!(title: "Test Title")
    model.update_column(:slug, nil)
    model_found = TestModel.find(model.id)
    refute_nil model_found.slug, "After find, nil slug should be updated"
  end

  def test_slug_not_updated_if_present_and_id_unchanged
    # If slug is already set (and id hasn't changed), set_slug shouldn't alter it.
    model = TestModel.create!(title: "Original Title")
    orig_slug = model.slug
    model.update!(title: "New Title")  # change a non-slug attribute
    model.send(:set_slug)
    model.reload
    assert_equal orig_slug, model.slug, "Slug should remain unchanged if already present"
  end

  # ============================================================================
  # Attribute-Based Slug Tests
  # ============================================================================

  def test_slug_based_on_db_attribute
    TestModel.class_eval do
      generate_slug_based_on :title
    end
    model = TestModel.create!(title: "My Test Title")
    assert_equal "my-test-title", model.slug, "Slug should be parameterized from the title attribute"
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

  def test_attribute_is_not_a_string
    # Test when the attribute method returns a numeric value
    TestModel.class_eval do
      generate_slug_based_on :numeric_title

      def numeric_title
        12345
      end
    end
    model = TestModel.create!(title: "Ignored")
    # Parameterize "12345" should yield "12345"
    assert_equal "12345", model.slug, "Numeric attribute should be converted to string and parameterized"
  end

  # ============================================================================
  # Method-Based Slug Tests
  # ============================================================================

  def test_slug_based_on_method
    TestModel.class_eval do
      generate_slug_based_on :custom_title

      def custom_title
        "#{title} Custom"
      end
    end
    model = TestModel.create!(title: "My Test")
    assert_equal "my-test-custom", model.slug, "Slug should be computed from the custom method"
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
    assert_equal expected_slug, model.slug, "Method returning nil should fall back to random number based slug"
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
    assert_equal "private-test", model.slug, "Should use a private method to compute slug"
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
    assert_equal "protected-test", model.slug, "Should use a protected method to compute slug"
  end

  # ============================================================================
  # Hash/Option-Based Strategy Tests
  # ============================================================================

  def test_hash_based_attribute_strategy_with_extra_options
    # Test when using a hash with :attribute and extra options (like custom length)
    TestModel.class_eval do
      generate_slug_based_on attribute: :title, length: 15
    end
    model = TestModel.create!(title: "A Longer Test Title")
    # The raw parameterized value should be "a-longer-test-title"
    base_slug = "a-longer-test-title"
    # Because the compute_slug_based_on_attribute uses generate_unique_slug,
    # and our test DB is empty, it should simply return the parameterized value if present.
    # But note: if base_slug length exceeds custom length (15), our implementation might not truncate.
    # In our implementation, the custom length is only passed to compute_slug_as_string or compute_slug_as_number.
    # For attribute-based generation, length option is not directly used unless in a collision.
    # So we only test that the slug starts with the base_slug.
    assert model.slug.start_with?(base_slug), "Slug computed with hash strategy should start with the parameterized attribute"
  end

  # ============================================================================
  # Collision Resolution Tests
  # ============================================================================

  def test_collision_resolution
    TestModel.class_eval do
      generate_slug_based_on :title
    end
    # Create first record
    model1 = TestModel.create!(title: "Same Title")
    base_slug = model1.slug

    # Override exists? to force collisions for a set number of attempts
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
      refute_equal model1.slug, model2.slug, "Collision should result in a different slug"
      assert model2.slug.start_with?("#{base_slug}-"), "Collision should append a suffix to the base slug"
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
    end
  end

  def test_collision_resolution_with_timestamp_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end
    # Force collisions to always be true to trigger timestamp fallback.
    original_exists = TestModel.method(:exists?)
    begin
      TestModel.define_singleton_method(:exists?) { |_conditions| true }
      model = TestModel.create!(title: "Test")
      # Expect a slug in the format "test-<timestamp>" (timestamp is 10+ digits)
      assert_match(/\Atest-\d{10,}\z/, model.slug, "Should fall back to timestamp after max attempts")
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
      TestModel.define_singleton_method(:exists?, original_exists) # Restore original method
    end
  end

  # ============================================================================
  # Internal Method and Helper Tests
  # ============================================================================

  def test_determine_slug_generation_method_default
    # When no explicit strategy is defined, default to compute_slug_as_string.
    model = TestModel.create!(title: "Test")
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
    assert_equal :compute_slug_based_on_attribute, method_sym, "Strategy should be compute_slug_based_on_attribute"
    assert_equal :title, strategy, "Should use the :title attribute"
  end

  def test_compute_slug_as_string_with_length
    model = TestModel.create!(title: "Test")
    slug = model.send(:compute_slug_as_string, 5)
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, 5]
    assert_equal expected, slug, "Should respect custom length for string slug"
  end

  def test_compute_slug_as_number_with_length
    model = TestModel.create!(title: "Test")
    slug = model.send(:compute_slug_as_number, 4)
    expected = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** 4))
    assert_equal expected, slug, "Should respect custom length for numeric slug"
  end

  def test_generate_random_number_based_on_id_hex_returns_valid_number
    model = TestModel.create!(title: "Test")
    num = model.send(:generate_random_number_based_on_id_hex, 6)
    assert num.is_a?(Integer), "Random number based on id hex should be an Integer"
    assert num < 10**6, "Random number should be less than 10^6"
  end

  def test_slug_persisted_returns_true_if_slug_column_exists
    model = TestModel.create!(title: "Test")
    assert model.send(:slug_persisted?), "slug_persisted? should be true when the model has a slug column"
  end

  def test_slug_persisted_returns_false_for_model_without_slug_column
    model = TestModelWithoutSlug.create!(title: "No Persist")
    refute model.send(:slug_persisted?), "slug_persisted? should be false for models without a slug column"
  end

  def test_update_slug_if_nil_does_not_override_existing_slug
    model = TestModel.create!(title: "Test")
    original_slug = model.slug
    # Manually set slug to non-nil
    model.update_column(:slug, original_slug)
    model.send(:update_slug_if_nil)
    model.reload
    assert_equal original_slug, model.slug, "update_slug_if_nil should not change an existing slug"
  end

  # ============================================================================
  # Special Cases
  # ============================================================================

  def test_model_without_slug_column
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end
    model = TestModelWithoutSlug.create!(title: "No Persist")
    # When no slug column, compute_slug should simply return the parameterized title.
    assert_equal "no-persist", model.slug, "Model without slug column should return parameterized title"
  end

  def test_generate_slug_based_on_method_redefinition
    # Ensure that calling generate_slug_based_on multiple times resets the strategy.
    TestModel.class_eval do
      generate_slug_based_on :title
    end
    model1 = TestModel.create!(title: "Title One")
    slug1 = model1.slug

    # Redefine strategy to use a custom method now.
    TestModel.class_eval do
      generate_slug_based_on :custom_title

      def custom_title
        "Custom #{title}"
      end
    end
    model2 = TestModel.create!(title: "Title Two")
    slug2 = model2.slug

    refute_equal slug1, slug2, "Redefining generate_slug_based_on should change slug generation strategy"
    assert_equal "custom-title-two", slug2, "Slug should reflect new custom method strategy"
  end
end
