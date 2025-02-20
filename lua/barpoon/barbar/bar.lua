local lazy = require("barpoon.lazy")
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"
local events = lazy.require("barpoon.events") ---@module "barpoon.events"
local state = lazy.require("barpoon.state") ---@module "barpoon.state"
local render = lazy.require("barpoon.barbar.render") ---@module "barpoon.barbar.render"
local bar = lazy.require("barpoon.bar") ---@module "barpoon.bar"

local bb_events = lazy.require("barbar.events") ---@module "barbar.events"
local bb_state = lazy.require("barbar.state") ---@module "barbar.state"
local bdelete = lazy.require("barbar.bbye").bdelete ---@module "barbar.bbye"
local bb_api = lazy.require("barbar.api") ---@module "barbar.api"
local bb_buffer = lazy.require("barbar.buffer") ---@module "barbar.buffer"
local bb_render = lazy.require("barbar.ui.render") ---@module "barbar.ui.render"
local bb_config = lazy.require("barbar.config") ---@module "barbar.config"
local bb_layout = lazy.require("barbar.ui.layout") ---@module "barbar.ui.layout"

---@class BarbarBar : BarpoonBar
local BarbarBar = {}
local enabled = true

function BarbarBar.update()
	bb_state.buffers = state.get().buffers
	bb_render.update(true)
end

function BarbarBar.on_click_pin_handler(buffer)
	events.emit(bar.events.ON_PIN_TAB, buffer)
end

function BarbarBar.enable()
	enabled = true
	bb_events.enable()
	render.setup_highlights()
	events.emit(bar.events.ON_TOGGLE_ENABLED, true)
	bb_render.update(true)
end

function BarbarBar.disable()
	enabled = false
end

--
--
--
-- INFO: overrides the method barbar uses to determine its state

bb_state.get_buffer_list = function()
	local buffers = state.get().buffers
	bb_state.buffers = buffers
	return buffers
end

local get_updated_buffers_base = bb_state.get_updated_buffers
bb_state.get_updated_buffers = function(update_names)
	bb_state.buffers = state.get(true).buffers
	return get_updated_buffers_base(update_names)
end

function bb_events.close_click_handler(bufnr)
	events.emit(bar.events.ON_CLOSE_TAB, bufnr)
end

local events_enable_base = bb_events.enable
bb_events.enable = function()
	events_enable_base()
	enabled = true
	events.emit(bar.events.ON_TOGGLE_ENABLED, enabled)
end

local events_disable_base = bb_events.disable
bb_events.disable = vim.schedule_wrap(function()
	events_disable_base()
	enabled = false
	events.emit(bar.events.ON_TOGGLE_ENABLED, enabled)
end)

--
--
-- INFO: Override the relevant BarBar api methods to work as expected
--
function bb_api.restore_buffer()
	events.emit(bar.events.ON_RESTORE_BUFFER)
end

function bb_api.goto_buffer_relative(steps)
	bb_state.get_updated_buffers()

	if #bb_state.buffers < 1 then
		return utils.notify("E85: There is no listed buffer", vim.log.levels.ERROR)
	end

	local current_bufnr = vim.api.nvim_get_current_buf()
	local idx = utils.index_of(bb_state.buffers, current_bufnr)

	if not idx then -- fall back to: 1. the alternate buffer, 2. the first buffer
		idx = utils.index_of(bb_state.buffers, vim.fn.bufnr("#")) or 1
		utils.notify(
			"Couldn't find buffer #"
				.. current_bufnr
				.. " in the list: "
				.. vim.inspect(bb_state.buffers)
				.. ". Falling back to buffer #"
				.. bb_state.buffers[idx],
			vim.log.levels.INFO
		)
	end
	local new_idx = (idx + steps - 1) % #bb_state.buffers + 1

	vim.api.nvim_set_current_buf(bb_state.buffers[new_idx])
end

function bb_api.move_buffer(buffer_number, steps)
	local idx = utils.index_of(bb_state.buffers, buffer_number)
	if idx == nil then
		return
	end
	local to_idx = math.max(1, math.min(#bb_state.buffers, idx + steps))
	if to_idx == idx then
		return
	end

	local animation = bb_config.options.animation

	local previous_positions
	if animation == true then
		previous_positions = bb_layout.calculate_buffers_position_by_buffer_number(bb_state)
	end

	events.emit(bar.events.ON_MOVE_TAB, idx, idx + steps, false)
	render.swap_buffer(idx, idx + steps, buffer_number, previous_positions)
end

local move_buffer_to_base = bb_api.move_current_buffer_to
function bb_api.move_current_buffer_to(idx)
	if idx == -1 then
		idx = #bb_state.buffers
	end

	local current_bufnr = vim.api.nvim_get_current_buf()
	local from_idx = utils.index_of(bb_state.buffers, current_bufnr)

	if from_idx ~= nil then
		move_buffer_to_base(idx)
		events.emit(bar.events.ON_MOVE_TAB, from_idx, idx)
	end
end

function bb_api.close_all_but_current()
	local current_bufnr = vim.api.nvim_get_current_buf()
	for _, buffer_number in ipairs(bb_state.buffers) do
		if buffer_number ~= current_bufnr and buffer_number ~= nil then
			events.emit(bar.events.ON_CLOSE_TAB, buffer_number)
			bdelete(false, buffer_number)
		end
	end
end

function bb_api.close_all_but_visible()
	local visible = bb_buffer.activities.Visible
	for _, buffer_number in ipairs(bb_state.buffers) do
		if bb_buffer.get_activity(buffer_number) < visible then
			events.emit(bar.events.ON_CLOSE_TAB, buffer_number)
			bdelete(false, buffer_number)
		end
	end
end

function bb_api.close_buffers_left()
	local idx = utils.index_of(bb_state.buffers, vim.api.nvim_get_current_buf())
	if idx == nil or idx == 1 then
		return
	end

	for i = idx - 1, 1, -1 do
		bdelete(false, bb_state.buffers[i])
		events.emit(bar.events.ON_CLOSE_TAB, bb_state.buffers[i])
	end
end

function bb_api.close_buffers_right()
	local idx = utils.index_of(bb_state.buffers, vim.api.nvim_get_current_buf())
	if idx == nil then
		return
	end

	for i = #bb_state.buffers, idx + 1, -1 do
		bdelete(false, bb_state.buffers[i])
		events.emit(bar.events.ON_CLOSE_TAB, bb_state.buffers[i])
	end
end

function bb_api.close_all_but_pinned()
	for _, buffer_number in ipairs(bb_state.buffers) do
		if not bb_state.is_pinned(buffer_number) then
			events.emit(bar.events.ON_CLOSE_TAB, buffer_number)
			bdelete(false, buffer_number)
		end
	end
end

function bb_api.close_all_but_current_or_pinned()
	local current_bufnr = vim.api.nvim_get_current_buf()
	for _, buffer_number in ipairs(bb_state.buffers) do
		if not bb_state.is_pinned(buffer_number) and buffer_number ~= current_bufnr then
			events.emit(bar.events.ON_CLOSE_TAB, buffer_number)
			bdelete(false, buffer_number)
		end
	end
end

local order_by_buffer_number_base = bb_api.order_by_buffer_number
function bb_api.order_by_buffer_number()
	order_by_buffer_number_base()
	events.emit(bar.events.ON_SORT_TABS, bb_state.buffers)
end

local order_by_name_base = bb_api.order_by_name
function bb_api.order_by_name()
	order_by_name_base()
	events.emit(bar.events.ON_SORT_TABS, bb_state.buffers)
end

local order_by_directory_base = bb_api.order_by_directory
function bb_api.order_by_directory()
	order_by_directory_base()
	events.emit(bar.events.ON_SORT_TABS, bb_state.buffers)
end

local order_by_language_base = bb_api.order_by_language
function bb_api.order_by_language()
	order_by_language_base()
	events.emit(bar.events.ON_SORT_TABS, bb_state.buffers)
end

local order_by_window_number_base = bb_api.order_by_window_number
function bb_api.order_by_window_number()
	order_by_window_number_base()
	events.emit(bar.events.ON_SORT_TABS, bb_state.buffers)
end

return BarbarBar
