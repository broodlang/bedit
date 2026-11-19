#!/usr/bin/env julia
# the greeter
# ^^^^^^^^^^^ comment
module Greet
# ^^^^ keyword
#      ^^^^^ special

using LinearAlgebra
import Base: show

export greet

#= a block
comment =#
const MAX = 0x10
#           ^^^^ number

abstract type Shape end
#             ^^^^^ special

struct Point{T<:Real} <: Shape
    #  ^^^^^ special
    x::T
    y::T
end
# ^ keyword

mutable struct Greeter
    # ^ keyword
    #          ^^^^^^^ special
    name::String
end

"""
    greet(who)

Say hello.
"""
function greet(who::String, loud::Bool=false)
    #    ^^^^^ definition
    #               ^^^^^^ special
    if isempty(who)
        return nothing
        #      ^^^^^^^ constant
    elseif loud
        println(uppercase("hi $who and $(length(who))"))
        # ^^^^^ function  ^^^^ string    ^^^^^^ function
        #                      ^^^ plain
    else
        Base.print(stdout, 'c', 1.5, true)
        #    ^^^^^ function     ^^^ number
        #                  ^^^ string
        #                            ^^^^ constant
    end
    for each in ["a", "b"]
        #        ^^^ string
        continue
        # ^^^^^^ keyword
    end
    while false
        break
    end
    result = let value = 1
        value * 2
    end
    doubled = map(x -> x * 2, [1, 2])
    total = sum(1:10) do index
        #             ^^ keyword
        index^2
    end
    try
        work(:symbol)
        #    ^^^^^^^ constant
    catch err
        rethrow(err)
    finally
        cleanup()
    end
    @assert MAX > 0
    # ^^^^^ special
    return Point(1.0, 2.0)
    #      ^^^^^ function
end

area(point::Point) = point.x * point.y
# ^^ definition

macro twice(expr)
    # ^^^^^ definition
    quote
        $(esc(expr))
        $(esc(expr))
    end
end

end # module