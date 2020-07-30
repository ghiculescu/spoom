# typed: true
# frozen_string_literal: true

module Spoom
  module Sorbet
    module Sigils
      extend T::Sig

      VALID_STRICTNESS = ["ignore", "false", "true", "strict", "strong", "__STDLIB_INTERNAL"].freeze
      SIGIL_REGEXP = /^#\s*typed\s*:\s*(\w*)\s*$/.freeze

      # returns the full sigil comment string for the passed strictness
      sig { params(strictness: String).returns(String) }
      def self.sigil_string(strictness)
        "# typed: #{strictness}"
      end

      # returns true if the passed string is a sigil with valid strictness (else false)
      sig { params(content: String).returns(T::Boolean) }
      def self.valid_strictness?(content)
        VALID_STRICTNESS.include?(strictness(content))
      end

      # returns the strictness of a sigil in the passed file content string (nil if no sigil)
      sig { params(content: String).returns(T.nilable(String)) }
      def self.strictness(content)
        SIGIL_REGEXP.match(content)&.[](1)
      end

      # returns a string which is the passed content but with the sigil updated to a new strictness
      sig { params(content: String, new_strictness: String).returns(String) }
      def self.update_sigil(content, new_strictness)
        content.sub(SIGIL_REGEXP, sigil_string(new_strictness))
      end
    end
  end
end
