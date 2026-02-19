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

    # SHA256 produces 64 hex characters
    MAX_HEX_STRING_LENGTH = 64
    # 10^18 fits safely in a 64-bit integer
    MAX_NUMBER_LENGTH = 18

    # Maximum number of attempts to generate a unique slug
    # before falling back to timestamp-based suffix
    MAX_SLUG_GENERATION_ATTEMPTS = 10

    included do
      around_create :retry_create_on_slug_unique_violation
      after_create :set_slug
      after_find :update_slug_if_nil
      validates :slug, uniqueness: true
    end

    class_methods do
      def generate_slug_based_on(strategy, options = {})
        # Remove previous definition if it exists to avoid warnings
        remove_method(:generate_slug_based_on) if method_defined?(:generate_slug_based_on)

        # Define the method that returns the strategy
        define_method(:generate_slug_based_on) do
          [strategy, options]
        end
      end
    end

    def method_missing(missing_method, *args, &block)
      if missing_method.to_s == "slug" && !has_slug_method?
        compute_slug
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      method_name.to_s == "slug" && !has_slug_method? || super
    end

    def compute_slug
      strategy, options = determine_slug_generation_method

      length = options[:length] if options.is_a?(Hash)

      if strategy == :compute_slug_based_on_attribute
        self.send(strategy, options)
      else
        self.send(strategy, length)
      end
    end

    def compute_slug_as_string(length = DEFAULT_SLUG_STRING_LENGTH)
      length = normalize_length(length, DEFAULT_SLUG_STRING_LENGTH, MAX_HEX_STRING_LENGTH)
      (Digest::SHA2.hexdigest self.id.to_s).first(length)
    end

    def compute_slug_as_number(length = DEFAULT_SLUG_NUMBER_LENGTH)
      length = normalize_length(length, DEFAULT_SLUG_NUMBER_LENGTH, MAX_NUMBER_LENGTH)
      generate_random_number_based_on_id_hex(length)
    end

    def compute_slug_based_on_attribute(attribute_name)
      # This method generates a slug from either:
      # 1. A database column (e.g. generate_slug_based_on :title)
      # 2. An instance method (e.g. generate_slug_based_on :title_with_location)
      #
      # Priority:
      # - Database columns take precedence over methods with the same name
      # - Falls back to methods if no matching column exists
      # - Falls back to ID-based slug if neither exists
      #
      # Flow:
      # 1. Check if source exists (DB column first, then method)
      # 2. Get raw value
      # 3. Parameterize (convert "My Title" -> "my-title")
      # 4. Ensure uniqueness
      # 5. Fallback to random number if anything fails

      # First check if we can get a value from the database
      has_attribute = self.attributes.include?(attribute_name.to_s)

      # Only check for methods if no DB attribute exists
      # We check all method types to be thorough
      responds_to_method = !has_attribute && (
        self.class.method_defined?(attribute_name) ||
        self.class.private_method_defined?(attribute_name) ||
        self.class.protected_method_defined?(attribute_name)
      )

      # If we can't get a value from either source, fallback to using the record's ID
      return compute_slug_as_string unless has_attribute || responds_to_method

      # Get and clean the raw value (e.g. "  My Title  " -> "My Title")
      # Works for both DB attributes and methods thanks to Ruby's send
      raw_value = self.send(attribute_name)
      return generate_random_number_based_on_id_hex if raw_value.nil?

      # Convert to URL-friendly format
      # e.g. "My Title" -> "my-title"
      base_slug = raw_value.to_s.strip.parameterize
      return generate_random_number_based_on_id_hex if base_slug.blank?

      # Handle duplicate slugs by adding a random suffix if needed
      # e.g. "my-title" -> "my-title-123456"
      unique_slug = generate_unique_slug(base_slug)
      unique_slug.presence || generate_random_number_based_on_id_hex
    end

    private

    # Returns the raw parameterized slug without uniqueness handling.
    # Used by the exhaustion fallback to avoid double-suffixing.
    #
    # Fallback behavior matches compute_slug_based_on_attribute: uses
    # generate_random_number_based_on_id_hex for nil/blank/missing attributes.
    def compute_base_slug
      strategy, options = determine_slug_generation_method

      case strategy
      when :compute_slug_based_on_attribute
        attribute_name = options
        has_attribute = self.attributes.include?(attribute_name.to_s)
        responds_to_method = !has_attribute && (
          self.class.method_defined?(attribute_name) ||
          self.class.private_method_defined?(attribute_name) ||
          self.class.protected_method_defined?(attribute_name)
        )

        return generate_random_number_based_on_id_hex unless has_attribute || responds_to_method

        raw_value = self.send(attribute_name)
        return generate_random_number_based_on_id_hex if raw_value.nil?

        base_slug = raw_value.to_s.strip.parameterize
        base_slug.presence || generate_random_number_based_on_id_hex
      else
        # For ID-based strategies, return the deterministic hash
        compute_slug
      end
    end

    def normalize_length(length, default, max)
      length = length.to_i
      return default if length <= 0
      [length, max].min
    end

    def generate_random_number_based_on_id_hex(length = DEFAULT_SLUG_NUMBER_LENGTH)
      length = normalize_length(length, DEFAULT_SLUG_NUMBER_LENGTH, MAX_NUMBER_LENGTH)
      ((Digest::SHA2.hexdigest(id.to_s)).hex % (10 ** length))
    end

    def generate_unique_slug(base_slug)
      slug_candidate = base_slug

      return slug_candidate unless slug_persisted?

      # Collision resolution logic:
      # Try up to MAX_SLUG_GENERATION_ATTEMPTS times with random suffixes
      # This prevents infinite loops while still giving us good odds
      # of finding a unique slug
      attempts = 0

      while self.class.exists?(slug: slug_candidate) && attempts < MAX_SLUG_GENERATION_ATTEMPTS
        attempts += 1
        # Use SecureRandom for truly random suffixes during collision resolution
        # This ensures each attempt tries a different suffix
        random_suffix = SecureRandom.random_number(10 ** DEFAULT_SLUG_NUMBER_LENGTH)
        slug_candidate = "#{base_slug}-#{random_suffix}"
      end

      # If we couldn't find a unique slug after MAX_SLUG_GENERATION_ATTEMPTS,
      # append timestamp + random to ensure uniqueness
      if attempts == MAX_SLUG_GENERATION_ATTEMPTS
        slug_candidate = "#{base_slug}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
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
          return [:compute_slug_based_on_attribute, strategy[:attribute]]
        end
      end

      [DEFAULT_SLUG_GENERATION_STRATEGY, options]
    end

    def slug_persisted?
      has_slug_method? && self.attributes.include?("slug")
    end

    def has_slug_method?
      # Check if slug method exists from ActiveRecord (not from method_missing)
      self.class.method_defined?(:slug) || self.class.private_method_defined?(:slug)
    end

    def set_slug
      return unless slug_persisted?

      set_slug_with_retry
    end

    def set_slug_with_retry
      return unless slug.blank?

      # For attribute-based slugs, compute_slug -> generate_unique_slug already
      # handles uniqueness with random suffixes on each call.
      # For ID-based slugs, collisions are impossible since two records can't
      # have the same ID, so retries would never be triggered in practice.
      #
      # Each attempt runs in a savepoint so a unique-constraint violation does
      # not abort the outer transaction in PostgreSQL.
      #
      # Fallback when all retries exhausted: use timestamp suffix for guaranteed uniqueness.
      # Uses compute_base_slug to avoid double-suffixing (compute_slug includes random suffixes).
      on_exhaustion = -> {
        base_slug = compute_base_slug
        self.slug = "#{base_slug}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
        self.class.transaction(requires_new: true) { self.save }
      }

      with_slug_retry(-> { self.slug = nil }, on_exhaustion: on_exhaustion) do
        self.slug = compute_slug
        self.class.transaction(requires_new: true) { self.save }
      end
    end

    # Detects if a RecordNotUnique error is related to the slug column.
    #
    # Uses patterns that handle common error message formats without false positives:
    # - SQLite: "UNIQUE constraint failed: table.slug" -> matches \bslug\b (period is word boundary)
    # - PostgreSQL: "Key (slug)=(value)" -> matches \bslug\b (parens are word boundaries)
    # - MySQL/PG index: "index_posts_on_slug" -> matches _on_slug\b
    #
    # IMPORTANT: We use _on_slug\b specifically to avoid false positives on columns
    # like canonical_slug, parent_slug, original_slug, etc. The pattern _slug alone
    # would incorrectly match those.
    #
    # LIMITATION: Custom index names like `uq_slug_col`, `slug_idx`, or `posts_slug_unique`
    # won't match. This results in a false negative (exception bubbles up), which is the
    # safe outcome — no data corruption, just no automatic retry for that schema.
    def slug_unique_violation?(error)
      message = error.message.to_s.downcase
      cause_message = error.cause&.message.to_s.downcase
      # \bslug\b matches "slug" as standalone word (SQLite ".slug", PostgreSQL "(slug)")
      # _on_slug\b matches Rails index naming convention "index_*_on_slug"
      pattern = /\bslug\b|_on_slug\b/
      [message, cause_message].any? { |m| m.match?(pattern) }
    end

    # Handle INSERT-time slug races for models that persist slugs at create-time
    # (e.g., NOT NULL slug columns with before_validation slug generation).
    #
    # NOTE: This calls `yield` multiple times (once per attempt) via `retry`.
    # This relies on Rails `around_create` yielding a re-invocable Proc, which
    # is undocumented but has worked consistently in Rails 6-8. The behavior
    # stems from Rails building callback chains as re-callable Procs/lambdas.
    # See: activerecord/lib/active_record/callbacks.rb and
    # activesupport/lib/active_support/callbacks.rb in Rails source.
    # The test suite includes `around_create_state_machine_test.rb` which
    # validates this behavior continues to work on Rails upgrades.
    #
    # Unlike set_slug_with_retry (which falls back to timestamp suffix on exhaustion),
    # this method raises after MAX_SLUG_GENERATION_ATTEMPTS because INSERT-time
    # collisions requiring 10+ retries indicate a systemic issue that warrants attention.
    def retry_create_on_slug_unique_violation
      return yield unless slug_persisted?
      # Skip savepoint overhead for nullable slug columns — INSERT-time slug
      # collisions are impossible when slug is NULL at INSERT time.
      return yield unless slug_column_not_null?

      # Each attempt runs in a savepoint so a unique-constraint violation does
      # not abort the outer transaction in PostgreSQL.
      with_slug_retry(
        -> { self.slug = compute_slug_for_retry },
        retry_if: ->(_error) { !persisted? }
      ) do
        # Recompute slug before retry because create-callback retries do not
        # re-run validation callbacks.
        self.class.transaction(requires_new: true) { yield }
      end
    end

    def slug_column_not_null?
      return @slug_column_not_null if defined?(@slug_column_not_null)
      @slug_column_not_null = self.class.columns_hash["slug"]&.null == false
    end

    # Generates a slug for retry attempts.
    # For attribute-based strategies, compute_slug calls generate_unique_slug which
    # adds random suffixes on each call, ensuring retry attempts try different values.
    #
    # NOTE: ID-based slug collisions are impossible (two records can't share the same ID),
    # so this method is only meaningful for attribute-based strategies where concurrent
    # inserts can race to claim the same slug.
    def compute_slug_for_retry
      compute_slug
    end

    # Shared retry logic for slug unique constraint violations.
    # Makes up to MAX_SLUG_GENERATION_ATTEMPTS total attempts (1 initial + N-1 retries),
    # calling pre_retry_action before each retry to regenerate the slug.
    #
    # When retries are exhausted, calls the optional on_exhaustion proc if provided,
    # otherwise re-raises the exception. The on_exhaustion proc can apply a timestamp
    # fallback to maintain parity with generate_unique_slug's lenient behavior.
    def with_slug_retry(pre_retry_action, retry_if: ->(_error) { true }, on_exhaustion: nil)
      attempts = 0

      begin
        yield
      rescue ActiveRecord::RecordNotUnique => e
        raise unless slug_unique_violation?(e)
        raise unless retry_if.call(e)

        attempts += 1
        if attempts >= MAX_SLUG_GENERATION_ATTEMPTS
          if on_exhaustion
            on_exhaustion.call
          else
            raise
          end
        else
          pre_retry_action.call
          retry
        end
      end
    end

    def update_slug_if_nil
      set_slug if slug_persisted? && self.slug.nil?
    end

  end
end
