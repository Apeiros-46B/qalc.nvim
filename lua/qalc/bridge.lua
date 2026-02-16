-- set up connection with the C++ library
local ns_track = vim.api.nvim_create_namespace('qalc_track')
local lib = require('qalc.lib')

local M = {}

M.JobType = {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_LINE = 3,
	EVAL_LINE = 4,
}

function M.submit(type, bufnr, extmark, payload)
	local output = require('qalc.output')

	-- strip comments
	if (type == M.JobType.EVAL_LINE or type == M.JobType.PARSE_LINE) then
		payload = payload:gsub('#.*$', '')
	end

	-- don't allow legacy function syntax, too hard to parse for depgraph
	local is_forbidden = payload:match('^%s*function%s+')
	local is_blank = not payload:match('%S')

	if type == M.JobType.EVAL_LINE then
		if is_forbidden then
			local diags = {{
				message = 'Legacy "function" syntax disabled. Use f(x) := ...',
				severity = vim.diagnostic.severity.ERROR
			}}
			output.render(bufnr, extmark, '', diags)
			return
		elseif is_blank then
			-- clear stale results for blank lines
			output.clear(bufnr, extmark)
			return
		end
	elseif type == M.JobType.PARSE_LINE then
		if is_forbidden or is_blank then
			-- force parser to parse empty string to update depgraph in callback
			-- we can't update it directly because race conditions might occur
			-- sending jobs enforces a strict order since they are queued on the worker thread
			payload = ''
		end
	end

	lib.submit_job(type, bufnr, extmark, payload)
end

function M.register_callback(attached_bufs)
	local function handle_job(type, bufnr, extmark, output, diags, out_syms, in_syms)
		-- buffer might have been closed while C++ was working
		if not vim.api.nvim_buf_is_valid(bufnr) then return end

		local graph = attached_bufs[bufnr]

		if type == M.JobType.EVAL_LINE then
			if graph and graph.cycle_errors and graph.cycle_errors[extmark] then
				return
			end
			require('qalc.output').render(bufnr, extmark, output, diags)
		elseif type == M.JobType.PARSE_LINE then
			if not graph then return end

			local deleted_syms, broken_dependents = graph:update_node(extmark, out_syms, in_syms)
			for _, sym in ipairs(deleted_syms) do
				M.submit(M.JobType.DELETE_SYM, bufnr, extmark, sym)
			end

			local cascade, dep_diags = graph:get_cascade(extmark, broken_dependents)

			local total_lines = vim.api.nvim_buf_line_count(bufnr)
			for _, id in ipairs(cascade) do
				if dep_diags and dep_diags[id] then
					require('qalc.output').render(bufnr, id, '', dep_diags[id])

					-- TODO: if there are depgraph errors other than cyclic, we have to distinguish
					-- for now, only cyclic errors are possible, so this is fine
					-- purge cyclic nodes
					local node = graph.nodes[id]
					if node and node.out_syms then
						for _, sym in ipairs(node.out_syms) do
							M.submit(M.JobType.DELETE_SYM, bufnr, id, sym)
						end
					end
				else
					local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_track, id, {})
					if #pos > 0 then
						local lnum = pos[1]
						if lnum < total_lines then
							local line_marks = vim.api.nvim_buf_get_extmarks(
								bufnr, ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
							)

							if #line_marks > 0 and line_marks[1][1] == id then
								-- active mark, safe to evaluate
								local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ''
								M.submit(M.JobType.EVAL_LINE, bufnr, id, text)
							end
							-- in case of ghost, do nothing
						end
					end
				end
			end
		end
	end

	local dummy = vim.uv.new_timer()
	assert(dummy, 'unable to initialize qalc.nvim: uv timer is nil')
	lib.init_loop(dummy)
	dummy:close()

	lib.set_callback(vim.schedule_wrap(handle_job))
end

return M
