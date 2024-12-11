-- display Qalculate output to the user through virtual text and diagnostics
local ns = vim.api.nvim_create_namespace('qalc')
local util = require('qalc.util')

local all_results = {}

local function clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	vim.diagnostic.reset(ns, bufnr)
end

-- TODO: see todo at bridge.lua/eval()
local function render(bufnr, result, first_lnum)
	clear(bufnr)
	for lnum, value in pairs(result.values) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
			-- TODO obey config
			virt_text = {
				{ '= ', '@conceal' },
				{ value, '@string' },
			},
			virt_text_pos = 'eol',
			hl_mode = 'combine',
		})
	end
	vim.diagnostic.set(ns, bufnr, result.diagnostics)
end

return {
	clear  = clear,
	render = render,
}
