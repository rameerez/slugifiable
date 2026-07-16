# frozen_string_literal: true

require "test_helper"

# The `except:` option — reserved slugs (route segments and friends): a
# record named "Create" must never mint the slug "create" when the host app
# routes /things/create next to /things/:slug. Reserved words are treated
# exactly like collisions: the candidate gets a random numeric suffix.
class Slugifiable::ReservedSlugsTest < Minitest::Test
  def setup
    TestModel.delete_all
    TestModel.class_eval do
      generate_slug_based_on :title, except: %w[create admin new]
    end
  end

  def teardown
    TestModel.class_eval do
      generate_slug_based_on :title
    end
  end

  def test_reserved_word_gets_suffixed_instead_of_minted
    model = TestModel.create!(title: "Create")

    refute_equal "create", model.slug
    assert_match(/\Acreate-\d+\z/, model.slug, "reserved base falls into the collision-suffix path")
  end

  def test_reserved_matching_is_parameterized_and_case_insensitive
    TestModel.class_eval do
      generate_slug_based_on :title, except: [ "Admin", :new ]
    end

    admin = TestModel.create!(title: "ADMIN")
    fresh = TestModel.create!(title: "New")

    refute_equal "admin", admin.slug
    refute_equal "new", fresh.slug
  end

  def test_non_reserved_titles_are_untouched
    model = TestModel.create!(title: "Perfectly Normal Name")

    assert_equal "perfectly-normal-name", model.slug
  end

  def test_reserved_check_composes_with_real_collisions
    first = TestModel.create!(title: "Duplicate")
    second = TestModel.create!(title: "Duplicate")

    assert_equal "duplicate", first.slug
    assert_match(/\Aduplicate-\d+\z/, second.slug)
  end

  def test_except_accepts_a_single_string
    TestModel.class_eval do
      generate_slug_based_on :title, except: "create"
    end

    model = TestModel.create!(title: "Create")
    refute_equal "create", model.slug
  end
end
