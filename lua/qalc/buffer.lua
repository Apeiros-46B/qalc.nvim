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

local function submit_parse(state, stmt)
	local expr = stmt.text:gsub(util.comment_pat, '')
	if not expr:match('%S') then
		stmt.parsed = { out_syms = {}, in_syms = {}, norm_expr = '', skip = true }
		return
	end

	require('qalc.bridge').submit(
		util.JobType.PARSE_LINE,
		state.bufnr,
		stmt.id,
		stmt.text
	)
end

local function has_timeout(diagnostics)
	for _, diagnostic in ipairs(diagnostics or {}) do
		if diagnostic.message == 'Calculation took too long'
			or diagnostic.message == 'Dependent calculation took too long'
		then
			return true
		end
	end
	return false
end

local start_evaluation

local function finish_evaluation(complete)
	local finished = eval_inflight
	if not finished then return end
	if finished.state.doc.generation ~= finished.generation then
		finished.state.needs_refresh = true
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
		start_evaluation(pending.state, pending.graph)
	end
end

local function handle_eval_result(bufnr, statement_id, output, diagnostics)
	local inflight = eval_inflight
	if not inflight or inflight.state.bufnr ~= bufnr then return end
	if not inflight.pending[statement_id] then return end

	inflight.pending[statement_id] = nil
	inflight.pending_count = inflight.pending_count - 1
	if has_timeout(diagnostics) then
		inflight.complete = false
	end

	local state = M.attached_bufs[bufnr]
	if state == inflight.state and state.doc.generation == inflight.generation then
		local statement = state.doc:get(statement_id)
		if statement then
			require('qalc.output').render(
				bufnr,
				statement.mark,
				output,
				diagnostics
			)
		end
	end

	if inflight.pending_count == 0 then
		finish_evaluation(inflight.complete)
	end
end

start_evaluation = function(state, graph)
	local reset = not calculator_valid or committed_bufnr ~= state.bufnr
	local base = reset and nil or committed_graph
	local plan = Depgraph.plan(graph, base, state.needs_refresh)
	local bridge = require('qalc.bridge')
	local output = require('qalc.output')
	state.needs_refresh = false

	if reset then
		bridge.submit(util.JobType.CLEAR_SYMS, state.bufnr, -1, '')
	else
		local symbols = vim.tbl_keys(plan.deletions)
		table.sort(symbols)
		for _, symbol in ipairs(symbols) do
			bridge.submit(util.JobType.DELETE_SYM, state.bufnr, -1, symbol)
		end
	end

	local pending_marks = {}
	local pending = {}
	for _, id in ipairs(plan.eval_ord) do
		local statement = state.doc:get(id)
		if statement then
			pending[id] = true
			pending_marks[#pending_marks+1] = statement.mark
		end
	end
	if #pending_marks > 0 then
		util.emit_signal('eval_started', state.bufnr, pending_marks)
	end

	for id in pairs(plan.affected) do
		local statement = state.doc:get(id)
		if statement then
			local diagnostics = graph.cycle_diags[id] or graph.dup_diags[id]
			if diagnostics then
				output.render(state.bufnr, statement.mark, '', diagnostics)
			end
		end
	end

	eval_inflight = {
		state = state,
		graph = graph,
		generation = state.doc.generation,
		pending = pending,
		pending_count = #pending_marks,
		complete = true,
	}

	for _, id in ipairs(plan.eval_ord) do
		local statement = state.doc:get(id)
		if statement then
			local expression = graph.nodes[id].norm_expr
			if not expression or expression == '' then
				expression = statement.text
			end
			bridge.submit(util.JobType.EVAL_LINE, state.bufnr, id, expression)
		end
	end

	if eval_inflight and eval_inflight.pending_count == 0 then
		finish_evaluation(true)
	end
end

local function request_evaluation(state, graph)
	if eval_inflight then
		pending_eval = { state = state, graph = graph }
	else
		start_evaluation(state, graph)
	end
end

local function rebuild(state)
	if state.needs_initialization or not M.is_active(state.bufnr) then return end

	for _, stmt in ipairs(state.doc:records()) do
		if not stmt.text or not stmt.parsed then return end
	end

	state.graph = Depgraph.build(state.doc:records())
	state.is_initializing = false

	request_evaluation(state, state.graph)
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
	vim.api.nvim_buf_clear_namespace(bufnr, util.ns_track, 0, -1)

	local state = new_buf_state(bufnr)
	state.needs_initialization = false
	M.attached_bufs[bufnr] = state

	for i, stmt in ipairs(state.doc:records()) do
		local mark = vim.api.nvim_buf_set_extmark(bufnr, util.ns_track, i - 1, 0, {})
		state.doc:set_mark(stmt, mark)
		submit_parse(state, stmt)
	end

	rebuild(state)
end

local function flush_dirty_bufs()
	-- runs when event loop is idle
	flush_scheduled = false

	for bufnr, dirty in pairs(dirty_bufs) do
		local state = M.attached_bufs[bufnr]
		if
			vim.api.nvim_buf_is_valid(bufnr)
			and state
			and M.is_active(bufnr)
			and not state.needs_initialization
		then
			state.doc:settle(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

			for _, stmt in pairs(dirty.retired) do
				require('qalc.output').clear(bufnr, stmt.mark)
				vim.api.nvim_buf_del_extmark(bufnr, util.ns_track, stmt.mark)
			end

			for i, stmt in ipairs(state.doc:records()) do
				if not stmt.mark then
					local mark = vim.api.nvim_buf_set_extmark(bufnr, util.ns_track, i - 1, 0, {})
					state.doc:set_mark(stmt, mark)
					submit_parse(state, stmt)
				end
			end

			rebuild(state)
		elseif state then
			state.needs_initialization = true
		end
	end

	dirty_bufs = {}
end

local function on_lines(_, bufnr, _, first_lnum, old_last_lnum, new_last_lnum)
	local state = M.attached_bufs[bufnr]
	if not state then return true end

	local removed = state.doc:apply_edit(first_lnum, old_last_lnum, new_last_lnum)
	state.is_initializing = true

	if not M.is_active(bufnr) then
		state.needs_initialization = true
		dirty_bufs[bufnr] = nil
		return
	end

	local dirty = dirty_bufs[bufnr] or { retired = {} }
	for _, stmt in ipairs(removed) do
		if stmt.mark then
			dirty.retired[stmt.id] = stmt
		end
	end
	dirty_bufs[bufnr] = dirty

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

	request_evaluation(state, state.graph)
end

function M.get_state(bufnr)
	return M.attached_bufs[bufnr]
end

function M.get_graph(bufnr)
	local state = M.attached_bufs[bufnr]
	return state and state.graph
end

util.connect_signal('parse_done', function(bufnr, stmt_id, out_syms, in_syms, norm_expr)
	local state = M.attached_bufs[bufnr]
	if not state then return end
	if not M.is_active(bufnr) then
		state.needs_initialization = true
		return
	end

	local stmt = state.doc:get(stmt_id)
	if not stmt then return end
	stmt.parsed = {
		out_syms = out_syms,
		in_syms = in_syms,
		norm_expr = norm_expr,
	}

	rebuild(state)
end)

util.connect_signal('eval_done', handle_eval_result)

return M
