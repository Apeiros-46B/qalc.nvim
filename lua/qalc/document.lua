-- handle buffer creation, attach, cleanup, and job submission
local M = {}
M.__index = M

local next_doc_id = 0
local next_stmt_id = 0

local function new_stmt(text)
	next_stmt_id = next_stmt_id + 1

	return {
		id = next_stmt_id,
		text = text,
	}
end

function M.new(lines)
	next_doc_id = next_doc_id + 1

	local self = setmetatable({
		doc_id = next_doc_id,
		generation = 0,
		lines = {},
		by_id = {},
	}, M)

	for _, text in ipairs(lines) do
		local stmt = new_stmt(text)
		self.lines[#self.lines+1] = stmt
		self.by_id[stmt.id] = stmt
	end

	return self
end

function M:records()
	return self.lines
end

function M:get(id)
	return self.by_id[id]
end

function M:apply_edit(first_lnum, old_last_lnum, new_last_lnum)
	assert(first_lnum >= 0 and first_lnum <= old_last_lnum, 'invalid old line range')
	assert(old_last_lnum <= #self.lines, 'old line range exceeds document')
	assert(new_last_lnum >= first_lnum, 'invalid new line range')

	local next_lines = {}
	local removed = {}
	local added = {}

	for i = 1, first_lnum do
		next_lines[#next_lines+1] = self.lines[i]
	end

	for i = first_lnum + 1, old_last_lnum do
		local stmt = self.lines[i]
		removed[#removed+1] = stmt
		self.by_id[stmt.id] = nil
	end

	for _ = first_lnum + 1, new_last_lnum do
		local stmt = new_stmt(nil)
		next_lines[#next_lines+1] = stmt
		added[#added+1] = stmt
		self.by_id[stmt.id] = stmt
	end

	for i = old_last_lnum + 1, #self.lines do
		next_lines[#next_lines+1] = self.lines[i]
	end

	self.lines = next_lines
	self.generation = self.generation + 1

	return removed, added
end

function M:settle(lines)
	assert(#lines == #self.lines, 'buf and document line counts differ')

	for i, text in ipairs(lines) do
		local stmt = self.lines[i]
		if stmt.text == nil then
			stmt.text = text
		else
			assert(stmt.text == text, 'statement text changed without edit')
		end
	end
end

return M
