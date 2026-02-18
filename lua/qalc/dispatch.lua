local util = require('qalc.util')

local M = {}

-- dispatch a cascade of evaluations, reporting cycles and duplicates
function M.run_cascade(bufnr, graph, cascade, cycle_diags, dup_diags)
	local total_lines = vim.api.nvim_buf_line_count(bufnr)

	local pending_ids = {}

	for _, id in ipairs(cascade) do
		if not ((cycle_diags and cycle_diags[id]) or (dup_diags and dup_diags[id])) then
			pending_ids[#pending_ids+1] = id
		end
	end

	if #pending_ids > 0 then
		util.emit_signal('eval_started', bufnr, pending_ids)
	end

	for _, id in ipairs(cascade) do
		if cycle_diags and cycle_diags[id] then
			util.emit_signal('diags_ready', bufnr, id, cycle_diags[id])
			M.clear_out_syms_for(bufnr, graph, id)
		elseif dup_diags and dup_diags[id] then
			util.emit_signal('diags_ready', bufnr, id, dup_diags[id])
		else
			local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, util.ns_track, id, {})

			if #pos > 0 then
				local lnum = pos[1]

				if lnum < total_lines then
					local line_marks = vim.api.nvim_buf_get_extmarks(
						bufnr, util.ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
					)

					if #line_marks > 0 and line_marks[1][1] == id then
						-- active mark, safe to evaluate

						-- ensure idempotency by deleting all possible output symbols first
						-- makes global shadowing warning consistent and also prevents self-ref
						M.clear_out_syms_for(bufnr, graph, id)

						require('qalc.bridge').submit(
							util.JobType.EVAL_LINE,
							bufnr,
							id,
							vim.api.nvim_buf_get_lines(bufnr, lnum, lnum+1, false)[1] or ''
						)
					else
						util.emit_signal('result_cleared', bufnr, id)
					end
				end
			end
		end
	end
end

function M.clear_out_syms_for(bufnr, graph, id)
	local node = graph.nodes[id]
	if node and node.out_syms then
		for _, def in ipairs(node.out_syms) do
			require('qalc.bridge').submit(util.JobType.DELETE_SYM, bufnr, id, def.ref_name)
		end
	end
end

util.guard_signal('eval_done', function(bufnr, extmark, _, _)
	local graph = require('qalc.buffer').get_graph(bufnr)

	-- don't allow results to propagate if cycle errors are present
	if graph and graph.had_cycle_error[extmark] then
		return false
	end

	return true
end)

util.connect_signal('parse_done', function(bufnr, extmark, out_syms, in_syms)
	local graph = require('qalc.buffer').get_graph(bufnr)
	if not graph then return end

	local deleted_syms, broken_dependents = graph:update_node(extmark, out_syms, in_syms)

	for _, sym in ipairs(deleted_syms) do
		require('qalc.bridge').submit(util.JobType.DELETE_SYM, bufnr, extmark, sym)
	end

	-- initial graph setup. we can't evaluate lines sequentially since variables might
	-- be defined lower in the file than they're used (the sheet is free-form like excel)
	if graph.is_initializing then
		graph.pending_parses = graph.pending_parses - 1

		if graph.pending_parses == 0 then
			graph.is_initializing = false

			local full_cascade, cycle_diags, dup_diags = graph:get_full_sort()
			M.run_cascade(bufnr, graph, full_cascade, cycle_diags, dup_diags)
		end

		return
	end

	local cascade, cycle_diags, dup_diags = graph:get_cascade(extmark, broken_dependents)
	M.run_cascade(bufnr, graph, cascade, cycle_diags, dup_diags)
end)

return M
