-- handle buffer creation, attach, cleanup, and job submission
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

-- mapping of bufnr -> depgraph. if a bufnr is present then qalc is attached to it
M.graphs = {}

local cur_active_buf = nil

-- bufnr -> { retired = { mark_id -> bool } }
local dirty_bufs = {}
local flush_scheduled = false

function M.new_buf(name)
	if not name or name == '' then
		name = cfg.bufname
	end

	if name == '' then
		vim.cmd.enew()
	else
		vim.api.nvim_cmd({ cmd = 'edit', args = { name } }, {})
	end
end

function M.is_attached(bufnr)
	return M.graphs[bufnr] ~= nil
end

function M.is_active(bufnr)
	return cur_active_buf == bufnr and bufnr == vim.api.nvim_get_current_buf()
end

-- re-initialize a buffer completely
function M.hard_reset(bufnr)
	local bridge = require('qalc.bridge')

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) then return end
	if bufnr ~= vim.api.nvim_get_current_buf() then
		M.graphs[bufnr].needs_initialization = true
		return
	end

	cur_active_buf = bufnr
	bridge.register_callback(M.graphs)

	require('qalc.output').clear_all(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, util.ns_track, 0, -1)
	bridge.submit(util.JobType.CLEAR_SYMS, bufnr, -1, '')

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local graph = require('qalc.depgraph').new(bufnr, lines)
	graph.needs_initialization = false

	M.graphs[bufnr] = graph

	-- first initialization, we need to mark the graph as initializing so it can
	-- be properly rebuilt later
	graph.is_initializing = true
	graph.pending_parses = 0

	for i, stmt in ipairs(graph.doc:records()) do
		local id = vim.api.nvim_buf_set_extmark(bufnr, util.ns_track, i - 1, 0, {})
		graph.doc:set_mark(stmt, id)

		if stmt.text:gsub(util.comment_pat, ''):match('%S') then
			graph.pending_parses = graph.pending_parses + 1
			bridge.submit(util.JobType.PARSE_LINE, bufnr, id, stmt.text)
		end
	end

	-- edge case, buffer is initially empty
	if graph.pending_parses == 0 then
		graph.is_initializing = false
	end
end

local function flush_dirty_bufs()
	local bridge = require('qalc.bridge')

	-- runs when event loop is idle
	flush_scheduled = false

	for bufnr, state in pairs(dirty_bufs) do
		local graph = M.graphs[bufnr]
		if vim.api.nvim_buf_is_valid(bufnr) and graph and M.is_active(bufnr)
			and not graph.needs_initialization
		then
			local total_lines = vim.api.nvim_buf_line_count(bufnr)
			local doc_lines = vim.api.nvim_buf_get_lines(bufnr, 0, total_lines, false)
			graph.doc:settle(doc_lines)

			for mark in pairs(state.retired) do
				bridge.submit(util.JobType.PARSE_LINE, bufnr, mark, '')
			end

			for row, stmt in ipairs(graph.doc:records()) do
				if not stmt.mark then
					local mark = vim.api.nvim_buf_set_extmark(
						bufnr,
						util.ns_track,
						row - 1,
						0,
						{}
					)
					graph.doc:set_mark(stmt, mark)
					bridge.submit(util.JobType.PARSE_LINE, bufnr, mark, stmt.text)
				end
			end
		elseif graph then
			graph.needs_initialization = true
		end
	end

	dirty_bufs = {}
end

local function on_lines(_, bufnr, _, first_lnum, old_last_lnum, new_last_lnum)
	local graph = M.graphs[bufnr]
	if not graph then return true end
	local removed = graph.doc:apply_edit(first_lnum, old_last_lnum, new_last_lnum)

	if not M.is_active(bufnr) then
		graph.needs_initialization = true
		dirty_bufs[bufnr] = nil
		return
	end

	local state = dirty_bufs[bufnr] or { retired = {} }
	for _, statement in ipairs(removed) do
		if statement.mark then
			state.retired[statement.mark] = true
		end
	end
	dirty_bufs[bufnr] = state

	-- if this is the first edit of the block, schedule the flush
	if not flush_scheduled then
		flush_scheduled = true
		vim.schedule(flush_dirty_bufs)
	end
end

-- attach qalc to a buffer
function M.attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if M.is_attached(bufnr) then
		local graph = M.graphs[bufnr]
		if bufnr == vim.api.nvim_get_current_buf() and graph.needs_initialization then
			M.focus_buffer(bufnr)
		end
		return true
	end

	vim.fn.bufload(bufnr)
	if M.is_attached(bufnr) then return true end
	require('qalc.hover').bind_key(bufnr)

	local graph = require('qalc.depgraph').new(bufnr)
	graph.needs_initialization = true
	M.graphs[bufnr] = graph

	vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = on_lines,
		on_detach = function(_, detached_bufnr)
			M.graphs[detached_bufnr] = nil
			dirty_bufs[detached_bufnr] = nil
			if cur_active_buf == detached_bufnr then
				cur_active_buf = nil
			end
			require('qalc.output').clear_all(detached_bufnr)
		end,
	})
	vim.bo[bufnr].filetype = 'qalc'

	if bufnr == vim.api.nvim_get_current_buf() then
		cur_active_buf = bufnr
		M.hard_reset(bufnr)
	end
end

-- update C++-side state in the newly focused buffer
function M.focus_buffer(bufnr)
	local bridge = require('qalc.bridge')

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if bufnr ~= vim.api.nvim_get_current_buf() then return end
	if not M.is_attached(bufnr) then
		cur_active_buf = nil
		return
	end
	if cur_active_buf == bufnr then return end
	cur_active_buf = bufnr

	local graph = M.graphs[bufnr]
	if graph.needs_initialization then
		M.hard_reset(bufnr)
		return
	end

	-- wipe local variables from other buffers
	bridge.submit(util.JobType.CLEAR_SYMS, bufnr, -1, '')

	if graph.is_initializing then return end

	local cascade, cycle_diags, dup_diags = graph:get_full_sort()
	require('qalc.dispatch').run_cascade(bufnr, graph, cascade, cycle_diags, dup_diags)
end

function M.get_graph(bufnr)
	return M.graphs[bufnr]
end

util.connect_signal('parse_done', function(bufnr, extmark, out_syms, in_syms, norm_expr)
	local graph = M.graphs[bufnr]
	if not graph then return end
	if not M.is_active(bufnr) then
		graph.needs_initialization = true
		return
	end
	if #vim.api.nvim_buf_get_extmark_by_id(bufnr, util.ns_track, extmark, {}) == 0 then
		return
	end

	local deleted_syms, broken_dependents = graph:update_node(
		extmark,
		out_syms,
		in_syms,
		norm_expr
	)

	for _, sym in ipairs(deleted_syms) do
		require('qalc.bridge').submit(util.JobType.DELETE_SYM, bufnr, extmark, sym)
	end

	if not graph.doc:get_by_mark(extmark) then
		util.emit_signal('result_cleared', bufnr, extmark)
		vim.api.nvim_buf_del_extmark(bufnr, util.ns_track, extmark)
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

return M
