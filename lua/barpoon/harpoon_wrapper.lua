local lazy = require("barpoon.lazy")
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"
local harpoon = lazy.require("harpoon") or nil ---@module "harpoon"
local h_config = lazy.require("harpoon.config") ---@module "harpoon.config"
local Path = require("plenary.path")

local extensions = nil
extensions = lazy.require("harpoon.extensions") or nil ---@module "harpoon.extensions"

local harpoon_wrapper = {}

local function create_list_item(name)
	local path = Path:new(name)
		:make_relative(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()), h_config.get_root_dir)
	name = name or path

	local bufnr = vim.fn.bufnr(name, false)

	local pos = { 1, 0 }
	if bufnr ~= -1 then
		pos = vim.api.nvim_win_get_cursor(0)
	end

	return {
		value = name,
		context = {
			row = pos[1],
			col = pos[2],
		},
	}
end

function harpoon_wrapper.add_listeners(callbacks)
	extensions.extensions:add_listener(callbacks)
end

function harpoon_wrapper.clear_listeners()
	extensions.extensions:clear_listeners()
end

function harpoon_wrapper.get_items()
	local list = harpoon:list()
	return list.items
end

function harpoon_wrapper.add_item(bufnr)
	vim.api.nvim_set_current_buf(bufnr)
	harpoon:list():add()
end

function harpoon_wrapper.add_item_by_name(name)
	local bufnr = vim.fn.bufnr(utils.to_exact_name(name))
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(name)
	end
	vim.api.nvim_set_current_buf(bufnr)
	harpoon:list():add()
end

function harpoon_wrapper.sort_items(reference_buffers)
	local new_list = {}
	local list = harpoon_wrapper.get_items()
	for _, bufnr in ipairs(reference_buffers) do
		for _, item in ipairs(list) do
			local item_bufnr = vim.fn.bufnr(utils.to_exact_name(item.value))
			if bufnr ~= -1 and bufnr == item_bufnr then
				table.insert(new_list, item)
				break
			end
		end
	end
	harpoon:list().items = new_list
	extensions.extensions:emit(extensions.event_names.LIST_CHANGE)
end

function harpoon_wrapper.move_item(start_index, end_index, emit_event)
	emit_event = emit_event or true
	local harpoon_list = harpoon:list()
	local item = harpoon_list:get(start_index)
	if item ~= nil then
		table.remove(harpoon_list.items, start_index)
		table.insert(harpoon_list.items, end_index, item)

		if emit_event then
			extensions.extensions:emit(extensions.event_names.LIST_CHANGE)
		end
	end
end

function harpoon_wrapper.remove_item_by_name(name)
	local h_list = harpoon:list()
	local item, index = h_list:get_by_value(name)
	h_list:remove_at(index)
end

function harpoon_wrapper.remove_items_by_name(names_list)
	for _, name in ipairs(names_list) do
		harpoon_wrapper.remove_item_by_name(name)
	end
end

function harpoon_wrapper.remove_item_by_bufnr(bufnr)
	local harpoon_list = harpoon:list()
	for i, v in ipairs(harpoon_list.items) do
		local item_bufnr = vim.fn.bufnr(utils.to_exact_name(v.value))
		if item_bufnr == bufnr and bufnr ~= -1 then
			table.remove(harpoon_list.items, i)
			extensions.extensions:emit(extensions.event_names.REMOVE, { list = harpoon_list, item = v, idx = i })
			return v
		end
	end
	return nil
end

function harpoon_wrapper.find_removed_buffers(bufnr_list)
	local harpoon_list = harpoon:list()
	local removed_buffers = {}
	if #bufnr_list == #harpoon_list.items then
		return removed_buffers
	end
	for _, bufnr in ipairs(bufnr_list) do
		local found = false
		for _, item in ipairs(harpoon_list.items) do
			local item_bufnr = vim.fn.bufnr(utils.to_exact_name(item.value))
			if item_bufnr == bufnr and item_bufnr ~= -1 then
				found = true
			end
			if found then
				break
			end
		end
		if not found then
			table.insert(removed_buffers, 1, bufnr)
		end
	end
	return removed_buffers
end

function harpoon_wrapper._set_dummy(new_harpoon, new_extensions)
	extensions = new_extensions
	harpoon = new_harpoon
end

return harpoon_wrapper
