require "test_helper"

# API Documentation Test Suite for Slugifiable
#
# This test suite serves as living documentation for the gem's public API.
# Each test demonstrates a feature documented in the README.
# These tests should always pass and serve as examples for users.

class Slugifiable::ApiDocumentationTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
      remove_method(:title_with_location) if method_defined?(:title_with_location)
    end
  end

  # ============================================================================
  # README Example: Basic Usage
  # ============================================================================

  def test_basic_inclusion_provides_slug_method
    # From README: "That's it! Then you can get the slug for a product"
    model = TestModel.create!(title: "Test Product")

    # .slug method should be available
    refute_nil model.slug
    assert model.slug.is_a?(String)
  end

  def test_default_slug_is_hex_string_based_on_id
    # From README: "By default, slugs will be generated as a random-looking string
    # based off the record id (SHA hash)"
    model = TestModel.create!(title: "Test")

    # Default slug should be 11 characters (DEFAULT_SLUG_STRING_LENGTH)
    assert_equal Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH, model.slug.length

    # Should be hex characters only
    assert model.slug.match?(/\A[0-9a-f]+\z/)
  end

  # ============================================================================
  # README Example: generate_slug_based_on :attribute
  # ============================================================================

  def test_slug_based_on_name_attribute
    # From README:
    # ```ruby
    # class Product < ApplicationRecord
    #   include Slugifiable::Model
    #   generate_slug_based_on :name
    # end
    # ```
    TestModel.class_eval do
      generate_slug_based_on :title  # Using :title as our equivalent to :name
    end

    model = TestModel.create!(title: "Big Red Backpack")
    assert_equal "big-red-backpack", model.slug
  end

  # ============================================================================
  # README Example: generate_slug_based_on id: :hex_string
  # ============================================================================

  def test_explicit_hex_string_strategy
    # From README:
    # ```ruby
    # generate_slug_based_on id: :hex_string
    # ```
    # "Which returns slugs like: d4735e3a265"
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string
    end

    model = TestModel.create!(title: "Test")

    # Should be hex string
    assert model.slug.match?(/\A[0-9a-f]+\z/)
    assert_equal Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH, model.slug.length
  end

  # ============================================================================
  # README Example: generate_slug_based_on id: :number
  # ============================================================================

  def test_number_only_slugs
    # From README:
    # ```ruby
    # generate_slug_based_on id: :number
    # ```
    # "Which will return slugs like: 321678 – nonconsecutive, nonincremental"
    TestModel.class_eval do
      generate_slug_based_on id: :number
    end

    model = TestModel.create!(title: "Test")

    # Should be numeric only
    assert model.slug.match?(/\A\d+\z/)
  end

  # ============================================================================
  # README Example: Custom Length
  # ============================================================================

  def test_custom_length_for_id_based_slugs
    # From README:
    # ```ruby
    # generate_slug_based_on id: :number, length: 3
    # ```
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: 3
    end

    model = TestModel.create!(title: "Test")

    # Number should be less than 10^3 = 1000
    assert model.slug.to_i < 1000
  end

  def test_custom_length_for_hex_string
    # From README:
    # ```ruby
    # generate_slug_based_on :id, length: 6
    # ```
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 6
    end

    model = TestModel.create!(title: "Test")
    assert_equal 6, model.slug.length
  end

  # ============================================================================
  # README Example: Method-Based Slugs
  # ============================================================================

  def test_instance_method_for_complex_slugs
    # From README:
    # ```ruby
    # class Event < ApplicationRecord
    #   include Slugifiable::Model
    #   belongs_to :location
    #
    #   generate_slug_based_on :title_with_location
    #
    #   def title_with_location
    #     if location.present?
    #       "#{title} #{location.city} #{location.region}"
    #     else
    #       title
    #     end
    #   end
    # end
    # ```
    TestModel.class_eval do
      generate_slug_based_on :title_with_location

      def title_with_location
        "#{title} New York"
      end
    end

    model = TestModel.create!(title: "My Awesome Event")
    assert_equal "my-awesome-event-new-york", model.slug
  end

  # ============================================================================
  # README Example: Collision Resolution
  # ============================================================================

  def test_collision_adds_unique_suffix
    # From README:
    # "There may be collisions if two records share the same name – but slugs should
    # be unique! To resolve this, when this happens, slugifiable will append a
    # unique string at the end to make the slug unique"
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model1 = TestModel.create!(title: "Big Red Backpack")
    model2 = TestModel.create!(title: "Big Red Backpack")

    assert_equal "big-red-backpack", model1.slug
    assert model2.slug.start_with?("big-red-backpack-")
    refute_equal model1.slug, model2.slug
  end

  # ============================================================================
  # README Example: Slug Persistence
  # ============================================================================

  def test_slug_persisted_to_database
    # From README:
    # "When a model has a slug attribute, slugifiable automatically generates
    # a slug for that model upon instance creation, and saves it to the DB."
    model = TestModel.create!(title: "Persisted Slug Test")

    # Reload from database to verify persistence
    model_from_db = TestModel.find(model.id)
    assert_equal model.slug, model_from_db.slug
  end

  def test_slug_never_changes_after_creation
    # From README: "Slugs should never change"
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Original Title")
    original_slug = model.slug

    model.update!(title: "Completely Different Title")
    model.reload

    assert_equal original_slug, model.slug, "Slug should not change after creation"
  end

  # ============================================================================
  # README Example: Working Without Persistence
  # ============================================================================

  def test_slug_works_without_persistence
    # From README:
    # "slugifiable can also work without persisting slugs to the database:
    # you can always run .slug, and that will give you a valid, unique slug"
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    model = TestModelWithoutSlug.create!(title: "Non Persisted")
    assert_equal "non-persisted", model.slug
  end

  # ============================================================================
  # API Constants
  # ============================================================================

  def test_default_slug_string_length_constant
    # The gem uses this constant for default hex string length
    assert_equal 11, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH
  end

  def test_default_slug_number_length_constant
    # The gem uses this constant for default number length
    assert_equal 6, Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH
  end

  def test_max_slug_generation_attempts_constant
    # The gem uses this constant for collision resolution
    assert_equal 10, Slugifiable::Model::MAX_SLUG_GENERATION_ATTEMPTS
  end

  # ============================================================================
  # Public Methods
  # ============================================================================

  def test_compute_slug_is_public
    model = TestModel.create!(title: "Public Method Test")
    assert model.respond_to?(:compute_slug)
    refute_nil model.compute_slug
  end

  def test_compute_slug_as_string_is_public
    model = TestModel.create!(title: "Public Method Test")
    assert model.respond_to?(:compute_slug_as_string)
    refute_nil model.compute_slug_as_string
  end

  def test_compute_slug_as_number_is_public
    model = TestModel.create!(title: "Public Method Test")
    assert model.respond_to?(:compute_slug_as_number)
    refute_nil model.compute_slug_as_number
  end

  def test_compute_slug_based_on_attribute_is_public
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Attribute Method Test")
    assert model.respond_to?(:compute_slug_based_on_attribute)
    # Note: This may include a suffix if there's a collision with the already-saved slug
    result = model.compute_slug_based_on_attribute(:title)
    assert result.start_with?("attribute-method-test")
  end

  # ============================================================================
  # Finder Support
  # ============================================================================

  def test_find_by_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Findable Item")

    found = TestModel.find_by(slug: model.slug)
    assert_equal model.id, found.id
  end

  def test_where_by_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Queryable Item")

    found = TestModel.where(slug: model.slug).first
    assert_equal model.id, found.id
  end

  # ============================================================================
  # Parameterization Behavior
  # ============================================================================

  def test_parameterization_lowercases
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "UPPERCASE TITLE")
    assert_equal "uppercase-title", model.slug
  end

  def test_parameterization_replaces_spaces_with_dashes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Title With Spaces")
    assert_equal "title-with-spaces", model.slug
  end

  def test_parameterization_removes_special_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello! What's this? A title...")
    assert_equal "hello-what-s-this-a-title", model.slug
  end

  def test_parameterization_handles_accents
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Café Résumé")
    assert_equal "cafe-resume", model.slug
  end

  # ============================================================================
  # Edge Case Handling
  # ============================================================================

  def test_nil_attribute_falls_back_to_id_based_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: nil)
    model.reload

    # Should have a valid slug (fallback to id-based number)
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_blank_attribute_falls_back_to_id_based_slug
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "   ")
    model.reload

    # Should have a valid slug (fallback to id-based number)
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_nonexistent_attribute_falls_back_to_id_based_slug
    TestModel.class_eval do
      generate_slug_based_on :nonexistent
    end

    model = TestModel.create!(title: "Test")

    # Should have a valid slug (fallback to id-based hex)
    refute_nil model.slug
    assert model.slug.match?(/\A[0-9a-f]+\z/)
  end
end
