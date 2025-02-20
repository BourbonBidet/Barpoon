local Path = require("plenary.path")

local utils = {}

function utils.to_exact_name(value)
	return "^" .. value .. "$"
end

function utils.index_of(tbl, t)
	for i, value in ipairs(tbl) do
		if value == t then
			return i
		end
	end
	return nil
end

function utils.notify(msg, level)
	vim.notify(msg, level, { title = "Barpoon" })
end

function utils.delete_buffer(bufnr)
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			local cmd = "bdelete! %d"
			vim.cmd(string.format(cmd, bufnr))
		end
	end)
end

function utils.command(name, cmd, opts)
	vim.api.nvim_create_user_command(name, cmd, opts or {})
end

return utils
