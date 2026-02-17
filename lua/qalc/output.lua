-- display Qalculate output to the user through a decoration provider
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

-- bufnr -> tracking_extmark_id -> diags array
local diag_cache = {}

-- bufnr -> tracking_extmark_id -> string
local result_cache = {}

-- flush diagnostics to neovim for a specific buf
local function flush_diags(bufnr)
	if not diag_cache[bufnr] then return end

	local all_diags = {}
	for tracking_mark_id, diags in pairs(diag_cache[bufnr]) do
		-- find current location of this diagnostic
		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, util.ns_track, tracking_mark_id, {})

		if #pos > 0 then
			local lnum = pos[1]
			for _, d in ipairs(diags) do
				local diag_copy = vim.deepcopy(d)
				diag_copy.bufnr = bufnr
				diag_copy.lnum = lnum
				diag_copy.col = 0
				all_diags[#all_diags+1] = diag_copy
			end
		else
			-- extmark was deleted by user
			diag_cache[bufnr][tracking_mark_id] = nil
		end
	end

	vim.diagnostic.set(util.ns_ui, bufnr, all_diags)
end

-- clear one extmark from the cache
function M.clear(bufnr, tracking_mark)
	if result_cache[bufnr] then
		result_cache[bufnr][tracking_mark] = nil
	end

	if diag_cache[bufnr] and diag_cache[bufnr][tracking_mark] then
		diag_cache[bufnr][tracking_mark] = nil
		flush_diags(bufnr)
	end

	-- force repaint, which erases ephemeral text (see decoration provider below)
	vim.cmd('redraw!')
end

-- clear all extmarks
function M.clear_all(bufnr)
	result_cache[bufnr] = nil
	diag_cache[bufnr] = nil
	vim.diagnostic.set(util.ns_ui, bufnr, {})
	vim.cmd('redraw!')
end

-- update the cache for one extmark
function M.render(bufnr, tracking_mark, output, diags)
	result_cache[bufnr] = result_cache[bufnr] or {}

	if output and output ~= '' then
		result_cache[bufnr][tracking_mark] = output
	else
		result_cache[bufnr][tracking_mark] = nil
	end

	diag_cache[bufnr] = diag_cache[bufnr] or {}
	if diags and #diags > 0 then
		diag_cache[bufnr][tracking_mark] = diags
	else
		diag_cache[bufnr][tracking_mark] = nil
	end

	flush_diags(bufnr)
	vim.cmd('redraw!')
end

-- yank result at current line in the given buf into the given register
function M.yank_result(register)
	local bufnr = vim.fn.bufnr()
	local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 -- :h api-indexing

	local tracking_marks = vim.api.nvim_buf_get_extmarks(
		bufnr, util.ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
	)
	if tracking_marks == nil or #tracking_marks == 0 then
		vim.notify('qalc: Unable to find extmark on current line')
		return
	end

	local tracking_mark = tracking_marks[1][1]
	if not result_cache[bufnr] then return end

	local val = result_cache[bufnr][tracking_mark]
	if val == nil or val == '' then
		vim.notify('qalc: No result on current line')
		return
	end

	vim.fn.setreg(register, val)
end

-- use ephemeral extmarks so we don't have to deal with them getting moved around
vim.api.nvim_set_decoration_provider(util.ns_ui, {
	on_win = function(_, _, bufnr, _, _)
		if not result_cache[bufnr] then
			return false
		end
		return true
	end,

	on_range = function(_, _, bufnr, start_lnum, _, end_lnum, _)
		-- exclude end
		for lnum = start_lnum, end_lnum - 1 do
			-- find active tracking mark
			local tracking_marks = vim.api.nvim_buf_get_extmarks(
				bufnr, util.ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
			)

			if #tracking_marks > 0 then
				local tracking_mark = tracking_marks[1][1]
				local text = result_cache[bufnr][tracking_mark]

				if text then
					local virt_text = {}
					if cfg.display.sign ~= false then
						virt_text[#virt_text+1] = { cfg.display.sign .. ' ', cfg._sign_hl }
					end
					virt_text[#virt_text+1] = { text, cfg._result_hl }
					vim.api.nvim_buf_set_extmark(bufnr, util.ns_ui, lnum, 0, {
						ephemeral = true,
						virt_text = virt_text,
						virt_text_pos = 'eol',
						hl_mode = 'combine',
					})
				end
			end
		end
	end
})

return M
