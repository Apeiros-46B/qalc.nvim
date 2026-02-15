-- handle buffer creation, attach/detach, and yanking result
local ns_track = vim.api.nvim_create_namespace('qalc_track')
local cfg = require('qalc.config').cfg
local bridge = require('qalc.bridge')

local M = {}

-- mapping of bufnr -> depgraph
local attached_bufs = {}
-- mapping of bufnr -> bool, all buffers in this set should be detached from
local detach_queue = {}

local cur_active_buf = nil

bridge.register_callback(attached_bufs)

-- create buffer
function M.new_buf(name)
	local cmd = 'enew'

	if name ~= '' and name ~= nil then
		cmd = 'e ' .. name
	elseif cfg.bufname ~= '' then
		cmd = 'e ' .. cfg.bufname
	end

	vim.cmd(cmd)
end

-- detach
function M.queue_detach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- referenced in nvim_buf_attach callback to actually detach the callback
	detach_queue[bufnr] = true

	require('qalc.output').clear(bufnr)
end
local function detach(bufnr)
	detach_queue[bufnr] = nil
	attached_bufs[bufnr] = nil
end

-- attach
function M.is_attached(bufnr)
	return attached_bufs[bufnr] ~= nil
end
function M.attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- don't attach twice
	if M.is_attached(bufnr) then return true end

	-- we are attaching; don't detach
	detach_queue[bufnr] = nil
	vim.fn.bufload(bufnr)

	-- TODO: the extmark handling in this is severely broken in some undo/redo edge cases
	-- it can leave lines without extmarks, or pile multiple extmarks on one line
	local function cb(_, _, _, first, last, new_last)
		if detach_queue[bufnr] then
			detach(bufnr)
			return true -- actually detaches the callback
		end

		local total_lines = vim.api.nvim_buf_line_count(bufnr)

		-- clear extmarks that are outside of the buffer
		local eof_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_track, {total_lines, 0}, {-1, -1}, {})
		for _, mark in ipairs(eof_marks) do
			vim.api.nvim_buf_del_extmark(bufnr, ns_track, mark[1])
			require('qalc.output').clear(bufnr, mark[1])
		end

		-- determine which lines have been modified
		local mod_start = first
		local mod_end = math.min(math.max(new_last, first + 1), total_lines)

		-- process extmarks on every modified line
		local lines = vim.api.nvim_buf_get_lines(bufnr, mod_start, mod_end, false)
		for i, text in ipairs(lines) do
			local row = mod_start + i - 1
			local row_marks = vim.api.nvim_buf_get_extmarks(
				bufnr, ns_track,
				{row, 0}, {row, -1},
				{}
			)

			local active_extmark_id
			if #row_marks > 0 then -- a mark exists already
				-- always use the first tracking mark
				active_extmark_id = row_marks[1][1]

				-- garbage collect duplicate extmarks
				if #row_marks > 1 then
					for j = 2, #row_marks do
						local ghost_id = row_marks[j][1]
						vim.api.nvim_buf_del_extmark(bufnr, ns_track, ghost_id)
					end
				end

				if text:match("%S") then
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_extmark_id, text)
				else
					-- send empty parse job so dep graph is updated with symbol deletes
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_extmark_id, "")
					require('qalc.output').clear(bufnr, active_extmark_id)
				end
			else -- there is no existing mark
				-- we need vim.schedule so the extmarks are applied after any pending undo/redo or
				-- other editing transaction, which prevents strange issues
				vim.schedule(function()
					if not vim.api.nvim_buf_is_valid(bufnr) then return end
					if row >= vim.api.nvim_buf_line_count(bufnr) then return end

					-- line without extmark, make a new one asap
					-- we need right_gravity to prevent extmarks from being pushed outside of
					-- the buffer in some cases
					active_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_track, row, 0, {
						right_gravity = false
					})

					local current_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

					if current_text:match("%S") then
						bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_extmark_id, current_text)
					else
						bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_extmark_id, "")
						require('qalc.output').clear(bufnr, active_extmark_id)
					end
				end)
			end
		end
	end

	attached_bufs[bufnr] = require('qalc.depgraph').new(bufnr)

	-- manual update on all existing lines (place the initial extmarks)
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	cb(nil, bufnr, nil, 0, total_lines, total_lines)

	-- attach listener
	vim.api.nvim_buf_attach(bufnr, false, { on_lines = cb })
	vim.bo.filetype = 'qalc'
end

-- update C++-side state in the newly focused buffer
function M.focus_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) then
		return
	end
	if cur_active_buf == bufnr then
		return
	end
	cur_active_buf = bufnr

	-- wipe local variables from other buffers
	bridge.submit(bridge.JobType.CLEAR_SYMS, bufnr, -1, "")

	-- evaluate all lines in top to bottom order
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_track, 0, -1, {})
	for _, mark in ipairs(marks) do
		local extmark_id = mark[1]
		local lnum = mark[2]
		local lines = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)
		local text = lines[1] or ""
		if text:match("%S") then
			-- direct eval, don't go through the depgraph
			bridge.submit(bridge.JobType.EVAL_LINE, bufnr, extmark_id, text)
		end
	end
end

-- TODO: function to yank results from current line

return M
