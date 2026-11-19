#!/usr/bin/env lua
-- ^^^^^^^^^^^^^^^ comment
-- the greeter
-- ^^^^^^^^^^^ comment
local M = {}

--[[ a block
comment ]]
local MAX = 0x10
--          ^^^^ number

local Greeter = {
  name = "world",
  --     ^^^^^^^ string
  weight = 1.5,
  --       ^^^ number
}

function M.greet(who, loud)
  --       ^^^^^ definition
  if who == nil then
    --      ^^^ constant
    --          ^^^^ keyword
    return nil
  elseif loud then
    print(string.upper("hi " .. who))
    -- ^^ function
    --           ^^^^^ function
  else
    io.write([[raw
text]])
  end
  -- <- keyword
  for index = 1, MAX do
    M.log(index, true)
    --           ^^^^ constant
  end
  for _, each in ipairs({ "a", "b" }) do
    while false do
      break
      -- ^^ keyword
    end
  end
  repeat
    local done = true
  until done
  -- ^^ keyword
  local callback = function(value)
    return value * 2
  end
  return self:shout(who)
  --     ^^^^ keyword
  --          ^^^^^ function
end

function Greeter:shout(text)
  --             ^^^^^ definition
  return text:upper()
  --          ^^^^^ function
end

local function helper(...)
  --           ^^^^^^ definition
  --                  ^^^ constant
  local options = {
    flag = false,
  }
  do
    goto continue
  end
  ::continue::
  return select("#", ...)
end

return M