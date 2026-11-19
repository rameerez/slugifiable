# frozen_string_literal: true

require "test_helper"

# The `max_length:` option — a slug built from free text is as long as the
# text, and some destinations have a limit (a URL segment an API validates,
# a subdomain). The cap applies to the parameterized base, in bytes, before
# the uniqueness suffix.
class Slugifiable::MaxLengthTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModel.class_eval do
      generate_slug_based_on :title, max_length: 20
    end
  end

  def teardown
    TestModel.class_eval do
      generate_slug_based_on :title
    end
  end

  def test_a_long_title_is_cut_to_the_cap
    model = TestModel.create!(title: "abcdefghij" * 5)

    assert_equal "abcdefghijabcdefghij", model.slug
  end

  def test_a_short_title_is_untouched
    assert_equal "short-name", TestModel.create!(title: "Short Name").slug
  end

  def test_the_cap_counts_bytes_after_transliteration
    model = TestModel.create!(title: "Æ" * 20) # 20 characters, 40 bytes once transliterated

    assert_equal "ae" * 10, model.slug
  end

  def test_a_cut_never_leaves_a_trailing_separator
    model = TestModel.create!(title: "nineteen characters and more") # byte 20 is the hyphen after "characters"

    assert_equal "nineteen-characters", model.slug
  end

  def test_the_uniqueness_suffix_is_appended_after_the_cap
    TestModel.create!(title: "abcdefghij" * 5)
    second = TestModel.create!(title: "abcdefghij" * 5)

    assert_match(/\Aabcdefghijabcdefghij-\d+\z/, second.slug)
  end

  def test_composes_with_except
    TestModel.class_eval do
      generate_slug_based_on :title, max_length: 20, except: %w[admin]
    end

    assert_match(/\Aadmin-\d+\z/, TestModel.create!(title: "Admin").slug)
  end

  def test_works_with_the_hash_attribute_syntax
    TestModel.class_eval do
      generate_slug_based_on attribute: :title, max_length: 5
    end

    assert_equal "abcde", TestModel.create!(title: "abcdefghij").slug
  end

  def test_an_invalid_cap_fails_at_class_definition_time
    [ 0, -1, "80", 12.5 ].each do |bad|
      error = assert_raises(ArgumentError) do
        TestModel.class_eval { generate_slug_based_on :title, max_length: bad }
      end
      assert_match(/max_length/, error.message)
    end
  end
end
