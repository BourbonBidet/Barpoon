-- NOTE: copy pasta'd 500 lines of barbar render code to add one button and colored text
--
-- This file contains code adapted from bufferline.nvim:
-- https://github.com/akinsho/bufferline.nvim/blob/main/lua/bufferline/ui.lua
--
-- The original project is licensed under the GNU General Public license:
-- Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
--
-- Modifications made in this file:
-- -- Allow barpoon to modify individual tabs with different button icons

local lazy = require("barpoon.lazy")
local state = lazy.require("barpoon.state") ---@module "barpoon.state"
local config = lazy.require("barpoon.config") ---@module "barpoon.config"
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"

local bb_config = lazy.require("barbar.config") ---@module "barbar.config"
local bb_buffer = lazy.require("barbar.buffer") ---@module "barbar.buffer"
local bb_layout = lazy.require("barbar.ui.layout") ---@module "barbar.ui.layout"
local bb_state = lazy.require("barbar.state") ---@module "barbar.state"
local bb_render = lazy.require("barbar.ui.render") ---@module "barbar.ui.render"
local bb_nodes = lazy.require("barbar.ui.nodes") ---@module "barbar.ui.nodes"
local hl = lazy.require("barbar.utils.highlight") ---@module "barbar.utils.highlight"
local bb_icons = lazy.require("barbar.icons") ---@module "barbar.icons"
local bb_highlight = lazy.require("barbar.highlight") ---@module "barbar.highlight"
local bb_animate = lazy.require("barbar.animate") ---@module "barbar.animate"
local bb_notify = lazy.require("barbar.utils").notify ---@module "barbar.utils"
local get_letter = lazy.require("barbar.jump_mode").get_letter ---@module "barbar.jump_mode"
local get_icon = lazy.require("barbar.icons").get_icon ---@module "barbar.icons"
local severity = vim.diagnostic.severity
local strcharpart = vim.fn.strcharpart --- @type function
local command = vim.api.nvim_command --- @type function
local ceil = math.ceil

local barbar_render = {}

local SUPERSCRIPT_DIGITS = { "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }
local SUBSCRIPT_DIGITS = { "₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉" }
local SUPERSCRIPT_LETTERS = {
	A = "ᴬ",
	B = "ᴮ",
	D = "ᴰ",
	E = "ᴱ",
	G = "ᴳ",
	H = "ᴴ",
	I = "ᴵ",
	J = "ᴶ",
	K = "ᴷ",
	L = "ᴸ",
	M = "ᴹ",
	N = "ᴺ",
	O = "ᴼ",
	P = "ᴾ",
	R = "ᴿ",
	T = "ᵀ",
	U = "ᵁ",
	V = "ⱽ",
	W = "ᵂ",
	a = "ᵃ",
	b = "ᵇ",
	c = "ᶜ",
	d = "ᵈ",
	e = "ᵉ",
	f = "ᶠ",
	g = "ᵍ",
	h = "ʰ",
	i = "ⁱ",
	j = "ʲ",
	k = "ᵏ",
	l = "ˡ",
	m = "ᵐ",
	n = "ⁿ",
	o = "ᵒ",
	p = "ᵖ",
	r = "ʳ",
	s = "ˢ",
	t = "ᵗ",
	u = "ᵘ",
	v = "ᵛ",
	w = "ʷ",
	x = "ˣ",
	y = "ʸ",
	z = "ᶻ",
}

local scroll = { current = 0, target = 0 }
local unpinned_buffers = {}

local function style_number(num, style)
	if style == true then
		return num, 0
	end
	local digits = style == "subscript" and SUBSCRIPT_DIGITS or SUPERSCRIPT_DIGITS
	return tostring(num):gsub("%d", function(match)
		return digits[match + 1]
	end)
end

local function style_label(char)
	if char:match("%d") then
		return style_number(tonumber(char))
	end
	return tostring(char):gsub("%s", function(match)
		return SUPERSCRIPT_LETTERS[match + 1]
	end)
end

local function wrap_hl(group)
	return "%#" .. group .. "#"
end

local HL = {
	FILL = wrap_hl("BufferTabpageFill"),
	TABPAGES = wrap_hl("BufferTabpages"),
	TABPAGES_SEP = wrap_hl("BufferTabpagesSep"),
	SIGN_INACTIVE = wrap_hl("BufferInactiveSign"),
	SCROLL_ARROW = wrap_hl("BufferScrollArrow"),
}

function barbar_render.setup_highlights()
	hl.set_default_link("BufferCurrentUnpooned", "BufferDefaultCurrentUnpooned")
	hl.set_default_link("BufferCurrentUnpoonedBtn", "BufferDefaultCurrentUnpoonedBtn")

	local current_hl = { "TabLineSel" }

	local attributes = hl.definition(current_hl) or {}
	attributes.bold = true
	local bg = hl.bg_or_default(current_hl, "none")
	local sp
	local fg_unpooned = hl.fg_or_default({ "Unpooned" }, config.settings.barbar.temp_tab_color, 90)

	hl.set("BufferDefaultCurrentUnpooned", bg, fg_unpooned, sp, attributes)
	hl.set("BufferDefaultVisibleMod", bg, fg_unpooned, sp, attributes)

	bb_icons.set_highlights()
	hl.reset_cache()
	bb_highlight.setup()
end

local MOVE_DURATION = 150
local move_animation = nil
local move_animation_data = {
	next_positions = nil,
	previous_positions = nil,
}

local function move_buffer_animated_tick(ratio, current_animation)
	for _, current_number in ipairs(bb_state.buffers_visible) do
		local current_data = bb_state.get_buffer_data(current_number)

		if current_animation.running == true then
			current_data.position = bb_animate.lerp(
				ratio,
				(move_animation_data.previous_positions or {})[current_number],
				(move_animation_data.next_positions or {})[current_number]
			)
		else
			current_data.position = nil
			current_data.moving = false
		end
	end

	bb_render.update()

	if current_animation.running == false then
		move_animation = nil
		move_animation_data.next_positions = nil
		move_animation_data.previous_positions = nil
	end
end

function barbar_render.swap_buffer(from_idx, to_idx, bufnr, previous_positions)
	local animation = bb_config.options.animation

	if animation == true then
		local current_index = utils.index_of(bb_state.buffers_visible, bufnr)
		local start_index = math.min(from_idx, current_index)
		local end_index = math.max(from_idx, current_index)

		if start_index == end_index then
			return
		elseif move_animation ~= nil then
			bb_animate.stop(move_animation)
		end

		local next_positions = bb_layout.calculate_buffers_position_by_buffer_number(bb_state)
		for _, layout_bufnr in ipairs(bb_state.buffers_visible) do
			local current_data = bb_state.get_buffer_data(layout_bufnr)

			local previous_position = previous_positions[layout_bufnr]
			local next_position = next_positions[layout_bufnr]

			if next_position ~= previous_position then
				current_data.position = previous_positions[layout_bufnr]
				current_data.moving = true
			end
		end

		move_animation_data = {
			previous_positions = previous_positions,
			next_positions = next_positions,
		}

		move_animation = bb_animate.start(MOVE_DURATION, 0, 1, vim.v.t_float, function(ratio, current_animation)
			move_buffer_animated_tick(ratio, current_animation)
		end)
	end

	bb_render.update()
end

local function get_bufferline_containers(data, bufnrs, refocus)
	local click_enabled = vim.fn.has("tablineat") and bb_config.options.clickable

	local accumulated_pinned_width = 0 --- the width of pinned buffers accumulated while iterating
	local accumulated_unpinned_width = 0 --- the width of buffers accumulated while iterating
	local current_buffer = nil --- @type nil|{idx: integer, pinned: boolean}
	local done = false --- if all of the visible buffers have been clumped
	local containers = {}
	local pinned_containers = {}

	-- INFO: Remove some padding if there are key labels
	local offset = config.settings.key_labels ~= nil and -1 or 0
	local pinned_pad_text = (" "):rep(bb_config.options.minimum_padding + offset)
	local unpinned_pad_text = (" "):rep(data.buffers.padding + offset)

	for i, bufnr in ipairs(bufnrs) do
		-- INFO: Add back padding when we run out of key labels
		if config.settings.key_labels ~= nil and i == #config.settings.key_labels + 1 then
			pinned_pad_text = pinned_pad_text .. " "
			unpinned_pad_text = unpinned_pad_text .. " "
		end
		local activity = bb_buffer.get_activity(bufnr)
		local activity_name = bb_buffer.activities[activity]
		local buffer_data = bb_state.get_buffer_data(bufnr)
		local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr })
		local pinned = buffer_data.pinned

		-- Check if the buffer is the current temp buffer
		local unpooned = false
		local s = state.get()
		local should_open = config and config.settings and config.settings.show_pin_button_on_temp_tab
		if should_open and s.temp_bufnr == bufnr then
			unpooned = true
		end

		if pinned then
			buffer_data.computed_position = accumulated_pinned_width
			buffer_data.computed_width =
				bb_layout.calculate_width(data.buffers.base_widths[i], bb_config.options.minimum_padding)
		else
			buffer_data.computed_position = accumulated_unpinned_width + data.buffers.pinned_width
			buffer_data.computed_width = bb_layout.calculate_width(data.buffers.base_widths[i], data.buffers.padding)
		end
		local container_width = buffer_data.width or buffer_data.computed_width

		if activity == bb_buffer.activities.Current and refocus ~= false then
			current_buffer = { idx = #(pinned and pinned_containers or containers) + 1, pinned = pinned }

			local start = accumulated_unpinned_width
			local end_ = accumulated_unpinned_width + container_width

			if scroll.target > start then
				bb_render.set_scroll(start)
			elseif scroll.target + data.buffers.unpinned_allocated_width < end_ then
				bb_render.set_scroll(scroll.target + (end_ - (scroll.target + data.buffers.unpinned_allocated_width)))
			end
		end

		if pinned then
			accumulated_pinned_width = accumulated_pinned_width + container_width
		else
			accumulated_unpinned_width = accumulated_unpinned_width + container_width

			if accumulated_unpinned_width < scroll.current then
				goto continue -- HACK: there is no `continue` keyword
			elseif
				(refocus == false or (refocus ~= false and current_buffer ~= nil))
				and accumulated_unpinned_width - scroll.current > data.buffers.unpinned_allocated_width
			then
				done = true
			end
		end

		--- the start of all rendered highlight names
		local hl_prefix = "Buffer" .. activity_name

		--- the suffix of some (eventually all) rendered highlight names
		local hl_suffix = (modified and "Mod") or (unpooned and "Unpooned") or ""
		local buffer_name = buffer_data.name or "[no name]"
		local buffer_hl = wrap_hl(hl_prefix .. hl_suffix)

		local icons_option = bb_buffer.get_icons(activity_name, modified, pinned)

		--- Prefix this value to allow an element to be clicked
		local clickable = click_enabled and ("%" .. bufnr .. "@barbar#events#main_click_handler@") or ""

		local name = { hl = clickable .. buffer_hl, text = icons_option.filename and buffer_name or "" }

		local buffer_label = { hl = "", text = "" }
		local buffer_index = { hl = "", text = "" }
		local buffer_number = { hl = "", text = "" }
		if config.settings.key_labels ~= nil and i <= #config.settings.key_labels then
			buffer_label.hl = wrap_hl(hl_prefix .. "Index")
			local label = string.sub(config.settings.key_labels, i, i)
			buffer_label.text = style_label(label) .. " "
		else
			if icons_option.buffer_index then
				buffer_index.hl = wrap_hl(hl_prefix .. "Index")
				buffer_index.text = style_number(i, icons_option.buffer_index) .. " "
			end

			if icons_option.buffer_number then
				buffer_number.hl = wrap_hl(hl_prefix .. "Number")
				buffer_number.text = style_number(bufnr, icons_option.buffer_number) .. " "
			end
		end

		local pin_button = { hl = wrap_hl(hl_prefix .. hl_suffix .. "Btn"), text = "" }

		local pin_button_icon = config.settings.pin_icon
		if pin_button_icon and #pin_button_icon > 0 then
			pin_button.text = pin_button_icon .. " "

			if click_enabled then
				pin_button.hl = "%" .. bufnr .. "@barpoon#barbar#bar#on_click_pin_handler@" .. pin_button.hl
			end
		end

		local close_button = { hl = wrap_hl(hl_prefix .. hl_suffix .. "Btn"), text = "" }

		local button_icon = icons_option.button
		if button_icon and #button_icon > 0 then
			close_button.text = button_icon .. " "

			if click_enabled then
				close_button.hl = "%" .. bufnr .. "@barbar#events#close_click_handler@" .. close_button.hl
			end
		end

		local jump_letter = { hl = "", text = "" }

		local icon = { hl = clickable, text = "" }

		if bb_state.is_picking_buffer then
			local letter = get_letter(bufnr)

			-- Replace first character of buf name with jump letter
			if letter and not icons_option.filetype.enabled then
				name.text = strcharpart(name.text, 1)
			end

			jump_letter.hl = wrap_hl(hl_prefix .. "Target")
			if letter then
				jump_letter.text = letter
				if icons_option.filetype.enabled and #name.text > 0 then
					jump_letter.text = jump_letter.text .. " "
				end
			elseif icons_option.filetype.enabled then
				jump_letter.text = "  "
			end
		elseif icons_option.filetype.enabled then
			local iconChar, iconHl = get_icon(bufnr, activity_name)
			local hlName = (activity_name == "Inactive" and not bb_config.options.highlight_inactive_file_icons)
					and "BufferInactive"
				or iconHl

			icon.hl = icons_option.filetype.custom_colors and wrap_hl(hl_prefix .. "Icon")
				or (hlName and wrap_hl(hlName) or buffer_hl)
			icon.text = #name.text > 0 and iconChar .. " " or iconChar
		end

		local left_separator = {
			hl = clickable .. wrap_hl(hl_prefix .. "Sign"),
			text = icons_option.separator.left,
		}

		local padding = { hl = buffer_hl, text = pinned and pinned_pad_text or unpinned_pad_text }

		local container = {
			-- nodes = { left_separator, padding, buffer_number, buffer_index, icon, jump_name },
			nodes = { left_separator, padding, buffer_label, buffer_number, buffer_index, icon, jump_letter, name },
			--- @diagnostic disable-next-line:assign-type-mismatch it is assigned just earlier
			position = buffer_data.position or buffer_data.computed_position,
			--- @diagnostic disable-next-line:assign-type-mismatch it is assigned just earlier
			width = container_width,
		}

		bb_state.for_each_counted_enabled_diagnostic(bufnr, icons_option.diagnostics, function(count, idx, option)
			table.insert(container.nodes, {
				hl = wrap_hl(hl_prefix .. severity[idx]),
				text = " " .. option.icon .. count,
			})
		end)

		bb_state.for_each_counted_enabled_git_status(bufnr, icons_option.gitsigns, function(count, idx, option)
			table.insert(container.nodes, {
				hl = wrap_hl(hl_prefix .. idx:upper()),
				text = " " .. option.icon .. count,
			})
		end)

		local right_separator = {
			hl = clickable .. wrap_hl(hl_prefix .. "SignRight"),
			text = icons_option.separator.right,
		}

		local button = close_button
		if unpooned then
			button = pin_button
		end

		vim.list_extend(container.nodes, { padding, button, right_separator })
		table.insert(pinned and pinned_containers or containers, container)

		if done then
			break
		end

		::continue::
	end

	return pinned_containers, containers, current_buffer
end

local function generate_side_offset(side)
	local offset = bb_state.offset[side]

	local align = offset.align
	local hl = wrap_hl(offset.hl)
	local text = offset.text
	local width = offset.width

	local max_content_width = width - 2
	local content = bb_nodes.slice_right({ { hl = hl, text = text } }, max_content_width)

	if max_content_width > #text then
		local offset_nodes = { { hl = hl, text = (" "):rep(width) } }

		local insert_position
		if align == "left" then
			insert_position = 1
		else -- align to the right (NOTE: center alignment is a type of right alignment)
			insert_position = width - #text - 1
			if align == "center" then
				insert_position = ceil(insert_position / 2)
			end
		end

		content = bb_nodes.insert_many(offset_nodes, insert_position, content)
	end

	return bb_nodes.to_string(content)
end

local function generate_tabline(bufnrs, refocus)
	local data = bb_layout.calculate(bb_state)
	if refocus ~= false and scroll.current > data.buffers.scroll_max then
		bb_render.set_scroll(data.buffers.scroll_max)
	end

	local pinned, unpinned, current_buffer = get_bufferline_containers(data, bufnrs, refocus)

	-- Create actual tabline string
	local result = ""

	-- Left offset
	if bb_state.offset.left.width > 0 then
		result = result .. generate_side_offset("left")
	end

	-- Buffer tabs
	do
		local content = { { hl = HL.FILL, text = (" "):rep(data.buffers.width) } }

		do
			local current_container = nil
			local current_not_unpinned = current_buffer == nil or current_buffer.pinned == true

			for i, container in ipairs(unpinned) do
				-- We insert the current buffer after the others so it's always on top
				--- @diagnostic disable-next-line:need-check-nil
				if current_not_unpinned or (current_buffer.pinned == false and current_buffer.idx ~= i) then
					content = bb_nodes.insert_many(content, container.position - scroll.current, container.nodes)
				else
					current_container = container
				end
			end

			if current_container ~= nil then
				content =
					bb_nodes.insert_many(content, current_container.position - scroll.current, current_container.nodes)
			end
		end

		if bb_config.options.icons.separator_at_end then
			local inactive_separator = bb_config.options.icons.inactive.separator.left
			if
				inactive_separator ~= nil
				and #unpinned > 0
				and data.buffers.unpinned_width + vim.fn.strwidth(inactive_separator)
					<= data.buffers.unpinned_allocated_width
			then
				content = bb_nodes.insert(
					content,
					data.buffers.used_width,
					{ text = inactive_separator, hl = HL.SIGN_INACTIVE }
				)
			end
		end

		if #pinned > 0 then
			local current_container = nil
			local current_not_pinned = current_buffer == nil or current_buffer.pinned == false

			for i, container in ipairs(pinned) do
				-- We insert the current buffer after the others so it's always on top
				--- @diagnostic disable-next-line:need-check-nil
				if current_not_pinned or (current_buffer.pinned == true and current_buffer.idx ~= i) then
					content = bb_nodes.insert_many(content, container.position, container.nodes)
				else
					current_container = container
				end
			end

			if current_container ~= nil then
				content = bb_nodes.insert_many(content, current_container.position, current_container.nodes)
			end
		end

		local filler = { { hl = HL.FILL, text = (" "):rep(data.buffers.width) } }
		content = bb_nodes.insert_many(filler, 0, content)
		content = bb_nodes.slice_right(content, data.buffers.width)

		local has_left_scroll = scroll.current > 0
		if has_left_scroll then
			content = bb_nodes.insert(content, data.buffers.pinned_width, {
				hl = HL.SCROLL_ARROW,
				text = bb_config.options.icons.scroll.left,
			})
		end

		local has_right_scroll = data.buffers.used_width - scroll.current > data.buffers.width
		if has_right_scroll then
			content = bb_nodes.insert(content, data.buffers.width - 1, {
				hl = HL.SCROLL_ARROW,
				text = bb_config.options.icons.scroll.right,
			})
		end

		-- Render bufferline string
		result = result .. bb_nodes.to_string(content)

		-- Prevent the expansion of the last click group
		if bb_config.options.clickable then
			result = result .. "%0@barbar#events#main_click_handler@"
		end
	end

	-- Tabpages
	if data.tabpages.width > 0 then
		result = result
			.. bb_nodes.to_string({
				{ hl = HL.TABPAGES, text = " " .. vim.fn.tabpagenr() },
				{ hl = HL.TABPAGES_SEP, text = "/" },
				{ hl = HL.TABPAGES, text = vim.fn.tabpagenr("$") .. " " },
			})
	end

	-- Right offset
	if bb_state.offset.right.width > 0 then
		result = result .. generate_side_offset("right")
	end

	-- NOTE: For development or debugging purposes, the following code can be used:
	-- ```lua
	-- local text = Nodes.to_raw_string(bufferline_nodes, true)
	-- if layout.buffers.unpinned_width + strwidth(inactive_separator) <= layout.buffers.unpinned_allocated_width and #items > 0 then
	--   text = text .. Nodes.to_raw_string({{ text = inactive_separator or '', hl = wrap_hl('BufferInactiveSign') }}, true)
	-- end
	-- local data = vim.json.encode({ metadata = 42 })
	-- fs.write('barbar.debug.txt', text .. ':' .. data .. '\n', 'a')
	-- ```

	return result .. HL.FILL
end

function bb_render.update(update_names, refocus)
	if vim.g.SessionLoad then
		return
	end
	local buffers = bb_layout.hide(bb_state, bb_state.get_updated_buffers(update_names))
	--
	-- Auto hide/show if applicable
	if bb_config.options.auto_hide > -1 then
		if #buffers <= bb_config.options.auto_hide then
			if vim.api.nvim_get_option_value("showtabline", { scope = "global" }) ~= 0 then
				vim.api.nvim_set_option_value("showtabline", 0, { scope = "global" })
			end
		else
			if vim.api.nvim_get_option_value("showtabline", { scope = "global" }) ~= 2 then
				vim.api.nvim_set_option_value("showtabline", 2, { scope = "global" })
			end
		end
	end

	-- Store current buffer to open new ones next to this one
	local current = vim.api.nvim_get_current_buf()
	if vim.api.nvim_get_option_value("buflisted", { buf = current }) then
		if vim.b.empty_buffer then
			bb_state.last_current_buffer = nil
		else
			bb_state.last_current_buffer = current
		end
	end

	-- Render the tabline
	local ok, result = xpcall(function()
		if buffers then
			bb_render.set_tabline(generate_tabline(buffers, refocus))
		end
	end, debug.traceback)

	if not ok then
		command("BarbarDisable")
		bb_notify(
			"Barbar detected an error while running. Barbar disabled itself :/ "
				.. "Include this in your report: "
				.. tostring(result),
			vim.log.levels.ERROR
		)
	end
end

return barbar_render
