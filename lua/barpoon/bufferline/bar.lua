local lazy = require("barpoon.lazy")

local state = lazy.require("barpoon.state") ---@module "barpoon.state"
local config = lazy.require("barpoon.config") ---@module "barpoon.config"
local events = lazy.require("barpoon.events") ---@module "barpoon.events"
local render = lazy.require("barpoon.bufferline.render") ---@module "barpoon.bufferline.render"
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"
local bar = lazy.require("barpoon.bar") ---@module "barpoon.bar"

local bl_utils = lazy.require("bufferline.utils") ---@module "bufferline.utils"
local bl_groups = lazy.require("bufferline.groups") ---@module "bufferline.groups"
local bl_pick = lazy.require("bufferline.pick") ---@module "bufferline.pick"
local bl_sorter = lazy.require("bufferline.sorters") ---@module "bufferline.sorters"
local bl_commands = lazy.require("bufferline.commands") ---@module "bufferline.commands"
local bl_config = lazy.require("bufferline.config") ---@module "bufferline.config"
local bl_state = lazy.require("bufferline.state") ---@module "bufferline.state"
local bl_sorters = lazy.require("bufferline.sorters") ---@module "bufferline.sorters"
local bl_tabpages = lazy.require("bufferline.tabpages") ---@module "bufferline.tabpages"
local bl_buffers = lazy.require("bufferline.buffers") ---@module "bufferline.buffers"
local bl_numbers = lazy.require("bufferline.numbers") ---@module "bufferline.numbers"
local bl_ui = lazy.require("bufferline.ui") ---@module "bufferline.ui"

local BUFFERLINE_GROUP = "BufferlineCmds"

---@class BufferlineBar : BarpoonBar
local BufferlineBar = {}
local enabled = true

-- Hide the bufferline if requirements are met
local function toggle_bufferline()
	if not bl_config.options.auto_toggle_bufferline then
		return
	end
	local item_count = bl_config:is_tabline() and bl_utils.get_tab_count() or bl_utils.get_buf_count()
	local hide_threshold = config.settings.bufferline.hide_threshold or 0
	local status = (bl_config.options.always_show_bufferline or item_count > hide_threshold) and 2 or 0
	if vim.o.showtabline ~= status then
		vim.o.showtabline = status
	end
end

function BufferlineBar.update()
	toggle_bufferline()
	render.update()
end

function BufferlineBar.disable()
	enabled = false
end

---@param bufnr integer
local function close_tab(bufnr)
	-- state.close_tab(bufnr)
	events.emit(bar.events.ON_CLOSE_TAB, bufnr)
end

---@param buffers integer[]
local function close_tabs(buffers)
	for _, bufnr in ipairs(buffers) do
		close_tab(bufnr)
	end
end

---@param bufnr integer
local function handle_button_click(bufnr, _, _)
	-- print("clicked: ", bufnr)
	local temp = state.get().temp_bufnr
	if config.settings.show_pin_button_on_temp_tab and temp ~= nil and bufnr == temp then
		events.emit(bar.events.ON_PIN_TAB, bufnr)
	else
		close_tab(bufnr)
	end
end

local function bufferline()
	local is_tabline = bl_config:is_tabline()

	local components = is_tabline and bl_tabpages.get_components(state) or bl_buffers.get_components(state)

	-- NOTE: keep track of the previous state so it can be used for sorting
	-- specifically to position newly opened buffers next to the buffer that was previously open
	local prev_idx, prev_components = state.current_element_index, state.components

	local function sorter(list)
		return bl_sorters.sort(list, {
			current_index = prev_idx,
			prev_components = prev_components,
			custom_sort = state.custom_sort,
		})
	end

	local _, current_idx = bl_utils.find(function(component)
		return component:current()
	end, components)

	bl_state.set({ current_element_index = current_idx })
	components = not is_tabline and bl_groups.render(components, sorter) or sorter(components)
	local tabline = bl_ui.tabline(components, bl_tabpages.get())

	bl_state.set({
		--- store the full unfiltered lists
		__components = components,
		--- Store copies without focusable/hidden elements
		components = components,
		visible_components = tabline.visible_components,
		--- size data stored for use elsewhere e.g. hover positioning
		left_offset_size = tabline.left_offset_size,
		right_offset_size = tabline.right_offset_size,
	})
	return tabline.str, tabline.segments
end

local function setup_autocommands()
	vim.api.nvim_clear_autocmds({
		group = BUFFERLINE_GROUP,
		event = { "BufAdd", "TabEnter" },
		pattern = "*",
	})
	if not bl_config.options.always_show_bufferline then
		vim.api.nvim_create_autocmd({ "BufAdd", "TabEnter" }, {
			pattern = "*",
			group = BUFFERLINE_GROUP,
			callback = function()
				toggle_bufferline()
			end,
		})
	end
end

function BufferlineBar.enable()
	bl_config.options.sort_by = "barpoon"
	enabled = true
	setup_autocommands()
	toggle_bufferline()
	render.update()
	utils.command("BufferLineSortByExtension", function()
		bl_commands.sort_by("extension")
	end)
	utils.command("BufferLineSortByDirectory", function()
		bl_commands.sort_by("directory")
	end)
	utils.command("BufferLineSortByRelativeDirectory", function()
		bl_commands.sort_by("relative_directory")
	end)
	utils.command("BufferLineSortByTabs", function()
		bl_commands.sort_by("tabs")
	end)
	utils.command("BufferLineCloseRight", function()
		bl_commands.close_in_direction("right")
	end)
	utils.command("BufferLineCloseLeft", function()
		bl_commands.close_in_direction("left")
	end)
	utils.command("BufferLineCloseOthers", function()
		bl_commands.close_others()
	end)
	utils.command("BufferLineGroupClose", function(opts)
		-- bl_groups.complete({})
		-- close_tabs(bl_groups.complete)
		-- bl_commands.
	end)
	utils.command("BufferLinePickClose", function()
		bl_commands.close_with_pick()
	end)
end

local handle_click_base = _G.___bufferline_private.handle_click
local function handle_click(bufnr, _, button)
	if button == "l" then
		handle_click_base(bufnr, _, button)
	else
		-- if button == "r" then
		-- 	close_tab(bufnr)
		-- end
		-- return
	end
	handle_click_base(bufnr, _, button)
end

---------
--
-- INFO: Override the relevant API methods to make sure Harpoon can update accordingly
--
---------

-- INFO: Overrides the main method bufferline uses to find the current buffers
bl_utils.get_valid_buffers = function()
	return state.get(true).buffers
end

bl_commands.sort_by = function(sort_by)
	if next(bl_state.components) == nil then
		return bl_utils.notify("Unable to find elements to sort, sorry", "warn")
	end
	bl_sorter.sort(bl_state.components, { sort_by = sort_by })
	state.custom_sort = bl_utils.get_ids(bl_state.components)
	local opts = bl_config.options
	if opts.persist_buffer_sort then
		bl_utils.save_positions(state.custom_sort)
	end
	local buffers = {}
	for index, value in ipairs(bl_state.components) do
		table.insert(buffers, value.id)
	end
	events.emit(bar.events.ON_SORT_TABS, buffers)
	BufferlineBar.update()
end

local sort_base = bl_sorter.sort
bl_sorter.sort = function(elements, opts)
	if not opts.sort_by or opts.sort_by == "barpoon" then
		return elements
	else
		sort_base(elements, opts)
	end
end

bl_commands.close_in_direction = function(direction)
	local index = bl_commands.get_current_element_index(bl_state)
	if not index then
		return
	end
	local length = #bl_state.components
	if not (index == length and direction == "right") and not (index == 1 and direction == "left") then
		local start = direction == "left" and 1 or index + 1
		local _end = direction == "left" and index - 1 or length
		for _, item in ipairs(vim.list_slice(bl_state.components, start, _end)) do
			close_tab(item.id)
		end
	end
	BufferlineBar.update()
end

bl_commands.unpin_and_close = function(id)
	close_tab(id)
end

--Close other buffers
bl_commands.close_others = function()
	local index = bl_commands.get_current_element_index(bl_state)
	if not index then
		return
	end

	for i, item in ipairs(bl_state.components) do
		if i ~= index then
			close_tab(item.id)
		end
	end
	BufferlineBar.update()
end

bl_commands.close_with_pick = function()
	bl_pick.choose_then(function(id)
		close_tab(id)
	end)
end

bl_commands.move_to = function(to_index, from_index)
	events.emit(bar.events.ON_MOVE_TAB, from_index, to_index)
end

bl_utils.get_buf_count = function()
	return #state.get().buffers
end

if config.settings.key_labels ~= nil then
	bl_numbers.component = function(context)
		local i = context.tab.ordinal
		local num = string.sub(config.settings.key_labels, i, i) or ""
		return { highlight = context.current_highlights.numbers, text = num }
	end
end

_G.nvim_bufferline = function()
	toggle_bufferline()
	return bufferline()
end

-- INFO: The global functions that get called for the tab/button click events
_G.___bufferline_private = _G.___bufferline_private or {} -- to guard against reloads
_G.___bufferline_private.handle_button_click = handle_button_click
_G.___bufferline_private.handle_click = handle_click

return BufferlineBar
