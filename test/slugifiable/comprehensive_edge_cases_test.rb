require "test_helper"

# Comprehensive Edge Cases Test Suite for Slugifiable
#
# This test suite covers:
# - Unicode/International characters (emojis, CJK, RTL, diacritics)
# - Very long strings and boundary conditions
# - Special characters and HTML/XSS patterns
# - Empty, nil, whitespace-only inputs
# - Numeric inputs and type coercion
# - Length parameter edge cases (0, negative, very large)
# - Reserved words and URL-unsafe characters

class Slugifiable::ComprehensiveEdgeCasesTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
      remove_method(:custom_slug_method) if method_defined?(:custom_slug_method)
    end
  end

  # ============================================================================
  # Unicode and International Characters
  # ============================================================================

  def test_unicode_emoji_parameterization
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello World")
    # Emojis may be stripped by parameterize depending on Rails version
    # The important thing is that a valid slug is generated
    refute_nil model.slug
    assert model.slug.length > 0
    # Should contain the non-emoji words
    assert model.slug.include?("hello")
    assert model.slug.include?("world")
  end

  def test_unicode_cjk_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # Chinese characters
    model = TestModel.create!(title: "")
    # CJK characters are typically stripped by parameterize in default Ruby/Rails
    # Result depends on I18n transliteration settings
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_unicode_japanese_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "")
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_unicode_arabic_rtl_text
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "مرحبا بالعالم")
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_unicode_cyrillic_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Привет мир")
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_unicode_accented_european_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Crème Brûlée Résumé Naïve Café")
    assert_equal "creme-brulee-resume-naive-cafe", model.slug
  end

  def test_unicode_german_umlauts
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Größe Über Öffentlich Ärger")
    # Default parameterize should handle umlauts
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_unicode_mixed_scripts
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello 世界 مرحبا Привет")
    refute_nil model.slug
  end

  # ============================================================================
  # Very Long Strings and Boundary Conditions
  # ============================================================================

  def test_very_long_title_parameterization
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    long_title = "a" * 10_000
    model = TestModel.create!(title: long_title)

    # Parameterize should handle long strings without error
    refute_nil model.slug
    assert_equal "a" * 10_000, model.slug
  end

  def test_very_long_title_with_spaces
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    # 1000 words
    long_title = (["word"] * 1000).join(" ")
    model = TestModel.create!(title: long_title)

    refute_nil model.slug
    assert model.slug.include?("word")
  end

  def test_single_character_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "A")
    assert_equal "a", model.slug
  end

  def test_title_with_only_numbers
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "123456789")
    assert_equal "123456789", model.slug
  end

  def test_title_with_mixed_numbers_and_letters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Product 123 Version 4.5.6")
    assert_equal "product-123-version-4-5-6", model.slug
  end

  # ============================================================================
  # Special Characters and HTML/XSS Patterns
  # ============================================================================

  def test_html_tags_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "<script>alert('xss')</script>Hello")
    # HTML should be stripped/escaped by parameterize
    refute_includes model.slug, "<"
    refute_includes model.slug, ">"
    assert model.slug.include?("hello")
  end

  def test_sql_injection_patterns_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Robert'); DROP TABLE users;--")
    # Should be safely parameterized
    refute_nil model.slug
    refute_includes model.slug, "'"
    refute_includes model.slug, ";"
  end

  def test_url_special_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Test?query=value&foo=bar#anchor")
    refute_includes model.slug, "?"
    refute_includes model.slug, "&"
    refute_includes model.slug, "#"
    refute_includes model.slug, "="
  end

  def test_forward_and_back_slashes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Path/To\\Something")
    refute_includes model.slug, "/"
    refute_includes model.slug, "\\"
  end

  def test_percent_encoding_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "100% Pure %20 Encoded")
    refute_includes model.slug, "%"
  end

  def test_newlines_and_tabs_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Line1\nLine2\tTabbed")
    refute_includes model.slug, "\n"
    refute_includes model.slug, "\t"
    assert model.slug.include?("line1")
  end

  def test_carriage_return_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Line1\r\nLine2")
    refute_includes model.slug, "\r"
    refute_includes model.slug, "\n"
  end

  def test_null_byte_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello\x00World")
    refute_includes model.slug, "\x00"
  end

  # ============================================================================
  # Empty, Nil, Whitespace-Only Inputs
  # ============================================================================

  def test_nil_title_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: nil)
    model.reload

    # Should fall back to id-based slug
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_empty_string_title_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "")
    model.reload

    # Should fall back to id-based slug
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_whitespace_only_title_fallback
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "   \t\n   ")
    model.reload

    # Should fall back to id-based slug (parameterize strips to blank)
    refute_nil model.slug
    assert model.slug.length > 0
  end

  def test_title_with_only_special_characters
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "!@#$%^&*()")
    model.reload

    # All special chars stripped = blank = fallback to id-based slug
    refute_nil model.slug
    assert model.slug.length > 0
  end

  # ============================================================================
  # Numeric Inputs and Type Coercion
  # ============================================================================

  def test_method_returning_integer
    TestModel.class_eval do
      generate_slug_based_on :custom_slug_method

      def custom_slug_method
        12345
      end
    end

    model = TestModel.create!(title: "ignored")
    assert_equal "12345", model.slug
  end

  def test_method_returning_float
    TestModel.class_eval do
      generate_slug_based_on :custom_slug_method

      def custom_slug_method
        123.456
      end
    end

    model = TestModel.create!(title: "ignored")
    # Float.to_s then parameterized
    assert_equal "123-456", model.slug
  end

  def test_method_returning_boolean
    TestModel.class_eval do
      generate_slug_based_on :custom_slug_method

      def custom_slug_method
        true
      end
    end

    model = TestModel.create!(title: "ignored")
    assert_equal "true", model.slug
  end

  def test_method_returning_array
    TestModel.class_eval do
      generate_slug_based_on :custom_slug_method

      def custom_slug_method
        ["hello", "world"]
      end
    end

    model = TestModel.create!(title: "ignored")
    # Array.to_s = '["hello", "world"]' then parameterized
    refute_nil model.slug
    assert model.slug.include?("hello")
    assert model.slug.include?("world")
  end

  def test_method_returning_hash
    TestModel.class_eval do
      generate_slug_based_on :custom_slug_method

      def custom_slug_method
        {key: "value"}
      end
    end

    model = TestModel.create!(title: "ignored")
    refute_nil model.slug
  end

  # ============================================================================
  # Length Parameter Edge Cases
  # ============================================================================

  def test_hex_string_with_length_one
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 1
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, 1]
    assert_equal expected, model.slug
    assert_equal 1, model.slug.length
  end

  def test_hex_string_with_max_length_64
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 64
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, 64]
    assert_equal expected, model.slug
    assert_equal 64, model.slug.length
  end

  def test_hex_string_with_length_exceeding_64
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 100
    end

    model = TestModel.create!(title: "A")
    # Should cap at 64 (SHA256 hex digest length)
    assert model.slug.length <= 64
  end

  def test_number_with_length_one
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: 1
    end

    model = TestModel.create!(title: "A")
    assert model.slug.to_i < 10, "Single digit number slug expected"
  end

  def test_number_with_very_large_length
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: 20
    end

    model = TestModel.create!(title: "A")
    refute_nil model.slug
  end

  # ============================================================================
  # Reserved Words and URL Patterns
  # ============================================================================

  def test_slug_with_reserved_word_admin
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "admin")
    assert_equal "admin", model.slug
  end

  def test_slug_with_reserved_word_api
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "api")
    assert_equal "api", model.slug
  end

  def test_slug_that_looks_like_id
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "123")
    assert_equal "123", model.slug
  end

  def test_slug_with_new_keyword
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "new")
    assert_equal "new", model.slug
  end

  def test_slug_with_edit_keyword
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "edit")
    assert_equal "edit", model.slug
  end

  # ============================================================================
  # Consecutive Dashes and Edge Formatting
  # ============================================================================

  def test_multiple_consecutive_spaces
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello     World")
    assert_equal "hello-world", model.slug
  end

  def test_multiple_consecutive_dashes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Hello---World")
    # parameterize typically collapses multiple dashes
    assert_equal "hello-world", model.slug
  end

  def test_leading_and_trailing_dashes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "---Hello World---")
    # Leading/trailing dashes should be stripped
    assert_equal "hello-world", model.slug
  end

  def test_leading_and_trailing_spaces
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "   Hello World   ")
    assert_equal "hello-world", model.slug
  end

  # ============================================================================
  # Case Sensitivity
  # ============================================================================

  def test_uppercase_to_lowercase_conversion
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "HELLO WORLD")
    assert_equal "hello-world", model.slug
  end

  def test_mixed_case_conversion
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "HeLLo WoRLD")
    assert_equal "hello-world", model.slug
  end

  def test_camelcase_preservation
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "HelloWorld")
    assert_equal "helloworld", model.slug
  end

  # ============================================================================
  # Underscore vs Dash Handling
  # ============================================================================

  def test_underscores_in_title
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "hello_world_test")
    # Rails 7+ parameterize preserves underscores by default
    # This tests the actual behavior
    assert_equal "hello_world_test", model.slug
  end

  def test_mixed_underscores_and_spaces
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "hello_world and test_value")
    # Rails 7+ parameterize: spaces become dashes, underscores preserved
    assert_equal "hello_world-and-test_value", model.slug
  end

  def test_underscores_converted_with_separator_option
    # This test documents that if someone wants underscores converted,
    # they would need to customize the slug generation method
    # The gem uses .parameterize which preserves underscores in Rails 7+
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "has_underscores")
    # Underscores are preserved with default parameterize
    refute_nil model.slug
    assert model.slug.include?("has")
  end
end
