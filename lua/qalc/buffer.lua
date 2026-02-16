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

	require('qalc.output').clear_all(bufnr)
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

	local function cb(_, _, _, first, last, new_last)
		if detach_queue[bufnr] then
			detach(bufnr)
			return true -- actually detaches the callback
		end

		local total_lines = vim.api.nvim_buf_line_count(bufnr)

		-- extmarks pushed beyond the last physical line should be treated as ghosts
		local eof_marks = vim.api.nvim_buf_get_extmarks(
			bufnr, ns_track,
			{total_lines, 0}, {-1, -1},
			{}
		)
		for _, mark in ipairs(eof_marks) do
			local id = mark[1]
			bridge.submit(bridge.JobType.PARSE_LINE, bufnr, id, "")
		end

		-- determine which lines have been modified
		local mod_start = first
		local mod_end = math.min(math.max(new_last, first + 1), total_lines)

		-- process extmarks on every modified line
		local lines = vim.api.nvim_buf_get_lines(bufnr, mod_start, mod_end, false)
		for i, text in ipairs(lines) do
			local lnum = mod_start + i - 1
			local marks = vim.api.nvim_buf_get_extmarks(
				bufnr, ns_track, {lnum, 0}, {lnum, -1}, {}
			)

			if #marks == 0 then -- no extmarks exist on this line yet
				-- make a new mark
				local new_id = vim.api.nvim_buf_set_extmark(bufnr, ns_track, lnum, 0, {
					right_gravity = false -- keep at column 0 instead of drifting rightwards
				})

				if text:match("%S") then
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, new_id, text)
				end
			else -- marks exist on this line
				-- first mark is the active one
				local active_id = marks[1][1]

				if text:match("%S") then
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_id, text)
				else
					-- blank line MUST be routed through callback to trigger cascade update
					-- it seems inefficient, but it's the only way we can get the depgraph
					-- to update correctly
					bridge.submit(bridge.JobType.PARSE_LINE, bufnr, active_id, "")
				end

				-- ghost marks must also be routed through callback to prune from depgraph
				if #marks > 1 then
					for j = 2, #marks do
						local ghost_id = marks[j][1]
						bridge.submit(bridge.JobType.PARSE_LINE, bufnr, ghost_id, "")
					end
				end
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

	-- fetch all marks in top-down order (this includes ghosts)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_track, 0, -1, {})
	local seen_lines = {}

	-- evaluate all lines in order
	for _, mark in ipairs(marks) do
		local extmark_id = mark[1]
		local lnum = mark[2]

		-- if we haven't seen this row yet, this is the active mark and not a ghost. otherwise,
		-- it's a ghost and we just ignore it to prevent duplicate eval calls on the same line
		if not seen_lines[lnum] then
			seen_lines[lnum] = true

			local lines = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)
			local text = lines[1] or ""

			-- direct eval, don't go through the depgraph
			-- the depgraph state is already maintained properly, the only reason we need to do
			-- this is to "synchronize" the libqalculate Calculator state with the new buffer
			bridge.submit(bridge.JobType.EVAL_LINE, bufnr, extmark_id, text)
		end
	end
end

-- TODO: function to yank results from current line

return M
