-- handle buffer creation, attach/detach, and job submission
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

-- mapping of bufnr -> depgraph
M.attached_bufs = {}
-- mapping of bufnr -> bool, all buffers in this set should be detached from asap
local detach_queue = {}

local cur_active_buf = nil

-- bufnr -> { min_lnum, max_lnum }
local dirty_bufs = {}
local flush_scheduled = false

-- create buffer
function M.new_buf(name)
	local cmd = 'enew'

	if name and name ~= '' then
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
	M.attached_bufs[bufnr] = nil
	dirty_bufs[bufnr] = nil
end

-- attach
function M.is_attached(bufnr)
	return M.attached_bufs[bufnr] ~= nil
end

local function flush_dirty_bufs()
	local bridge = require('qalc.bridge')

	-- runs when event loop is idle
	flush_scheduled = false

	for bufnr, state in pairs(dirty_bufs) do
		if vim.api.nvim_buf_is_valid(bufnr) and M.is_attached(bufnr) then
			local total_lines = vim.api.nvim_buf_line_count(bufnr)

			local min_lnum = state.min_lnum
			local max_lnum = math.min(math.max(state.max_lnum, min_lnum + 1), total_lines)

			-- fetch the fully settled text
			local lines = vim.api.nvim_buf_get_lines(bufnr, min_lnum, max_lnum, false)
			for i, text in ipairs(lines) do
				local row = min_lnum + i - 1
				local marks = vim.api.nvim_buf_get_extmarks(
					bufnr, util.ns_track, {row, 0}, {row, -1}, {}
				)

				if #marks == 0 then
					local new_id = vim.api.nvim_buf_set_extmark(bufnr, util.ns_track, row, 0, {})
					-- new mark, cannot possibly be a changed state
					-- therefore we check against whitespace to avoid sending empty jobs to C++
					if text:match('%S') then
						bridge.submit(util.JobType.PARSE_LINE, bufnr, new_id, text)
					end
				else
					local active_mark = marks[1][1]
					bridge.submit(util.JobType.PARSE_LINE, bufnr, active_mark, text)
					for j = 2, #marks do
						bridge.submit(util.JobType.PARSE_LINE, bufnr, marks[j][1], '')
					end
				end
			end

			-- marks have been pushed to EOF, mark them as blank
			local eof_marks = vim.api.nvim_buf_get_extmarks(
				bufnr, util.ns_track, {total_lines, 0}, {-1, -1}, {}
			)
			for _, mark in ipairs(eof_marks) do
				bridge.submit(util.JobType.PARSE_LINE, bufnr, mark[1], '')
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
	state.min_lnum = math.min(state.min_lnum, first_lnum)
	state.max_lnum = math.max(state.max_lnum, new_last_lnum)
	dirty_bufs[bufnr] = state

	-- if this is the first edit of the block, schedule the flush
	if not flush_scheduled then
		flush_scheduled = true
		vim.schedule(flush_dirty_bufs)
	end
end

util.connect_signal('parse_done', function(bufnr, extmark, out_syms, in_syms)
	local graph = M.attached_bufs[bufnr]
	if not graph then return end

	local deleted_syms, broken_dependents = graph:update_node(extmark, out_syms, in_syms)

	for _, sym in ipairs(deleted_syms) do
		require('qalc.bridge').submit(util.JobType.DELETE_SYM, bufnr, extmark, sym)
	end

	local dispatch = require('qalc.dispatch')

	-- initial graph setup. we can't evaluate lines sequentially since variables might
	-- be defined lower in the file than they're used (the sheet is free-form like excel)
	if graph.is_initializing then
		graph.pending_parses = graph.pending_parses - 1

		if graph.pending_parses == 0 then
			graph.is_initializing = false

			local full_cascade, cycle_diags, dup_diags = graph:get_full_sort()
			dispatch.run_cascade(bufnr, graph, full_cascade, cycle_diags, dup_diags)
		end

		return
	end

	local cascade, cycle_diags, dup_diags = graph:get_cascade(extmark, broken_dependents)
	dispatch.run_cascade(bufnr, graph, cascade, cycle_diags, dup_diags)
end)

-- re-initialize a buffer completely
function M.hard_reset(bufnr)
	local bridge = require('qalc.bridge')

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) then return end

	require('qalc.output').clear_all(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, util.ns_track, 0, -1)
	bridge.submit(util.JobType.CLEAR_SYMS, bufnr, -1, '')

	local graph = require('qalc.depgraph').new(bufnr)
	M.attached_bufs[bufnr] = graph

	-- first initialization, we need to mark the graph as initializing so it can
	-- be properly rebuilt later
	graph.is_initializing = true
	graph.pending_parses = 0

	local total_lines = vim.api.nvim_buf_line_count(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, total_lines, false)

	for i, text in ipairs(lines) do
		local id = vim.api.nvim_buf_set_extmark(bufnr, util.ns_track, i - 1, 0, {})
		if text:gsub(util.comment_pat, ''):match('%S') then
			graph.pending_parses = graph.pending_parses + 1
			bridge.submit(util.JobType.PARSE_LINE, bufnr, id, text)
		end
	end

	-- edge case, buffer is initially empty
	if graph.pending_parses == 0 then
		graph.is_initializing = false
	end
end

-- attach qalc to a buffer
function M.attach(bufnr)
	require('qalc.bridge').register_callback(M.attached_bufs)
	require('qalc.hover').bind_key(bufnr)

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if M.is_attached(bufnr) then return true end

	detach_queue[bufnr] = nil
	vim.fn.bufload(bufnr)

	M.attached_bufs[bufnr] = require('qalc.depgraph').new(bufnr)

	vim.api.nvim_buf_attach(bufnr, false, { on_lines = on_lines })
	vim.bo.filetype = 'qalc'

	M.hard_reset(bufnr)
end

-- update C++-side state in the newly focused buffer
function M.focus_buffer(bufnr)
	local bridge = require('qalc.bridge')

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) or cur_active_buf == bufnr then return end
	cur_active_buf = bufnr

	-- wipe local variables from other buffers
	bridge.submit(util.JobType.CLEAR_SYMS, bufnr, -1, '')

	local graph = M.attached_bufs[bufnr]
	if not graph or graph.is_initializing then return end

	local cascade, cycle_diags, dup_diags = graph:get_full_sort()
	require('qalc.dispatch').run_cascade(bufnr, graph, cascade, cycle_diags, dup_diags)
end

function M.get_graph(bufnr)
	return M.attached_bufs[bufnr]
end

return M
