-- display Qalculate output to the user through virtual text and diagnostics
local ns_track = vim.api.nvim_create_namespace('qalc_track')
local ns_ui = vim.api.nvim_create_namespace('qalc_ui')
local cfg = require('qalc.config').cfg

local M = {}

-- bufnr -> tracking_extmark_id -> [ diag1, diag2, ... ]
local diag_cache = {}

-- flush diagnostics to neovim for a specific buf
local function flush_diags(bufnr)
	if not diag_cache[bufnr] then return end

	local all_diags = {}
	for tracking_mark_id, diags in pairs(diag_cache[bufnr]) do
		-- find current location of this diagnostic
		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_track, tracking_mark_id, {})

		if #pos > 0 then
			local lnum = pos[1]
			for _, d in ipairs(diags) do
				local diag_copy = vim.deepcopy(d)
				diag_copy.bufnr = bufnr
				diag_copy.lnum = lnum
				diag_copy.col = 0
				table.insert(all_diags, diag_copy)
			end
		else
			-- extmark was deleted by user
			diag_cache[bufnr][tracking_mark_id] = nil
		end
	end

	vim.diagnostic.set(ns_ui, bufnr, all_diags)
end

-- clear one extmark
function M.clear(bufnr, tracking_mark)
	local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_track, tracking_mark, {})
	if pos == nil or #pos == 0 then return end
	-- extmark no longer exists

	local lnum = pos[1]

	local ui_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_ui, {lnum, 0}, {lnum, -1}, {})
	for _, mark in ipairs(ui_marks) do
		vim.api.nvim_buf_del_extmark(bufnr, ns_ui, mark[1])
	end

	if diag_cache[bufnr] and diag_cache[bufnr][tracking_mark] then
		diag_cache[bufnr][tracking_mark] = nil
		flush_diags(bufnr)
	end
end

-- update one extmark
function M.render(bufnr, tracking_mark, output, diags)
	local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_track, tracking_mark, {})
	if pos == nil or #pos == 0 then
		return -- extmark no longer exists
	end

	local row = pos[1]
	M.clear(bufnr, tracking_mark)

	if output ~= nil and output ~= '' then
		local virt_text = {}

		if cfg.display.sign ~= false then
			virt_text[#virt_text+1] = { cfg.display.sign .. ' ', cfg.display.highlights.sign }
		end
		virt_text[#virt_text+1] = { output, cfg.display.highlights.result }

		vim.api.nvim_buf_set_extmark(bufnr, ns_ui, row, 0, {
			virt_text = virt_text,
			virt_text_pos = 'eol',
			hl_mode = 'combine',

			-- do not track ephemeral UI marks for undo/redo
			invalidate = true,
			undo_restore = false,
		})
	end

	diag_cache[bufnr] = diag_cache[bufnr] or {}
	if diags and #diags > 0 then
		diag_cache[bufnr][tracking_mark] = diags
	else
		diag_cache[bufnr][tracking_mark] = nil
	end
	flush_diags(bufnr)
end

return M

-- {{{ old code for flash effect
-- TODO: integrate this later and make it configurable
-- local uv = vim.loop
-- local api = vim.api
--
-- -- {{{ gradient
-- -- {{{ generator
-- local function gradient(steps, c1, c2)
--     local r1 = c1[1]
--     local g1 = c1[2]
--     local b1 = c1[3]
--
--     local r2 = c2[1]
--     local g2 = c2[2]
--     local b2 = c2[3]
--
--     local new = { string.format('#%02X%02X%02X', r1, g1, b1) }
--
--     for i = 0, steps do
--         local rdiff = i * ((r2 - r1) / steps)
--         local gdiff = i * ((g2 - g1) / steps)
--         local bdiff = i * ((b2 - b1) / steps)
--
--         new[#new+1] = string.format(
--             '#%02X%02X%02X',
--             r1 + rdiff,
--             g1 + gdiff,
--             b1 + bdiff
--         )
--     end
--
--     return new
-- end
-- -- }}}
--
-- local colors = gradient(255,
--     { 0xD3,0xC6,0xAA },
--     { 0x83,0xC0,0x92 }
-- )
-- -- }}}
--
-- -- {{{ timer
-- local set_hl = vim.schedule_wrap(function(color)
--     api.nvim_set_hl(0, '@string', { fg = color })
-- end)
--
-- local i = 1
--
-- local timer = uv.new_timer()
-- timer:start(0, 1, function()
--     if i == #colors then
--         timer:stop()
--         timer:close()
--     end
--
--     set_hl(colors[i])
--
--     i = i + 1
-- end)
-- return timer
-- -- }}}
-- }}}
