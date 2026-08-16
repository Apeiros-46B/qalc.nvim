-- display Qalculate output to the user through a decoration provider
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

local function flush_diags(state)
	if not vim.api.nvim_buf_is_valid(state.bufnr) then return end

	local all_diags = {}
	for row, stmt in ipairs(state.doc:records()) do
		local seen_messages = {}
		for _, diag in ipairs(stmt.diags or {}) do
			if not seen_messages[diag.message] then
				seen_messages[diag.message] = true
				local copy = vim.deepcopy(diag)
				copy.bufnr = state.bufnr
				copy.lnum = row - 1
				copy.col = 0
				all_diags[#all_diags+1] = copy
			end
		end
	end

	vim.diagnostic.set(util.ns_ui, state.bufnr, all_diags)
end

local function should_show_result(stmt, output)
	if not output or output == '' then return false end

	local line = stmt.text or ''
	local escaped_output = output:gsub('([^%w])', '%%%1')
	if line:gsub('%s+', '') == output:gsub('%s+', '') then
		return false
	end
	if line:match('=%s*' .. escaped_output .. '%s*$') then
		return false
	end
	return true
end

function M.refresh(state, no_redraw)
	flush_diags(state)
	if not no_redraw then vim.cmd('redraw!') end
end

-- apply a batch of display updates
function M.render_batch(state, updates, no_redraw)
	if #updates == 0 then return end

	for _, update in ipairs(updates) do
		local stmt = state.doc:get(update.stmt_id)
		if stmt then
			if update.placeholder and cfg.display.placeholder then
				stmt.result = cfg.display.placeholder
			elseif should_show_result(stmt, update.output) then
				stmt.result = update.output
			else
				stmt.result = nil
			end
			stmt.diags = update.diags or {}
		end
	end

	M.refresh(state, no_redraw)
end

function M.clear_all(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then return end
	vim.diagnostic.set(util.ns_ui, bufnr, {})
	vim.cmd('redraw!')
end

-- yank result at current line in the given buf into the given register
function M.yank_result(register)
	local bufnr = vim.api.nvim_get_current_buf()
	local state = require('qalc.buffer').get_state(bufnr)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local stmt = state and state.doc.lines[row]
	local result = stmt and stmt.result

	if not result or result == '' then
		vim.notify('qalc: No result on current line')
		return
	end
	vim.fn.setreg(register, result)
end

-- use ephemeral extmarks so display state stays independent of buffer edits
vim.api.nvim_set_decoration_provider(util.ns_ui, {
	on_win = function(_, _, bufnr, _, _)
		return require('qalc.buffer').get_state(bufnr) ~= nil
	end,

	on_range = function(_, _, bufnr, start_lnum, _, end_lnum, _)
		if end_lnum <= start_lnum then return end

		local state = require('qalc.buffer').get_state(bufnr)
		if not state then return end

		local last_lnum = math.min(end_lnum - 1, #state.doc.lines - 1)
		for lnum = start_lnum, last_lnum do
			local stmt = state.doc.lines[lnum + 1]
			local text = stmt and stmt.result
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
	end,
})

return M
