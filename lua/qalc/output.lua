-- display Qalculate output to the user through virtual text and diagnostics
-- we distinguish between "tracking marks" and "UI marks" because tracking marks must be
-- persistent while UI marks may be randomly destroyed and re-created (for fancy effects)
local ns_track = vim.api.nvim_create_namespace('qalc_track')
local ns_ui = vim.api.nvim_create_namespace('qalc_ui')
local cfg = require('qalc.config').cfg

local M = {}

-- bufnr -> tracking_extmark_id -> [ diag1, diag2, ... ]
local diag_cache = {}

-- bufnr -> tracking_extmark_id -> string
local result_cache = {}

-- bufnr -> tracking_extmark_id -> uv_handle_t
local flash_timers = {}

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
				all_diags[#all_diags+1] = diag_copy
			end
		else
			-- extmark was deleted by user
			diag_cache[bufnr][tracking_mark_id] = nil
		end
	end

	vim.diagnostic.set(ns_ui, bufnr, all_diags)
end

-- clear one extmark
-- TODO: at all call sites, instead of clearing eagerly when job is submitted, clear
-- right before the new result comes in. this way we avoid a blank flicker (because of the
-- absence of the stale value) and instead use the flash to show when the new value arrives
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

-- clear all extmarks
function M.clear_all(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns_ui, 0, -1)
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
			virt_text[#virt_text+1] = { cfg.display.sign .. ' ', cfg._sign_hl }
		end
		if cfg.display.flash.enable then
			virt_text[#virt_text+1] = { output, cfg._flash_hl }
		else
			virt_text[#virt_text+1] = { output, cfg._result_hl }
		end

		-- TODO: there are some final bugs with UI marks piling up or being deleted on redo
		local ui_mark = vim.api.nvim_buf_set_extmark(bufnr, ns_ui, row, 0, {
			virt_text = virt_text,
			virt_text_pos = 'eol',
			hl_mode = 'combine',

			-- do not track ephemeral UI marks in undo/redo
			invalidate = true,
			undo_restore = false,
		})

		if cfg.display.flash.enable then
			flash_timers[bufnr] = flash_timers[bufnr] or {}

			-- cancel flash timer for this mark
			if flash_timers[bufnr][tracking_mark] ~= nil then
				flash_timers[bufnr][tracking_mark]:stop()
				if not flash_timers[bufnr][tracking_mark]:is_closing() then
					flash_timers[bufnr][tracking_mark]:close()
				end
				flash_timers[bufnr][tracking_mark] = nil
			end

			-- start timer to revert to the normal highlight group
			local timer = vim.uv.new_timer()

			if timer ~= nil then
				flash_timers[bufnr][tracking_mark] = timer
				timer:start(cfg.display.flash.duration * 1000, 0, vim.schedule_wrap(function()
					flash_timers[bufnr][tracking_mark] = nil

					if not timer:is_closing() then timer:close() end
					if not vim.api.nvim_buf_is_valid(bufnr) then return end

					local cur_pos = vim.api.nvim_buf_get_extmark_by_id(
						bufnr,
						ns_track,
						tracking_mark,
						{}
					)
					if cur_pos and #cur_pos > 0 then
						local cur_lnum = cur_pos[1]
						virt_text[#virt_text][2] = cfg._result_hl
						vim.api.nvim_buf_set_extmark(bufnr, ns_ui, cur_lnum, 0, {
							id = ui_mark,
							virt_text = virt_text,
							virt_text_pos = 'eol',
							hl_mode = 'combine',
						})
					end
				end))
			end
		end

		result_cache[bufnr] = result_cache[bufnr] or {}
		result_cache[bufnr][tracking_mark] = output
	else
		result_cache[bufnr] = result_cache[bufnr] or {}
		result_cache[bufnr][tracking_mark] = nil
	end

	diag_cache[bufnr] = diag_cache[bufnr] or {}
	if diags and #diags > 0 then
		diag_cache[bufnr][tracking_mark] = diags
	else
		diag_cache[bufnr][tracking_mark] = nil
	end
	flush_diags(bufnr)
end

-- yank result at current line in the given buf into the given register
function M.yank_result(register)
	local bufnr = vim.fn.bufnr()
	local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 -- :h api-indexing

	local tracking_marks = vim.api.nvim_buf_get_extmarks(
		bufnr, ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
	)
	if tracking_marks == nil or #tracking_marks == 0 then
		vim.notify('qalc: Unable to find extmark on current line')
		return
	end

	local tracking_mark = tracking_marks[1][1]
	local val = result_cache[bufnr][tracking_mark]
	if val == nil or val == '' then
		vim.notify('qalc: No result on current line')
		return
	end

	vim.fn.setreg(register, val)
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
