# frozen_string_literal: true
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment

require "json"
# ^^^^^ function
#       ^^^^^^ string

# Counts the words it is given.
module Words
  # ^^ keyword
  #    ^^^^^ special
  class Counter
    #   ^^^^^^^ special
    attr_reader :name
    #           ^^^^^ constant

    MAX = 10
    # ^ special
    #     ^^ number

    def initialize(name, limit: MAX)
      # ^^^^^^^^^^ definition
      @name = name
      # ^^^ function
      @limit = limit
      @seen = Hash.new(0)
    end

    def add(words)
      words.each do |word|
        #        ^^ keyword
        next if word.empty?

        @seen[word] += 1
      end
      self
    end

    def report
      if @seen.empty?
        puts "nothing for #{@name}"
      elsif @seen.size > @limit
        # ^ keyword
        warn "too many: #{@seen.size}"
      else
        @seen.sort_by { |_, count| -count }.first(3)
      end
    rescue StandardError => e
      # ^^ keyword
      raise ArgumentError, e.message
    end

    def to_json(*args)
      { name: @name, total: @seen.values.sum, ratio: 1.5, ok: true, gone: nil }.to_json(*args)
      #                                              ^^^ number           ^^^ constant
      #                                                       ^^^^ constant
    end
  end
end
