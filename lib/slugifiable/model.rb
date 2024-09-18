module Slugifiable
  module Model
    extend ActiveSupport::Concern

    # This concern makes objects have a string slug based on their ID or another specified attribute
    #
    # To use, include this in any ActiveRecord model:
    # ```
    # include Slugifiable::Model
    # ```
    #
    # Optional: Specify a different slug generation method
    # slug_generation_method :get_numeric_slug
    # or
    # slug_generation_method :get_readable_slug_based_on_attribute, 'attribute_name'

    included do
      after_create :set_slug
      after_find :update_slug_if_nil
      validates :slug, uniqueness: true
    end

    class_methods do
      def slug_generation_method(method_name = :get_short_string_slug, *args)
        define_method(:slug_generation_method) do
          [method_name, args]
        end
      end
    end

    def method_missing(missing_method, *args, &block)
      if missing_method.to_s == "slug" && !self.methods.include?(:slug)
        get_short_string_slug
      else
        super
      end
    end

    def get_numeric_slug
      generate_random_number_based_on_id_hex
    end

    def get_short_string_slug
      return (Digest::SHA2.hexdigest self.id.to_s).first(11)
    end

    def get_readable_slug_based_on_attribute(attribute_name)
      base_slug = self.send(attribute_name)&.to_s&.strip&.parameterize
      base_slug = base_slug.presence || generate_random_number_based_on_id_hex

      unique_slug = generate_unique_slug(base_slug)
      unique_slug.presence || generate_random_number_based_on_id_hex
    end

    private

    def generate_random_number_based_on_id_hex
      ((Digest::SHA2.hexdigest(id.to_s)).hex % 1000000)
    end

    def generate_unique_slug(base_slug)
      slug_candidate = base_slug
      count = 0

      while self.class.exists?(slug: slug_candidate)
        count += 1
        # slug_candidate = "#{base_slug}-#{count}"
        slug_candidate = "#{base_slug}-#{get_short_string_slug}"
      end

      slug_candidate
    end

    def set_slug
      method_info = respond_to?(:slug_generation_method) ? slug_generation_method : [:get_short_string_slug]
      method_name, args = method_info
      self.slug = send(method_name, *args) if id_changed? || slug.blank?
      self.save
    end

    def update_slug_if_nil
      set_slug if self.methods.include?(:slug) && self.attributes.include?("slug") && self.slug.nil?
    end

  end
end
