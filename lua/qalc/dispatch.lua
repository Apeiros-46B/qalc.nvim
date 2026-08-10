local util = require('qalc.util')

local M = {}

-- dispatch a cascade of evaluations, reporting cycles and duplicates
function M.run_cascade(bufnr, state, cascade, cycle_diags, dup_diags)
	local graph = state.graph
	local pending_ids = {}

	for _, id in ipairs(cascade) do
		local stmt = state.doc:get(id)
		if stmt and not (cycle_diags[id] or dup_diags[id]) then
			pending_ids[#pending_ids+1] = stmt.mark
		end
	end

	if #pending_ids > 0 then
		util.emit_signal('eval_started', bufnr, pending_ids)
	end

	for _, id in ipairs(cascade) do
		local stmt = state.doc:get(id)
		if cycle_diags and cycle_diags[id] then
			if stmt then
				util.emit_signal('diags_ready', bufnr, stmt.mark, cycle_diags[id])
			end
			M.clear_out_syms_for(bufnr, state, id)
		elseif dup_diags and dup_diags[id] then
			if stmt then
				util.emit_signal('diags_ready', bufnr, stmt.mark, dup_diags[id])
			end
		elseif stmt then
			local node = graph.nodes[id]
			local expr = node and node.norm_expr
			if not expr or expr == '' then
				expr = stmt.text
			end

			-- ensure idempotency by deleting all possible output symbols first
			-- makes global shadowing warning consistent and also prevents self-ref
			M.clear_out_syms_for(bufnr, state, id)
			require('qalc.bridge').submit(util.JobType.EVAL_LINE, bufnr, id, expr)
		end
	end
end

function M.clear_out_syms_for(bufnr, state, id)
	local graph = state.graph
	local node = graph.nodes[id]
	if node and node.outputs then
		for _, def in ipairs(node.outputs) do
			require('qalc.bridge').submit(util.JobType.DELETE_SYM, bufnr, id, def.ref_name)
		end
	end
end

util.guard_signal('eval_done', function(bufnr, extmark, _, _)
	local buffer = require('qalc.buffer')
	if not buffer.is_active(bufnr) then return false end

	local state = buffer.get_state(bufnr)
	if not state or not state.graph then return false end

	local stmt = state.doc:get_by_mark(extmark)
	if not stmt then return false end

	-- don't allow results to propagate if blocked
	if state.graph.blocked[stmt.id] then return false end

	return true
end)

return M
