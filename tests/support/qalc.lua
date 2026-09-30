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
		return require('qalc.buffer').is_ready(bufnr)
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

function M.diagnostics_at(bufnr, row)
	local matches = {}
	for _, diag in ipairs(M.diagnostics(bufnr)) do
		if diag.lnum == row - 1 then
			matches[#matches+1] = diag
		end
	end
	return matches
end

function M.has_diagnostic(bufnr, row, message)
	for _, diag in ipairs(M.diagnostics_at(bufnr, row)) do
		if diag.message:find(message, 1, true) then
			return true
		end
	end
	return false
end

function M.graph_diagnostics(bufnr)
	local matches = {}
	for _, diag in ipairs(M.diagnostics(bufnr)) do
		if diag.message:find('Duplicate definition', 1, true)
			or diag.message:find('Reference cycle', 1, true)
		then
			matches[#matches+1] = diag
		end
	end
	return matches
end

return M
