-- This file contains code adapted from the bufferline.nvim project:
-- https://github.com/akinsho/bufferline.nvim/blob/main/lua/bufferline/lazy.lua
--
-- Modifications made in this file:
-- -- copy pastad
local lazy = {}

--- Require on index.
---
--- Will only require the module after the first index of a module.
--- Only works for modules that export a table.
---@param require_path string
---@return table
lazy.require = function(require_path)
	return setmetatable({}, {
		__index = function(_, key)
			return require(require_path)[key]
		end,
		__newindex = function(_, key, value)
			require(require_path)[key] = value
		end,
	})
end

return lazy
