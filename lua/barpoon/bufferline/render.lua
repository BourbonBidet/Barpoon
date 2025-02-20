-- This file contains code adapted from bufferline.nvim:
-- https://github.com/akinsho/bufferline.nvim/blob/main/lua/bufferline/ui.lua
--
-- The original project is licensed under the GNU General Public license:
-- Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
--
-- Modifications made in this file:
-- -- Allow barpoon to modify individual tabs with different button icons

local lazy = require("barpoon.lazy")
local config = lazy.require("barpoon.config") ---@module "barpoon.config"
local state = lazy.require("barpoon.state") ---@module "barpoon.state"
local bl_config = lazy.require("bufferline.config") ---@module "bufferline.config"
local bl_highlights = lazy.require("bufferline.highlights") ---@module "bufferline.highlights"
local bl_duplicates = lazy.require("bufferline.duplicates") ---@module "bufferline.duplicates"
local bl_diagnostics = lazy.require("bufferline.diagnostics") ---@module "bufferline.diagnostics"
local bl_utils = lazy.require("bufferline.utils") ---@module "bufferline.utils"
local bl_numbers = lazy.require("bufferline.numbers") ---@module "bufferline.numbers"
local bl_sorter = lazy.require("bufferline.sorters") ---@module "bufferline.sorters"
local bl_state = lazy.require("bufferline.state") ---@module "bufferline.state"
local bl_ui = lazy.require("bufferline.ui") ---@module "bufferline.ui"
local bl_pick = lazy.require("bufferline.pick") ---@module "bufferline.pick"
local bl_constants = lazy.require("bufferline.constants") ---@module "bufferline.constants"
local bl_buffers = lazy.require("bufferline.buffers") ---@module "bufferline.buffers"
local groups = lazy.require("bufferline.groups") ---@module "bufferline.groups"

local strwidth = vim.api.nvim_strwidth

local bufferline_ui = {}
local sep_names = bl_constants.sep_names
local sep_chars = bl_constants.sep_chars

local Context = {}

---@param ctx bufferline.RenderContext
---@return bufferline.RenderContext
function Context:new(ctx)
	assert(ctx.tab, "A tab view entity is required to create a context")
	self.tab = ctx.tab
	self.__index = self
	return setmetatable(ctx, self)
end

local bl_components = {
	id = {
		diagnostics = "diagnostics",
		name = "name",
		icon = "icon",
		number = "number",
		groups = "groups",
		duplicates = "duplicates",
		close = "close",
		modified = "modified",
		pick = "pick",
	},
}

function bufferline_ui.update()
	bl_ui.refresh()
end

local function tab_click_handler(id)
	return bl_ui.make_clickable("handle_click", id, { attr = { global = true } })
end

local function set_id(component, id)
	if component then
		component.attr = component.attr or {}
		component.attr.__id = id
	end
	return component
end

local function get_icon(buffer, hl_defs)
	local icon = buffer.icon
	local original_hl = buffer.icon_highlight

	if not icon or icon == "" then
		return
	end
	if not original_hl or original_hl == "" then
		return { text = icon }
	end

	local icon_hl = bl_highlights.set_icon_highlight(buffer:visibility(), hl_defs, original_hl)
	return { text = icon, highlight = icon_hl, attr = { text = "%*" } }
end

local function add_icon(context)
	local element = context.tab
	local options = bl_config.options
	if context.is_picking and element.letter then
		return bl_pick.component(context)
	elseif options.show_buffer_icons and element.icon then
		return get_icon(element, bl_config.highlights)
	end
end

local function get_close_icon(buf_id, context)
	local options = bl_config.options
	if options.hover.enabled and not context.tab:current() and vim.tbl_contains(options.hover.reveal, "close") then
		if not bl_state.hovered or bl_state.hovered.id ~= context.tab.id then
			return
		end
	end

	-- INFO: Replaces close icon with pin button if it is a temp tab
	local button_icon = bl_config.options.close_icon
	local s = state.get()
	if config.settings.show_pin_button_on_temp_tab then
		if s.temp_bufnr ~= -1 and s.temp_bufnr == buf_id then
			button_icon = config.settings.pin_icon
		end
	end
	local close_button_hl = context.current_highlights.close_button
	if not options.show_buffer_close_icons then
		return
	end

	return bl_ui.make_clickable("handle_button_click", buf_id, {
		text = button_icon,
		highlight = close_button_hl,
	})
end

local function get_max_length(context)
	local modified = bl_config.options.modified_icon
	local options = bl_config.options
	local element = context.tab
	local icon_size = strwidth(element.icon)
	local padding_size = strwidth(bl_constants.padding) * 2
	local max_length = options.max_name_length

	local autosize = not options.truncate_names and not options.enforce_regular_tabs
	local name_size = strwidth(context.tab.name)
	if autosize and name_size >= max_length then
		return name_size
	end

	if not options.enforce_regular_tabs then
		return max_length
	end
	-- estimate the maximum allowed size of a filename given that it will be
	-- padded and prefixed with a file icon
	return options.tab_size - strwidth(modified) - icon_size - padding_size
end

local function get_name(ctx)
	local name = bl_utils.truncate_name(ctx.tab.name, get_max_length(ctx))
	-- escape filenames that contain "%" as this breaks in statusline patterns
	name = name:gsub("%%", "%%%1")
	return { text = name, highlight = ctx.current_highlights.buffer }
end

local function spacing(opts)
	opts = opts or { when = true }
	if not opts.when then
		return
	end
	return { text = bl_constants.padding, highlight = opts.highlight }
end

local function has_text(s)
	if s == nil or s.text == nil or s.text == "" then
		return false
	end
	return true
end

local function get_component_size(segments)
	assert(bl_utils.is_list(segments), "Segments must be a list")
	local sum = 0
	for _, s in pairs(segments) do
		if has_text(s) then
			sum = sum + strwidth(tostring(s.text))
		end
	end
	return sum
end

local function is_slant(style)
	return vim.tbl_contains({ sep_names.slant, sep_names.padded_slant, sep_names.slope, sep_names.padded_slope }, style)
end

local function add_suffix(context)
	local element = context.tab
	local hl = context.current_highlights
	local symbol = bl_config.options.modified_icon
	-- If the buffer is modified add an icon, if it isn't pad
	-- the buffer so it doesn't "jump" when it becomes modified i.e. due
	-- to the sudden addition of a new character
	local modified = {
		text = element.modified and symbol or string.rep(bl_constants.padding, strwidth(symbol)),
		highlight = element.modified and hl.modified or nil,
	}
	local close = get_close_icon(element.id, context)
	return not element.modified and close or modified
end

local function add_indicator(context)
	local element = context.tab
	local hl = bl_config.highlights
	local curr_hl = context.current_highlights
	local options = bl_config.options
	local style = options.separator_style
	local symbol, highlight = bl_constants.padding, nil

	if is_slant(style) then
		return { text = symbol, highlight = highlight }
	end

	local is_current = element:current()

	symbol = is_current and options.indicator.icon or symbol
	highlight = is_current and hl.indicator_selected.hl_group
		or element:visible() and hl.indicator_visible.hl_group
		or curr_hl.buffer

	if options.indicator.style ~= "icon" then
		return { text = bl_constants.padding, highlight = highlight }
	end

	-- since all non-current buffers do not have an indicator they need
	-- to be padded to make up the difference in size
	return { text = symbol, highlight = highlight }
end

local function get_separator(focused, style)
	if type(style) == "table" then
		return focused and style[1] or style[2]
	end
	---@diagnostic disable-next-line: undefined-field
	local chars = sep_chars[style] or sep_chars.thin
	if is_slant(style) then
		return chars[1], chars[2]
	end
	return focused and chars[1] or chars[2]
end

local function add_separators(context)
	local hl = bl_config.highlights
	local options = bl_config.options
	local style = options.separator_style
	local focused = context.tab:current() or context.tab:visible()
	local right_sep, left_sep = get_separator(focused, style)
	local sep_hl = is_slant(style) and context.current_highlights.separator or hl.separator.hl_group

	local left_separator = left_sep and { text = left_sep, highlight = sep_hl } or nil
	local right_separator = { text = right_sep, highlight = sep_hl }
	return left_separator, right_separator
end

local function filter_invalid(parts)
	local result = {}
	for _, p in pairs(parts) do
		if p ~= nil then
			result[#result + 1] = p
		end
	end
	return result
end

local function pad(opts)
	opts.left, opts.right = opts.left or {}, opts.right or {}
	local left, left_hl = opts.left.size or 0, opts.left.hl or ""
	local right, right_hl = opts.right.size or 0, opts.right.hl or left_hl
	local left_p, right_p = string.rep(bl_constants.padding, left), string.rep(bl_constants.padding, right)
	return { text = left_p, highlight = left_hl }, { text = right_p, highlight = right_hl }
end

local function add_space(ctx, length)
	local options = bl_config.options
	local curr_hl = ctx.current_highlights
	local left_size, right_size = 0, 0
	local icon = options.buffer_close_icon
	-- pad each tab smaller than the max tab size to make it consistent
	local difference = options.tab_size - length
	if difference > 0 then
		local size = math.floor(difference / 2)
		left_size, right_size = size + left_size, size + right_size
	end
	if not options.show_buffer_close_icons then
		right_size = right_size > 0 and right_size - strwidth(icon) or right_size
		left_size = left_size + strwidth(icon)
	end
	return pad({
		left = { size = left_size, hl = curr_hl.buffer },
		right = { size = right_size },
	})
end

local function create_renderer(left_separator, right_separator, component)
	--- We return a function from render buffer as we do not yet have access to
	--- information regarding which buffers will actually be rendered
	--- @param next_item bufferline.Component
	--- @return string
	return function(next_item)
		-- if using the non-slanted tab style then we must check if the component is at the end of
		-- of a section e.g. the end of a group and if so it should not be wrapped with separators
		-- as it can use those of the next item
		if not is_slant(bl_config.options.separator_style) and next_item and next_item:is_end() then
			return component
		end

		if left_separator then
			table.insert(component, 1, left_separator)
			table.insert(component, right_separator)
			return component
		end

		if next_item then
			table.insert(component, right_separator)
		end

		return component
	end
end

bl_ui.element = function(current_state, element)
	local curr_hl = bl_highlights.for_element(element)

	local ctx = Context:new({
		tab = element,
		current_highlights = curr_hl,
		is_picking = bl_state.is_picking,
	})

	local duplicate_prefix = bl_duplicates.component(ctx)
	local group_item = element.group and groups.component(ctx) or nil
	local diagnostic = bl_diagnostics.component(ctx)
	local icon = add_icon(ctx)
	local number_item = bl_numbers.component(ctx)
	local suffix = add_suffix(ctx)
	local indicator = add_indicator(ctx)
	local left, right = add_separators(ctx)

	local name = get_name(ctx)
	-- Guess how much space there will for padding based on the buffer's name
	local name_size = get_component_size({ duplicate_prefix, name, spacing(), icon, suffix })
	local left_space, right_space = add_space(ctx, name_size)

	local component = filter_invalid({
		tab_click_handler(element.id),
		indicator,
		left_space,
		set_id(number_item, bl_components.id.number),
		spacing({ when = number_item }),
		set_id(icon, bl_components.id.icon),
		spacing({ when = icon }),
		set_id(group_item, bl_components.id.groups),
		spacing({ when = group_item }),
		set_id(duplicate_prefix, bl_components.id.duplicates),
		set_id(name, bl_components.id.name),
		spacing({ when = name, highlight = curr_hl.buffer }),
		set_id(diagnostic, bl_components.id.diagnostics),
		spacing({ when = diagnostic and #diagnostic.text > 0 }),
		right_space,
		suffix,
		spacing({ when = suffix }),
	})

	element.component = create_renderer(left, right, component)
	-- NOTE: we must count the size of the separators here although we do not
	-- add them yet, since by the time they are added the component will already have rendered
	element.length = get_component_size(filter_invalid({ left, right, unpack(component) }))
	return element
end

return bufferline_ui
