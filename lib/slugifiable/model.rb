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
    DEFAULT_SLUG_STRING_LENGTH = 11
    DEFAULT_SLUG_NUMBER_LENGTH = 6

    included do
      after_create :set_slug
      after_find :update_slug_if_nil
      validates :slug, uniqueness: true
    end

    class_methods do
      def generate_slug_based_on(strategy, options = {})
        define_method(:generate_slug_based_on) do
          [strategy, options]
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
      strategy, options = determine_slug_generation_method

      length = options[:length] if options.is_a?(Hash) || nil

      if strategy == :compute_slug_based_on_attribute
        self.send(strategy, options)
      else
        self.send(strategy, length)
      end
    end

    def compute_slug_as_string(length = DEFAULT_SLUG_STRING_LENGTH)
      length ||= DEFAULT_SLUG_STRING_LENGTH
      (Digest::SHA2.hexdigest self.id.to_s).first(length)
    end

    def compute_slug_as_number(length = DEFAULT_SLUG_NUMBER_LENGTH)
      length ||= DEFAULT_SLUG_NUMBER_LENGTH
      generate_random_number_based_on_id_hex(length)
    end

    def compute_slug_based_on_attribute(attribute_name)
      return compute_slug_as_string unless self.attributes.include?(attribute_name.to_s)

      base_slug = self.send(attribute_name)&.to_s&.strip&.parameterize
      base_slug = base_slug.presence || generate_random_number_based_on_id_hex

      unique_slug = generate_unique_slug(base_slug)
      unique_slug.presence || generate_random_number_based_on_id_hex
    end

    private

    def generate_random_number_based_on_id_hex(length = DEFAULT_SLUG_NUMBER_LENGTH)
      length ||= DEFAULT_SLUG_NUMBER_LENGTH
      ((Digest::SHA2.hexdigest(id.to_s)).hex % (10 ** length))
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
      return [DEFAULT_SLUG_GENERATION_STRATEGY, {}] unless respond_to?(:generate_slug_based_on)

      strategy, options = generate_slug_based_on
      options.merge!(strategy) if strategy.is_a? Hash

      if strategy.is_a?(Symbol)
        if strategy == :id
          return [:compute_slug_as_string, options]
        else
          return [:compute_slug_based_on_attribute, strategy]
        end
      end

      if strategy.is_a?(Hash)
        if strategy.key?(:id)
          case strategy[:id]
          when :hex_string
            return [:compute_slug_as_string, options]
          when :number
            return [:compute_slug_as_number, options]
          else
            return [DEFAULT_SLUG_GENERATION_STRATEGY, options]
          end
        elsif strategy.key?(:attribute)
          return [:compute_slug_based_on_attribute, strategy[:attribute], options]
        end
      end

      [DEFAULT_SLUG_GENERATION_STRATEGY, options]
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
