-- handle buffer creation, attach, cleanup, and job submission
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local Depgraph = require('qalc.depgraph')
local Document = require('qalc.document')

local M = {}

-- bufnr -> buf state
M.attached_bufs = {}

local cur_active_buf = nil
local dirty_bufs = {}
local flush_scheduled = false

local calculator_valid = false
local committed_bufnr = nil
local committed_graph = nil

local eval_inflight = nil
local pending_eval = nil

local parse_inflight = nil
local next_parse_req_id = 0

local function new_buf_state(bufnr, lines)
	lines = lines or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	return {
		bufnr = bufnr,
		doc = Document.new(lines),
		graph = nil,
		needs_initialization = true,
		needs_refresh = false,
		is_initializing = true,
	}
end

local start_eval
local rebuild

-- parse all unresolved statements, then rebuild and evaluate one coherent graph snapshot.
local function request_parse(state)
	if parse_inflight then return end

	local stmts = {}
	for _, stmt in ipairs(state.doc:records()) do
		if not stmt.parsed then
			if not stmt.text then return end
			local expr = stmt.text:gsub(util.comment_pat, '')
			if expr:match('%S') then
				stmts[#stmts+1] = stmt
			else
				stmt.parsed = {
					outputs = {},
					in_syms = {},
					norm_expr = '',
					diags = {},
					skip = true,
				}
			end
		end
	end

	if #stmts == 0 then
		rebuild(state)
		return
	end

	next_parse_req_id = next_parse_req_id + 1
	parse_inflight = {
		req_id = next_parse_req_id,
		state = state,
	}
	require('qalc.bridge').submit_parse_batch(
		state.bufnr,
		next_parse_req_id,
		stmts
	)
end

local function finish_eval(complete)
	local finished = eval_inflight
	if not finished then return end
	if finished.state.doc.generation ~= finished.generation then
		finished.state.needs_refresh = true
	elseif M.attached_bufs[finished.state.bufnr] == finished.state then
		local updates = {}
		for _, result in ipairs(finished.results) do
			local stmt = finished.state.doc:get(result.stmt_id)
			if stmt then
				updates[#updates+1] = {
					stmt_id = stmt.id,
					output = result.output,
					diags = result.diags,
				}
			end
		end
		require('qalc.output').render_batch(finished.state, updates)
	end

	if complete then
		calculator_valid = true
		committed_bufnr = finished.state.bufnr
		committed_graph = finished.graph
	else
		calculator_valid = false
		committed_bufnr = nil
		committed_graph = nil
	end

	eval_inflight = nil
	local pending = pending_eval
	pending_eval = nil
	if pending and M.is_active(pending.state.bufnr) then
		start_eval(pending.state, pending.graph)
	end
end

start_eval = function(state, graph)
	local reset = not calculator_valid or committed_bufnr ~= state.bufnr
	local base = reset and nil or committed_graph
	local plan = Depgraph.plan(graph, base, state.needs_refresh)
	state.needs_refresh = false

	local pending = {}
	for _, id in ipairs(plan.eval_ord) do
		pending[id] = true
	end

	local display_updates = {}
	for id in pairs(plan.affected) do
		local stmt = state.doc:get(id)
		if stmt then
			local diags = graph.cycle_diags[id] or graph.dup_diags[id]
			display_updates[#display_updates+1] = {
				stmt_id = stmt.id,
				diags = diags or {},
				placeholder = pending[id] == true,
			}
		end
	end

	require('qalc.output').render_batch(state, display_updates)

	eval_inflight = {
		state = state,
		graph = graph,
		generation = state.doc.generation,
		results = {},
	}

	local evals = {}
	for _, id in ipairs(plan.eval_ord) do
		local statement = state.doc:get(id)
		if statement then
			local expr = graph.nodes[id].norm_expr
			if not expr or expr == '' then
				expr = statement.text
			end
			evals[#evals+1] = {
				stmt_id = id,
				expr = expr,
			}
		end
	end

	local deletions = vim.tbl_keys(plan.deletions)
	table.sort(deletions)
	require('qalc.bridge').submit_eval_batch(
		state.bufnr,
		state.doc.doc_id,
		state.doc.generation,
		reset,
		deletions,
		evals
	)
end

local function request_eval(state, graph)
	if eval_inflight then
		pending_eval = { state = state, graph = graph }
	else
		start_eval(state, graph)
	end
end

rebuild = function(state)
	if state.needs_initialization or not M.is_active(state.bufnr) then return end

	for _, stmt in ipairs(state.doc:records()) do
		if not stmt.text or not stmt.parsed then return end
	end

	state.graph = Depgraph.build(state.doc:records())
	state.is_initializing = false

	request_eval(state, state.graph)
end

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
	return M.attached_bufs[bufnr] ~= nil
end

function M.is_active(bufnr)
	return cur_active_buf == bufnr and bufnr == vim.api.nvim_get_current_buf()
end

function M.is_ready(bufnr)
	local state = M.attached_bufs[bufnr]
	return state ~= nil and not state.is_initializing
end

-- re-initialize a buffer completely
function M.hard_reset(bufnr)
	local bridge = require('qalc.bridge')

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_attached(bufnr) then return end
	if bufnr ~= vim.api.nvim_get_current_buf() then
		M.attached_bufs[bufnr].needs_initialization = true
		return
	end

	cur_active_buf = bufnr
	bridge.register_callback(M.attached_bufs)

	require('qalc.output').clear_all(bufnr)

	local state = new_buf_state(bufnr)
	state.needs_initialization = false
	M.attached_bufs[bufnr] = state

	request_parse(state)
end

local function flush_dirty_bufs()
	-- runs when event loop is idle
	flush_scheduled = false

	for bufnr in pairs(dirty_bufs) do
		local state = M.attached_bufs[bufnr]
		if
			vim.api.nvim_buf_is_valid(bufnr)
			and state
			and M.is_active(bufnr)
			and not state.needs_initialization
		then
			state.doc:settle(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
			require('qalc.output').refresh(state)
			request_parse(state)
		elseif state then
			state.needs_initialization = true
		end
	end

	dirty_bufs = {}
end

local function on_lines(_, bufnr, _, first_lnum, old_last_lnum, new_last_lnum)
	local state = M.attached_bufs[bufnr]
	if not state then return true end

	state.doc:apply_edit(first_lnum, old_last_lnum, new_last_lnum)
	state.is_initializing = true

	if not M.is_active(bufnr) then
		state.needs_initialization = true
		dirty_bufs[bufnr] = nil
		return
	end

	dirty_bufs[bufnr] = true

	if not flush_scheduled then
		flush_scheduled = true
		vim.schedule(flush_dirty_bufs)
	end
end

-- attach qalc to a buffer
function M.attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	if M.is_attached(bufnr) then
		local state = M.attached_bufs[bufnr]
		if bufnr == vim.api.nvim_get_current_buf() and state.needs_initialization then
			M.focus_buffer(bufnr)
		end
		return true
	end

	vim.fn.bufload(bufnr)
	if M.is_attached(bufnr) then return true end
	require('qalc.hover').bind_key(bufnr)

	M.attached_bufs[bufnr] = new_buf_state(bufnr)

	vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = on_lines,

		on_detach = function(_, detached_bufnr)
			M.attached_bufs[detached_bufnr] = nil
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
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if bufnr ~= vim.api.nvim_get_current_buf() then return end
	if not M.is_attached(bufnr) then
		cur_active_buf = nil
		return
	end

	if cur_active_buf == bufnr then return end
	cur_active_buf = bufnr

	local state = M.attached_bufs[bufnr]
	if state.needs_initialization then
		M.hard_reset(bufnr)
		return
	end

	request_eval(state, state.graph)
end

function M.get_state(bufnr)
	return M.attached_bufs[bufnr]
end

function M.get_graph(bufnr)
	local state = M.attached_bufs[bufnr]
	return state and state.graph
end

util.connect_signal('parse_batch_done', function(bufnr, req_id, results)
	local finished = parse_inflight
	if not finished or finished.req_id ~= req_id then return end
	parse_inflight = nil

	local state = M.attached_bufs[bufnr]
	if state == finished.state and M.is_active(bufnr) then
		for _, result in ipairs(results) do
			local stmt = state.doc:get(result.stmt_id)
			if stmt then
				stmt.parsed = {
					outputs = result.outputs,
					in_syms = result.in_syms,
					norm_expr = result.norm_expr,
					diags = result.diags,
				}
			end
		end
	elseif state == finished.state then
		state.needs_initialization = true
	end

	local active_state = M.attached_bufs[cur_active_buf]
	if active_state and not active_state.needs_initialization then
		request_parse(active_state)
	end
end)

util.connect_signal('eval_batch_done', function(bufnr, result)
	local inflight = eval_inflight
	if not inflight or inflight.state.bufnr ~= bufnr then return end
	if result.doc_id ~= inflight.state.doc.doc_id
		or result.generation ~= inflight.generation
	then
		return
	end

	inflight.results = result.results
	finish_eval(result.complete)
end)

return M
