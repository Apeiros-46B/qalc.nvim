-- handle buffer creation, attach/detach, and job submission
local ns_track = vim.api.nvim_create_namespace('qalc_track')
local cfg = require('qalc.config').cfg
local bridge = require('qalc.bridge')

local M = {}

-- mapping of bufnr -> depgraph
local attached_bufs = {}
-- mapping of bufnr -> bool, all buffers in this set should be detached from asap
local detach_queue = {}

local cur_active_buf = nil

-- bufnr -> { min_lnum, max_lnum }
local dirty_bufs = {}
local flush_scheduled = false

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

	-- referenced in on_lines to detach itself
	detach_queue[bufnr] = true

	require('qalc.output').clear_all(bufnr)
end
local function detach(bufnr)
	detach_queue[bufnr] = nil
	attached_bufs[bufnr] = nil
	dirty_bufs[bufnr] = nil
end

-- attach
function M.is_attached(bufnr)
	return attached_bufs[bufnr] ~= nil
end
local function flush_dirty_bufs()
	-- runs when event loop is idle
	flush_scheduled = false

	for bufnr, state in pairs(dirty_bufs) do
		if vim.api.nvim_buf_is_valid(bufnr) and M.is_attached(bufnr) then
			local total_lines = vim.api.nvim_buf_line_count(bufnr)

			local min_lnum = state.min_lnum
			local max_lnum = math.min(state.max_lnum, total_lines)

			-- fetch the fully settled text
			local lines = vim.api.nvim_buf_get_lines(bufnr, min_lnum, max_lnum, false)
			for i, text in ipairs(lines) do
				local row = min_lnum + i - 1
				local marks = vim.api.nvim_buf_get_extmarks(
					bufnr, ns_track, {row, 0}, {row, -1}, {}
				)

				if #marks == 0 then
					local new_id = vim.api.nvim_buf_set_extmark(bufnr, ns_track, row, 0, {})
					-- new mark, cannot possibly be a changed state
					-- therefore we check against whitespace to avoid sending empty jobs to C++
					if text:match('%S') then
						bridge.submit(bridge.JobType.PARSE_LINE, bufnr, new_id, text)
					end
				else
					local active_mark = marks[1][1]
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_mark, text)
					for j = 2, #marks do
						bridge.submit(bridge.JobType.PARSE_LINE, bufnr, marks[j][1], '')
					end
				end
			end

			-- marks have been pushed to EOF, mark them as blank
			local eof_marks = vim.api.nvim_buf_get_extmarks(
				bufnr, ns_track, {total_lines, 0}, {-1, -1}, {}
			)
			for _, mark in ipairs(eof_marks) do
				bridge.submit(bridge.JobType.PARSE_LINE, bufnr, mark[1], '')
			end
		end
	end

	dirty_bufs = {}
end

local function on_lines(_, bufnr, _, first_lnum, _, new_last_lnum)
	if detach_queue[bufnr] then
		detach(bufnr)
		return true -- detaches the on_lines
	end

	-- accumulate the affected ranges during the edit block
	local state = dirty_bufs[bufnr] or { min_lnum = first_lnum, max_lnum = new_last_lnum }
	state.min = math.min(state.min_lnum, first_lnum)
	state.max = math.max(state.max_lnum, new_last_lnum)
	dirty_bufs[bufnr] = state

	-- if this is the first edit of the block, schedule the flush
	if not flush_scheduled then
		flush_scheduled = true
		vim.schedule(flush_dirty_bufs)
	end
end

function M.attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if M.is_attached(bufnr) then return true end

	detach_queue[bufnr] = nil
	vim.fn.bufload(bufnr)

	attached_bufs[bufnr] = require('qalc.depgraph').new(bufnr)

	-- manual update on all existing lines (place the initial extmarks)
	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	on_lines(nil, bufnr, nil, 0, total_lines, total_lines)

	vim.api.nvim_buf_attach(bufnr, false, { on_lines = on_lines })
	vim.bo.filetype = 'qalc'
end

-- update C++-side state in the newly focused buffer
function M.focus_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) or cur_active_buf == bufnr then return end
	cur_active_buf = bufnr

	-- wipe local variables from other buffers
	bridge.submit(bridge.JobType.CLEAR_SYMS, bufnr, -1, '')

	-- fetch all marks in top-down order (this includes ghosts)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_track, 0, -1, {})
	local seen_lines = {}

	-- evaluate all lines in order
	for _, mark in ipairs(marks) do
		local extmark = mark[1]
		local lnum = mark[2]

		-- if we haven't seen this line yet, this is the active mark and not a ghost. otherwise,
		-- it's a ghost and we just ignore it to prevent duplicate eval calls on the same line
		if not seen_lines[lnum] then
			seen_lines[lnum] = true
			local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ''

			-- direct eval, don't go through the depgraph
			-- the depgraph state is already maintained properly, the only reason we need to do
			-- this is to "synchronize" the libqalculate Calculator state with the new buffer
			bridge.submit(bridge.JobType.EVAL_LINE, bufnr, extmark, text)
		end
	end
end

return M
