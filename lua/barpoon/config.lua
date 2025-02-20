---@alias BufferlinePlugin
---| '"bufferline"'
---| '"barbar"'
---| nil

---@class BarpoonBufferlineConfig
---@field hide_threshold integer

---@class BarpoonBarbarConfig
---@field temp_tab_color string

---@class BarpoonConfig
---@field plugin BufferlinePlugin
---@field open_tab_for_current_buffer boolean
---@field show_pin_button_on_temp_tab boolean
---@field pin_icon string
---@field key_labels string | nil
---@field bufferline BarpoonBufferlineConfig
---@field barbar BarpoonBarbarConfig
local config = {}

config.settings = {}
config.defaults = {
	plugin = nil, -- nil | 'bufferline' | 'barbar' : The bufferline plugin to use, will automatically detect installed plugin if set to nil

	open_tab_for_current_buffer = true, -- Open a tab while viewing a buffer that's not harpooned, and then close it when leaving the buffer

	show_pin_button_on_temp_tab = true, -- Replace the close button with a pin button on the temp tab, to add it to harpoon list

	pin_icon = "󰐃", -- Icon used for the pin button  NOTE: This button will harpoon the tab, not the built-in pin feature from bufferline or barbar

	-- list of labels to correspond with your harpoon keymaps
	key_labels = nil, -- eg. 'hjkl;HJKL'

	--NOTE: config exlusive to bufferline.nvim
	bufferline = { -- Config options specific to bufferline.nvim

		hide_threshold = 0, -- Hide bufferline when less than or equal to hide_tab_amount. (Bufferline's default is 1, but for Barpoon it makes sense to show all Harpoon'd tabs)
		-- INFO: Must also set 'always_show_bufferline = false' and 'auto_toggle_bufferline = true' in your bufferline config
	},

	--NOTE: config exclusive to barbar.nvim
	barbar = {
		temp_tab_color = "#87d7af", -- Foregrond color for the temporary tab opened while viewing a file not in the harpoon list
	},
}

---@param user_config BarpoonConfig
function config.setup(user_config)
	user_config = user_config or {}
	config.settings = vim.tbl_deep_extend("force", config.defaults, user_config)
end

return config
