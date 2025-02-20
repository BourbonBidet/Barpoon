local M = {}

local lazy = require("barpoon.lazy")

local config = lazy.require("barpoon.config") ---@module "barpoon.config"
local state = lazy.require("barpoon.state") ---@module "barpoon.state"
local events = lazy.require("barpoon.events") ---@module "barpoon.events"
local utils = lazy.require("barpoon.utils") ---@module "barpoon.utils"
local bar_base = lazy.require("barpoon.bar") ---@module "barpoon.bar"

---@type BarpoonBar
local bar = nil

local enabled = false

local bufferline_plugins = {
	bufferline = function()
		return lazy.require("barpoon.bufferline.bar")
	end,
	barbar = function()
		return lazy.require("barpoon.barbar.bar")
	end,
}

local function on_update_state()
	if bar ~= nil then
		bar.update()
	end
end

local function enable_barpoon()
	enabled = true
	state.enable()
	events.add_listener(state.events.ON_UPDATE_STATE, on_update_state)

	if bar ~= nil then
		events.add_listener(bar_base.events.ON_SORT_TABS, state.sort_tabs)
		events.add_listener(bar_base.events.ON_MOVE_TAB, state.move_tab)
		events.add_listener(bar_base.events.ON_CLOSE_TAB, state.close_tab)
		events.add_listener(bar_base.events.ON_PIN_TAB, state.pin_tab)

		if config.settings.plugin == "barbar" then
			events.add_listener(bar_base.events.ON_RESTORE_BUFFER, state.restore_buffer)
		end

		bar.enable()
	end
end

local function disable_barpoon()
	enabled = false
	events.clear_listeners()
	state.disable()
	if bar ~= nil then
		bar.disable()
	end
end

local function load_bufferline_plugin()
	if config.settings.plugin ~= nil and package.loaded[config.settings.plugin] ~= nil then
		bar = bufferline_plugins[config.settings.plugin]()
		return
	end
	for name, plugin_require in pairs(bufferline_plugins) do
		if package.loaded[name] ~= nil then
			bar = plugin_require()
		end
	end
end

local function setup_user_commands()
	vim.api.nvim_create_user_command("BarpoonToggle", function()
		if enabled then
			disable_barpoon()
			utils.notify("Barpoon hidden.", vim.log.levels.INFO)
		else
			enable_barpoon()
		end
	end, { desc = "Hide Barpoon bufferline" })
	vim.api.nvim_create_user_command("BarpoonHide", function()
		if enabled then
			disable_barpoon()
			utils.notify("Barpoon hidden.", vim.log.levels.INFO)
		end
	end, { desc = "Hide Barpoon bufferline" })
	vim.api.nvim_create_user_command("BarpoonShow", function()
		if not enabled then
			enable_barpoon()
		end
	end, { desc = "Show Barpoon bufferline" })
	vim.api.nvim_create_user_command("BarpoonRestoreTab", function()
		state.restore_buffer()
	end, { desc = "Restore the last closed tab and add it to the Harpoon list" })
end

---Main setup function for Barpoon
---@param opts BarpoonConfig
function M.setup(opts)
	local conf = opts or {}
	config.setup(conf)
	load_bufferline_plugin()
	state.setup()
	enable_barpoon()
	setup_user_commands()
end

return M
