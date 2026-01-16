require "test_helper"

class Slugifiable::AdditionalModelTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModelWithoutSlug.delete_all

    TestModel.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)

      remove_method(:custom_title) if method_defined?(:custom_title)
      remove_method(:private_title) if private_method_defined?(:private_title)
      remove_method(:protected_title) if protected_method_defined?(:protected_title)
    end

    TestModelWithoutSlug.class_eval do
      remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)
    end
  end

  # --- ID-based strategies (hex string) ---
  def test_id_hex_string_default_length
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  def test_id_hex_string_custom_length
    custom_length = 8
    TestModel.class_eval do
      generate_slug_based_on id: :hex_string, length: 8
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, custom_length]
    assert_equal expected, model.slug
  end

  # --- ID-based strategies (number) ---
  def test_id_number_default_length
    TestModel.class_eval do
      generate_slug_based_on id: :number
    end

    model = TestModel.create!(title: "A")
    expected_num = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    assert_equal expected_num, model.slug
  end

  def test_id_number_custom_length
    custom_length = 4
    TestModel.class_eval do
      generate_slug_based_on id: :number, length: custom_length
    end

    model = TestModel.create!(title: "A")
    expected_num = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** custom_length)).to_s
    assert_equal expected_num, model.slug
  end

  # --- Unknown strategy handling ---
  def test_unknown_id_strategy_falls_back_to_default
    TestModel.class_eval do
      generate_slug_based_on id: :unknown
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  def test_unknown_attribute_symbol_falls_back_to_id_strategy
    TestModel.class_eval do
      generate_slug_based_on :does_not_exist
    end

    model = TestModel.create!(title: "A")
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  # --- Attribute hash with options (length is ignored for attribute strategy) ---
  def test_attribute_hash_with_nil_value_falls_back_to_random_number
    TestModel.class_eval do
      generate_slug_based_on attribute: :title, length: 25
    end

    model = TestModel.create!(title: nil)
    expected = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH)).to_s
    model.reload
    assert_equal expected, model.slug
  end

  # --- method_missing behavior ---
  def test_method_missing_for_unknown_method_raises
    model = TestModel.create!(title: "X")
    assert_raises(NoMethodError) { model.send(:non_existent_method_abc) }
  end

  def test_method_missing_slug_without_slug_column_uses_default
    model = TestModelWithoutSlug.create!(title: "X")
    # Default is to compute hex string based on id
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, model.slug
  end

  # --- Uniqueness validation ---
  def test_slug_uniqueness_validation
    TestModel.create!(title: "A", slug: "duplicate")
    assert_raises(ActiveRecord::RecordInvalid) do
      TestModel.create!(title: "B", slug: "duplicate")
    end
  end

  # --- Parameterization robustness ---
  def test_attribute_with_whitespace_and_symbols_parameterizes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "  Hello, World!  --  A&B  ")
    assert_equal "hello-world-a-b", model.slug
  end

  # --- update_slug_if_nil no-op for models without slug column ---
  def test_update_slug_if_nil_noop_when_no_slug_column
    model = TestModelWithoutSlug.new(title: "X")
    # Should not raise
    model.send(:update_slug_if_nil)
  end

  # --- Internal nil length defaults ---
  def test_compute_slug_as_string_nil_length_defaults
    model = TestModel.create!(title: "X")
    slug = model.send(:compute_slug_as_string, nil)
    expected = Digest::SHA2.hexdigest(model.id.to_s)[0, Slugifiable::Model::DEFAULT_SLUG_STRING_LENGTH]
    assert_equal expected, slug
  end

  def test_compute_slug_as_number_nil_length_defaults
    model = TestModel.create!(title: "X")
    slug_num = model.send(:compute_slug_as_number, nil)
    expected_num = ((Digest::SHA2.hexdigest(model.id.to_s)).hex % (10 ** Slugifiable::Model::DEFAULT_SLUG_NUMBER_LENGTH))
    assert_equal expected_num, slug_num
  end

  # --- International/UTF-8 parameterization ---
  def test_attribute_with_accents_parameterizes
    TestModel.class_eval do
      generate_slug_based_on :title
    end

    model = TestModel.create!(title: "Café con Leche & Crème Brûlée")
    assert_equal "cafe-con-leche-creme-brulee", model.slug
  end

  # --- Models without slug column can share same computed slug ---
  def test_models_without_slug_column_can_share_same_slug
    TestModelWithoutSlug.class_eval do
      generate_slug_based_on :title
    end

    m1 = TestModelWithoutSlug.create!(title: "Same Title")
    m2 = TestModelWithoutSlug.create!(title: "Same Title")

    assert_equal m1.slug, m2.slug
  end
end