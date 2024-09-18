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
    # By default all slugs will be a string computed from the record ID:
    # ```
    # generate_slug_based_on :id
    # ```
    #
    # but optionally, you can also specify to compute the slug as a number:
    # ```
    # generate_slug_based_on id: :number
    # ```
    #
    # or compute the slug based off any other attribute:
    # ```
    # generate_slug_based_on :name
    # ```

    DEFAULT_SLUG_GENERATION_STRATEGY = :compute_slug_as_string

    included do
      after_create :set_slug
      after_find :update_slug_if_nil
      validates :slug, uniqueness: true
    end

    class_methods do
      def generate_slug_based_on(strategy_method_name = DEFAULT_SLUG_GENERATION_STRATEGY, *args)
        define_method(:generate_slug_based_on) do
          [strategy_method_name, args]
        end
      end
    end

    def method_missing(missing_method, *args, &block)
      if missing_method.to_s == "slug" && !self.methods.include?(:slug)
        compute_slug
      else
        super
      end
    end

    def compute_slug
      method_name, args = determine_slug_generation_method
      return self.send(method_name, *args)
    end

    def compute_slug_as_string
      return (Digest::SHA2.hexdigest self.id.to_s).first(11)
    end

    def compute_slug_as_number
      generate_random_number_based_on_id_hex
    end

    def compute_slug_based_on_attribute(attribute_name)
      return compute_slug_as_string unless self.attributes.include?(attribute_name.to_s)

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

      return slug_candidate unless slug_persisted?

      # Collision resolution logic:

      count = 0

      while self.class.exists?(slug: slug_candidate)
        count += 1
        # slug_candidate = "#{base_slug}-#{count}"
        slug_candidate = "#{base_slug}-#{compute_slug_as_number}"
      end

      slug_candidate
    end

    def determine_slug_generation_method
      return [DEFAULT_SLUG_GENERATION_STRATEGY] unless respond_to?(:generate_slug_based_on)

      slug_generation_strategy = generate_slug_based_on.first
      strategy_attributes = generate_slug_based_on.second

      if !slug_generation_strategy.is_a?(Array) && !slug_generation_strategy.is_a?(Symbol)
        return [DEFAULT_SLUG_GENERATION_STRATEGY]
      end

      if slug_generation_strategy.is_a?(Symbol)
        if slug_generation_strategy == :id
          return [DEFAULT_SLUG_GENERATION_STRATEGY]
        else
          return [:compute_slug_based_on_attribute, slug_generation_strategy]
        end
      end

      if slug_generation_strategy.include?(:attribute)
        which_attribute = slug_generation_strategy.dig(:attribute)
        return [:compute_slug_based_on_attribute, which_attribute]

      elsif slug_generation_strategy.include?(:id)
        return_as = slug_generation_strategy.dig(:id)

        if return_as == :hex_string
          return [:compute_slug_as_string]
        elsif return_as == :number
          return [:compute_slug_as_number]
        else
          return [DEFAULT_SLUG_GENERATION_STRATEGY]
        end

      else
        return [DEFAULT_SLUG_GENERATION_STRATEGY]
      end
    end

    def slug_persisted?
      self.methods.include?(:slug) && self.attributes.include?("slug")
    end

    def set_slug
      return unless slug_persisted?

      self.slug = compute_slug if id_changed? || slug.blank?
      self.save
    end

    def update_slug_if_nil
      set_slug if slug_persisted? && self.slug.nil?
    end

  end
end
