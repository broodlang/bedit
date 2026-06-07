# A small Ruby sample for exercising ruby-mode (tree-sitter).
require "json"

class Greeter
  GREETING = "hello"          # a constant + a string

  def initialize(name)
    @name = name              # an instance variable
    @count = 0
  end

  def greet(loud: false)
    msg = "#{GREETING}, #{@name}!"
    msg = msg.upcase if loud
    @count += 1
    puts msg
    msg
  end
end

g = Greeter.new("world")
3.times { g.greet(loud: true) }
