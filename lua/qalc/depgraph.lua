-- extmark-based dependency graph
-- TODO: actually track dependencies instead of returning all lines for recalculation
----> needs to expose methods to figure out which extmarks to recalculate
----> needs to also detect reference cycles and give errors ("reference cycle found, refusing to evaluate")
-- when this is done, address "TEMPORARY#1"
local ns_track = vim.api.nvim_create_namespace('qalc_track')

local M = {}
M.__index = M

---@param bufnr number The buffer this graph is attached to
function M.new(bufnr)
	local self = setmetatable({}, M)
	self.bufnr = bufnr
	return self
end

function M:update_node(extmark, assigned_list, read_list)
	return {}
end

function M:remove_node(extmark)
	return {}
end

function M:get_cascade(start_extmark_id)
	-- marks are returned in top->down order
	local marks = vim.api.nvim_buf_get_extmarks(self.bufnr, ns_track, 0, -1, {})
	local cascade = {}
	local seen_rows = {}
	local total_lines = vim.api.nvim_buf_line_count(self.bufnr)

	for _, mark in ipairs(marks) do
		local id = mark[1]
		local row = mark[2]

		-- only evaluate the first anchor we find on each row
		if row < total_lines and not seen_rows[row] then
			seen_rows[row] = true
			table.insert(cascade, id)
		end
	end

	return cascade, {}
end

return M
