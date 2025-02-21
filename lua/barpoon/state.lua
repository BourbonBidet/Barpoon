local lazy = require("barpoon.lazy")
local harpoon_wrapper = lazy.require("barpoon.harpoon_wrapper") ---@module "barpoon.harpoon_wrapper"
local config = lazy.require("barpoon.config") ---@module "barpoon.config"
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"
local events = lazy.require("barpoon.events") ---@module "barpoon.events"
local barpoon_enabled = true
local closed_buffer_stack = {}
local buffer_name_map = {}
local augroup = vim.api.nvim_create_augroup("Barpoon", { clear = true })

---@alias BarpoonState {buffers: integer[], temp_bufnr: integer }
local state = {
	buffers = {},
	temp_bufnr = -1,
}

state.events = {
	ON_UPDATE_STATE = "on_update_state",
}

---@return table
local function update_state()
	state.buffers = {}
	if not barpoon_enabled then
		return state.buffers
	end
	local harpoon_list = harpoon_wrapper.get_items()
	local removed_buf_names = {}
	for _, v in ipairs(harpoon_list) do
		local bufnr = vim.fn.bufnr(utils.to_exact_name(v.value))

		if bufnr == -1 then
			bufnr = vim.fn.bufadd(v.value)
		else
			table.insert(removed_buf_names, v.value)
		end
		if state.temp_bufnr ~= -1 and bufnr == state.temp_bufnr then
			state.temp_bufnr = -1
		end
		buffer_name_map[bufnr] = v.value
		table.insert(state.buffers, bufnr)
	end
	if config.settings.open_tab_for_current_buffer then
		if state.temp_bufnr ~= -1 then
			local name = vim.fn.bufname(state.temp_bufnr)

			if name ~= -1 then
				buffer_name_map[state.temp_bufnr] = name
				table.insert(state.buffers, state.temp_bufnr)
			end
		end
	end
	events.emit(state.events.ON_UPDATE_STATE)

	return state.buffers
end

---@param bufnr number
local function update_temp_tab(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })

	for _, buf in ipairs(state.buffers) do
		if buf ~= state.temp_bufnr and buf == bufnr then
			state.temp_bufnr = -1
			update_state()
			return
		end
	end
	if buftype == "" and buf_name ~= "" then
		state.temp_bufnr = bufnr
		update_state()
	end
end

---@param bufnr integer
local function on_remove_item(_, _, bufnr)
	local cur_buf = vim.api.nvim_get_current_buf()
	if cur_buf == bufnr then
		state.temp_bufnr = cur_buf
	end
	update_state()
end

function state.get(shouldRefresh)
	shouldRefresh = shouldRefresh or false
	if shouldRefresh and #state.buffers > 0 then
		for i, bufnr in ipairs(state.buffers) do
			if not vim.api.nvim_buf_is_valid(bufnr) then
				if bufnr == state.temp_bufnr then
					table.remove(state.buffers, i)
					state.temp_bufnr = -1
				else
					local name = buffer_name_map[bufnr]
					if name ~= nil then
						harpoon_wrapper.remove_item_by_name(name)
						table.remove(state.buffers, i)
					end
				end
			end
		end
	end
	return state
end

---@param bufnr number
function state.close_tab(bufnr)
	if bufnr == nil or bufnr == -1 then
		return
	end
	local deleted_item = harpoon_wrapper.remove_item_by_bufnr(bufnr)
	if deleted_item then
		table.insert(closed_buffer_stack, deleted_item.value)
	end
	update_state()
end

---@param start_index integer
---@param end_index integer
---@param should_update boolean
function state.move_tab(start_index, end_index, should_update)
	should_update = should_update or false
	if state.temp_bufnr ~= -1 and start_index == #state.buffers then
		update_state()
		return
	end
	harpoon_wrapper.move_item(start_index, end_index, should_update)
end

---@param buffers integer[]
function state.sort_tabs(buffers)
	harpoon_wrapper.sort_items(buffers)
end

function state.restore_buffer()
	if #closed_buffer_stack <= 0 then
		return
	end
	local name = closed_buffer_stack[#closed_buffer_stack]
	harpoon_wrapper.add_item_by_name(name)
	table.remove(closed_buffer_stack, #closed_buffer_stack)
end

local function on_list_change()
	local removed_buffers = harpoon_wrapper.find_removed_buffers(state.buffers)
	for _, bufnr in ipairs(removed_buffers) do
		local name = vim.api.nvim_buf_get_name(bufnr)
		if name ~= nil then
			table.insert(closed_buffer_stack, name)
		end
	end
	update_state()
end

--- Adds bufnr to harpoon list and bufferline
---@param bufnr integer
function state.pin_tab(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		harpoon_wrapper.add_item(bufnr)
	end
end

local function on_toggle_enabled(is_enabled)
	barpoon_enabled = is_enabled
	if not config.settings.open_tab_for_current_buffer then
		return
	end
	if is_enabled then
		vim.api.nvim_create_autocmd({
			"BufEnter",
			"BufWritePost",
		}, {
			callback = vim.schedule_wrap(function(opts)
				if opts.buf ~= nil and opts.buf ~= state.temp_bufnr then
					update_temp_tab(opts.buf)
				end
			end),
			group = augroup,
		})
	else
		vim.schedule_wrap(function()
			vim.api.nvim_clear_autocmds({ group = augroup })
		end)
	end
end

local harpoon_listeners = {
	ADD = update_state,
	REMOVE = on_remove_item,
	REPLACE = update_state,
	REORDER = update_state,
	LIST_CHANGE = on_list_change,
	UI_CREATE = update_state,
	SETUP_CALLED = update_state,
}

function state.setup()
	harpoon_wrapper.add_listeners(harpoon_listeners)
	on_toggle_enabled(true)
	update_state()
end

function state.disable()
	vim.schedule(function()
		vim.api.nvim_clear_autocmds({ group = augroup })
		state.temp_bufnr = -1
		state.buffers = {}

		harpoon_wrapper.clear_listeners()
		on_toggle_enabled(false)
	end)
end

function state.enable()
	state.setup()
end

return state
