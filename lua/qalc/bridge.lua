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

function M.submit(type, bufnr, extmark_id, payload)
	lib.submit_job(type, bufnr, extmark_id, payload)
end

function M.register_callback(attached_bufs)
	local function handle_job(type, bufnr, extmark, output, diags, out_syms, in_syms)
		if type == M.JobType.EVAL_LINE then
			require('qalc.output').render(bufnr, extmark, output, diags)
		elseif type == M.JobType.PARSE_LINE then
			local graph = attached_bufs[bufnr]
			if not graph then return end

			local deleted_syms = graph:update_node(extmark, out_syms, in_syms)
			for _, sym in ipairs(deleted_syms) do
				M.submit(M.JobType.DELETE_SYM, bufnr, extmark, sym)
			end

			local cascade, depgraph_diags = graph:get_cascade(extmark)

			-- TEMPORARY#1: when depgraph is done, this should be removed!
			-- for now, we need it to properly clear removed variables
			M.submit(M.JobType.CLEAR_SYMS, bufnr, -1, "")

			for _, id in ipairs(cascade) do
				if depgraph_diags and depgraph_diags[id] then
					require('qalc.output').render(bufnr, id, "", depgraph_diags[id])
				else
					local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_track, id, {})
					if #pos > 0 then
						local lnum = pos[1]
						local total_lines = vim.api.nvim_buf_line_count(bufnr)

						-- ensure the line actually exists in the buffer (dont try to read past end)
						if lnum < total_lines then
							-- find the active mark (first one) on this line
							local active_mark = vim.api.nvim_buf_get_extmarks(
								bufnr, ns_track, {lnum, 0}, {lnum, -1}, { limit = 1 }
							)

							-- only evaluate once for the active mark
							if #active_mark > 0 and active_mark[1][1] == id then
								local text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
								if text:match("%S") then
									M.submit(M.JobType.EVAL_LINE, bufnr, id, text)
								end
							end
						end
					end
				end
			end
		end
	end

	local dummy = vim.uv.new_timer()
	assert(dummy, "unable to initialize qalc.nvim: uv timer is nil")
	lib.init_loop(dummy)
	dummy:close()

	lib.set_callback(vim.schedule_wrap(handle_job))
end

return M
