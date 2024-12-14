-- display Qalculate output to the user through virtual text and diagnostics
local ns = vim.api.nvim_create_namespace('qalc')
local cfg = require('qalc.config').cfg

local function clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	vim.diagnostic.reset(ns, bufnr)
end

local function render(bufnr, result, first)
	clear(bufnr)

	local sign = nil
	if cfg.display.sign ~= false then
		sign = { cfg.display.sign .. ' ', cfg.display.highlights.sign }
	end

	for lnum, value in pairs(result.values) do
		vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
			virt_text = {
				sign,
				{ value, cfg.display.highlights.result },
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
