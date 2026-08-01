local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

vim.opt.runtimepath:prepend(root)
vim.cmd('runtime plugin/qalc.lua')

local M = { root = root }

function M.wait_for(predicate, message, timeout)
	assert(vim.wait(timeout or 4000, predicate, 10), message)
end

function M.attach_lines(lines)
	vim.cmd.enew()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.cmd.QalcAttach()

	local bufnr = vim.api.nvim_get_current_buf()
	M.wait_for(function()
		local graph = require('qalc.buffer').get_graph(bufnr)
		return graph and graph.is_initializing == false
	end, 'buffer did not finish initialization')

	return bufnr
end

function M.result_at(row, expected)
	vim.fn.setreg('q', '')
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	return vim.wait(3000, function()
		vim.cmd('silent! QalcYank q')
		return vim.fn.getreg('q') == expected
	end, 10)
end

function M.diagnostics(bufnr)
	return vim.diagnostic.get(bufnr, { namespace = require('qalc.util').ns_ui })
end

return M
