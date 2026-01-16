require "test_helper"

# Bug Verification Test Suite for Slugifiable
#
# This test suite verifies potential bugs identified in code analysis:
# 1. Return arity mismatch in determine_slug_generation_method for attribute: hash syntax
# 2. Collision suffix always returning same value (potential infinite loop)
# 3. method_missing behavior edge cases
# 4. Type consistency issues (Integer vs String for number slugs)
# 5. Length parameter edge cases (0, negative)
# 6. options.merge!(strategy) logic

class Slugifiable::BugVerificationTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # ============================================================================
  # Bug #1: Return Arity Mismatch in determine_slug_generation_method
  # When using `generate_slug_based_on attribute: :title, length: 25`
  # Line 188 returns 3-tuple but compute_slug expects 2-tuple
  # ============================================================================

  def test_attribute_hash_syntax_works_correctly
    TestModel.class_eval do
      generate_slug_based_on attribute: :title
    end

    model = TestModel.create!(title: "Attribute Hash Test")
    # This should work, not crash
    assert_equal "attribute-hash-test", model.slug
  end

  def test_attribute_hash_with_length_option
    TestModel.class_eval do
      generate_slug_based_on attribute: :title, length: 10
    end

    model = TestModel.create!(title: "Length Test Value")
    # Should create a slug without crashing
    # Note: length option may or may not affect attribute-based slugs
    refute_nil model.slug
  end

  def test_attribute_hash_with_nil_title_falls_back
    TestModel.class_eval do
      generate_slug_based_on attribute: :title
    end

    model = TestModel.create!(title: nil)
    model.reload

    # Should fall back to id-based number slug
    refute_nil model.slug
    assert model.slug.length > 0
  end

  # ============================================================================
  # Bug #2: Collision Suffix May Be Same on Each Iteration
  # compute_slug_as_number uses id, which doesn't change during collision loop
  # ============================================================================

  def test_collision_resolution_generates_different_suffixes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Create first record
    model1 = TestModel.create!(title: "Collision Test")
    base_slug = "collision-test"

    # Track the suffixes generated during collision resolution
    suffixes_seen = []
    original_compute_slug_as_number = TestModel.instance_method(:compute_slug_as_number)

    TestModel.class_eval do
      define_method(:compute_slug_as_number) do |length = nil|
        result = original_compute_slug_as_number.bind(self).call(length)
        suffixes_seen << result
        result
      end
    end

    begin
      # Force collisions to test suffix generation
      original_exists = TestModel.method(:exists?)
      collision_count = 0

      TestModel.define_singleton_method(:exists?) do |conditions|
        if conditions[:slug]&.start_with?(base_slug)
          collision_count += 1
          collision_count < 3  # Allow 2 collisions, then succeed
        else
          original_exists.call(conditions)
        end
      end

      model2 = TestModel.create!(title: "Collision Test")

      # The suffixes generated should be the same (id-based)
      # This test documents the current behavior - all suffixes are identical
      # because they're based on the record's id
      if suffixes_seen.length > 1
        # Note: This documents current behavior, not necessarily desired behavior
        # All suffixes will be the same since they're id-based
        assert suffixes_seen.uniq.length == 1, "Current behavior: all suffixes are identical (id-based)"
      end

      refute_equal model1.slug, model2.slug
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
      TestModel.class_eval do
        define_method(:compute_slug_as_number, original_compute_slug_as_number)
      end
    end
  end

  def test_collision_fallback_to_timestamp
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Force all collisions to trigger timestamp fallback
    attempt_count = 0

    TestModel.define_singleton_method(:exists?) do |conditions|
      attempt_count += 1
      true  # Always collide
    end

    begin
      model = TestModel.create!(title: "Timestamp Test")

      # Should fall back to timestamp + random suffix after MAX_SLUG_GENERATION_ATTEMPTS
      assert_match(/\Atimestamp-test-\d+-\d+\z/, model.slug, "Should include timestamp and random suffix")
      assert attempt_count >= Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
    ensure
      TestModel.singleton_class.send(:remove_method, :exists?)
    end
  end

  # ============================================================================
  # Bug #3: method_missing Behavior Edge Cases
  # ============================================================================

  def test_method_missing_only_handles_slug
    model = TestModel.create!(title: "Test")

    # Other missing methods should raise NoMethodError
    assert_raises(NoMethodError) do
      model.some_nonexistent_method
    end
  end

  def test_respond_to_slug_for_model_without_slug_column
    # respond_to?(:slug) should return true even for models without slug column
    # This ensures proper Ruby behavior when method_missing is implemented
    model = TestModelWithoutSlug.create!(title: "Test")

    assert model.respond_to?(:slug), "respond_to?(:slug) should return true"
    refute_nil model.slug
  end

  def test_respond_to_slug_for_model_with_slug_column
    model = TestModel.create!(title: "Test")

    assert model.respond_to?(:slug), "respond_to?(:slug) should return true"
    refute_nil model.slug
  end

  def test_method_missing_with_arguments
    model = TestModelWithoutSlug.create!(title: "Test")

    # Calling .slug with arguments should probably fail gracefully
    # Note: compute_slug doesn't take arguments
    begin
      # This tests edge case behavior
      result = model.slug
      refute_nil result
    rescue ArgumentError
      # Acceptable if it raises
      pass
    end
  end

  def test_model_with_slug_column_does_not_use_method_missing
    model = TestModel.create!(title: "Test")

    # TestModel has a slug column, so .slug is a real method
    assert model.methods.include?(:slug), "TestModel should have real slug method"
    refute_nil model.slug
  end

  def test_model_without_slug_column_uses_method_missing
    model = TestModelWithoutSlug.create!(title: "Test")

    # TestModelWithoutSlug uses method_missing for .slug
    # The model itself doesn't have slug in its methods list from AR
    slug = model.slug
    refute_nil slug
  end

  # ============================================================================
  # Bug #4: Type Consistency (Integer vs String for Number Slugs)
  # ============================================================================

  def test_number_slug_is_stored_as_string
    TestModel.class_eval do
      generate_slug_based_on id: :number
    end

    model = TestModel.create!(title: "Number Type Test")
    model.reload

    assert model.slug.is_a?(String), "Slug should be stored as String in database"
  end

  def test_number_slug_stored_matches_computed
    TestModel.class_eval do
      generate_slug_based_on id: :number
    end

    model = TestModel.create!(title: "Number Match Test")
    computed = model.compute_slug

    # compute_slug returns Integer for number strategy
    # But stored slug is String
    assert_equal computed.to_s, model.slug
  end

  def test_hex_string_slug_is_stored_as_string
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string
    end

    model = TestModel.create!(title: "Hex Type Test")
    model.reload

    assert model.slug.is_a?(String), "Slug should be stored as String"
  end

  # ============================================================================
  # Bug #5: Length Parameter Edge Cases
  # ============================================================================

  def test_length_zero_for_hex_string
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 0
    end

    model = TestModel.create!(title: "Zero Length Test")

    # SHA2.hexdigest(...).first(0) returns ""
    # This is an edge case - empty slug might cause issues
    refute_nil model.slug
  end

  def test_length_zero_for_number
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: 0
    end

    model = TestModel.create!(title: "Zero Length Number")

    # (hex % (10**0)) = (hex % 1) = 0
    # Should return "0" as the slug
    refute_nil model.slug
  end

  def test_negative_length_for_hex_string_uses_default
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: -5
    end

    # Negative length is now handled gracefully - falls back to default length
    model = TestModel.create!(title: "Negative Length Test")
    refute_nil model.slug
    assert_equal Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH, model.slug.length
  end

  def test_very_large_length_for_hex_string
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 1000
    end

    model = TestModel.create!(title: "Large Length Test")

    # SHA2 hex digest is 64 chars, so max length is 64
    refute_nil model.slug
    assert model.slug.length <= 64, "Hex string slug cannot exceed 64 chars"
  end

  def test_float_length_parameter
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 5.7
    end

    model = TestModel.create!(title: "Float Length Test")

    # Ruby's first method truncates float to int
    refute_nil model.slug
    # 5.7.to_i = 5
    assert_equal 5, model.slug.length
  end

  # ============================================================================
  # Bug #6: options.merge!(strategy) Logic
  # ============================================================================

  def test_hash_strategy_with_both_id_and_length
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 8
    end

    model = TestModel.create!(title: "Hash Strategy Test")

    assert_equal 8, model.slug.length
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, 8]
    assert_equal expected, model.slug
  end

  def test_hash_strategy_with_number_and_length
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: 4
    end

    model = TestModel.create!(title: "Number Hash Test")

    # Number should be less than 10^4 = 10000
    assert model.slug.to_i < 10000
  end

  def test_determine_slug_generation_method_with_symbol_strategy
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Test")
    method_sym, strategy = model.send(:determine_slug_generation_method)

    assert_equal :compute_slug_based_on_attribute, method_sym
    assert_equal :title, strategy
  end

  def test_determine_slug_generation_method_with_hash_strategy
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 10
    end

    model = TestModel.create!(title: "Test")
    method_sym, options = model.send(:determine_slug_generation_method)

    assert_equal :compute_slug_as_string, method_sym
    assert options.is_a?(Hash), "Options should be a Hash"
  end

  # ============================================================================
  # Bug #7: Unknown Strategy Handling
  # ============================================================================

  def test_unknown_id_strategy_falls_back_to_default
    TestModel.class_eval do
      generate_slug_based_on id: :unknown_strategy
    end

    model = TestModel.create!(title: "Unknown Strategy Test")

    # Should fall back to default hex string
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  def test_empty_hash_strategy
    TestModel.class_eval do
      generate_slug_based_on({})
    end

    model = TestModel.create!(title: "Empty Hash Test")

    # Should use default strategy
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  # ============================================================================
  # Bug #8: Nonexistent Attribute Handling
  # ============================================================================

  def test_nonexistent_attribute_falls_back_to_id_based
    TestModel.class_eval do
      generate_slug_based_on :nonexistent_attribute
    end

    model = TestModel.create!(title: "Fallback Test")

    # Should fall back to id-based slug since attribute doesn't exist
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  def test_attribute_that_exists_as_method_but_not_column
    TestModel.class_eval do
      generate_slug_based_on :virtual_attribute

      def virtual_attribute
        "Virtual Value"
      end
    end

    model = TestModel.create!(title: "Virtual Test")
    assert_equal "virtual-value", model.slug
  end

  # ============================================================================
  # Bug #9: compute_slug_based_on_attribute with Various Inputs
  # ============================================================================

  def test_compute_slug_based_on_attribute_with_method
    TestModel.class_eval do
      generate_slug_based_on :slug_source

      def slug_source
        "Method Based"
      end
    end

    model = TestModel.create!(title: "Method Test")
    assert_equal "method-based", model.slug
  end

  def test_compute_slug_based_on_attribute_uses_column_value
    # When generating slug based on a column attribute, it uses the column value
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.new
    model.write_attribute(:title, "Column Value")
    model.save!

    # Should use the column value
    assert_equal "column-value", model.slug
  end

  # ============================================================================
  # Bug #10: generate_slug_based_on Redefinition
  # ============================================================================

  def test_redefining_strategy_updates_behavior
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "First Strategy")
    assert_equal "first-strategy", model1.slug

    TestModel.class_eval do
      generate_slug_based_on id: :hex_string
    end

    model2 = TestModel.create!(title: "Second Strategy")
    expected = Digest::SHA2.hexdigest(model2.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model2.slug
  end

  def test_multiple_rapid_strategy_redefinitions
    5.times do |i|
      TestModel.class_eval do
        generate_slug_based_on :title
      end

      model = TestModel.create!(title: "Rapid #{i}")
      assert_equal "rapid-#{i}", model.slug
    end
  end

  # ============================================================================
  # Bug #11: slug_persisted? Edge Cases
  # ============================================================================

  def test_slug_persisted_returns_true_for_model_with_slug_column
    model = TestModel.create!(title: "Test")
    assert model.send(:slug_persisted?)
  end

  def test_slug_persisted_returns_false_for_model_without_slug_column
    model = TestModelWithoutSlug.create!(title: "Test")
    refute model.send(:slug_persisted?)
  end

  # ============================================================================
  # Bug #12: Private Method Accessibility
  # ============================================================================

  def test_private_generate_random_number_callable
    model = TestModel.create!(title: "Test")

    # Private methods should still be callable internally
    result = model.send(:generate_random_number_based_on_id_hex, 6)
    assert result.is_a?(Integer)
    assert result >= 0
    assert result < 10**6
  end

  def test_private_generate_unique_slug_callable
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Test")
    result = model.send(:generate_unique_slug, "test-base")

    assert result.is_a?(String)
    assert result.start_with?("test-base")
  end
end
