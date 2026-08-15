-- display Qalculate output to the user through a decoration provider
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

-- bufnr -> tracking_extmark_id -> array[diagnostic]
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
			local seen_msgs = {}

			for _, diag in ipairs(diags) do
				if not seen_msgs[diag.message] then
					seen_msgs[diag.message] = true
					local diag_copy = vim.deepcopy(diag)
					diag_copy.bufnr = bufnr
					diag_copy.lnum = lnum
					diag_copy.col = 0
					all_diags[#all_diags+1] = diag_copy
				end
			end
		else
			-- extmark was deleted by user
			diag_cache[bufnr][tracking_mark_id] = nil
		end
	end

	vim.diagnostic.set(util.ns_ui, bufnr, all_diags)
end

-- clear all extmarks
function M.clear_all(bufnr)
	result_cache[bufnr] = nil
	diag_cache[bufnr] = nil

	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.diagnostic.set(util.ns_ui, bufnr, {})
		vim.cmd('redraw!')
	end
end

local function should_show_result(bufnr, tracking_mark, output)
	local should_show = false

	-- check output against input to avoid redundant outputs like "x = 5 = 5"
	if output and output ~= '' then
		should_show = true

		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, util.ns_track, tracking_mark, {})
		if #pos > 0 then
			local lnum = pos[1]
			local lines = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)

			if #lines > 0 then
				local line = lines[1]
				-- escape special chars for lua pattern matching
				local escaped_out = output:gsub('([^%w])', '%%%1')

				if line:gsub('%s+', '') == output:gsub('%s+', '') then
					-- constant "5 = 5"
					should_show = false
				elseif line:match('=%s*' .. escaped_out .. '%s*$') then
					-- assignment "x = 5 = 5"
					should_show = false
				end
			end
		end
	end
	return should_show
end

function M.render_batch(bufnr, updates, no_redraw)
	if #updates == 0 then return end
	result_cache[bufnr] = result_cache[bufnr] or {}
	diag_cache[bufnr] = diag_cache[bufnr] or {}

	for _, update in ipairs(updates) do
		local tracking_mark = update.mark
		if update.placeholder and cfg.display.placeholder then
			result_cache[bufnr][tracking_mark] = cfg.display.placeholder
		elseif should_show_result(bufnr, tracking_mark, update.output) then
			result_cache[bufnr][tracking_mark] = update.output
		else
			result_cache[bufnr][tracking_mark] = nil
		end

		local diags = update.diags
		if diags and #diags > 0 then
			diag_cache[bufnr][tracking_mark] = diags
		else
			diag_cache[bufnr][tracking_mark] = nil
		end
	end

	flush_diags(bufnr)
	if not no_redraw then vim.cmd('redraw!') end
end

-- clear one extmark from the cache
-- if show_placeholder is true, show a placeholder until the mark is updated again
function M.clear(bufnr, tracking_mark, show_placeholder, no_redraw)
	M.render_batch(bufnr, {{
		mark = tracking_mark,
		diags = {},
		placeholder = show_placeholder,
	}}, no_redraw)
end

-- update the cache for one extmark
function M.render(bufnr, tracking_mark, output, diags)
	M.render_batch(bufnr, {{
		mark = tracking_mark,
		output = output,
		diags = diags,
	}})
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
		if end_lnum <= start_lnum then return end

		local tracking_marks = vim.api.nvim_buf_get_extmarks(
			bufnr,
			util.ns_track,
			{start_lnum, 0},
			{end_lnum - 1, -1},
			{}
		)
		local seen_rows = {}

		for _, mark in ipairs(tracking_marks) do
			local tracking_mark = mark[1]
			local lnum = mark[2]
			local text = result_cache[bufnr][tracking_mark]

			if not seen_rows[lnum] and text then
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

			seen_rows[lnum] = true
		end
	end
})

-- in case of ghost, clear the output and stale diagnostics
-- this is safe and will never drop the result for the active mark
util.connect_signal('result_cleared', M.clear)

util.connect_signal('diags_ready', function(bufnr, extmark, diags)
	M.render(bufnr, extmark, '', diags)
end)

return M
