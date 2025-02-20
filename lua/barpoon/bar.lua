---@class BarpoonBar
---@field update fun() : nil
---@field enable fun() : nil
---@field disable fun() : nil
local BarpoonBar = {}

local error_message =
	"No bufferline plugin found. Ensure you have a supported bufferline plugin installed and everything is configured correctly"

function BarpoonBar.update()
	print(error_message)
end

function BarpoonBar.enable()
	print(error_message)
end

function BarpoonBar.disable()
	print(error_message)
end

BarpoonBar.events = {
	ON_CLOSE_TAB = "on_close_tab",
	ON_MOVE_TAB = "on_move_tab",
	ON_RESTORE_BUFFER = "on_restore_buffer",
	ON_TOGGLE_ENABLED = "on_toggle_enabled",
	ON_SORT_TABS = "on_sort_tabs",
	ON_PIN_TAB = "on_pin_tab",
	ON_TABS_CHANGED = "on_tabs_changed",
}

return BarpoonBar
