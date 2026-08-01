local source = debug.getinfo(1, 'S').source:sub(2)
local test = dofile(vim.fs.dirname(source) .. '/support/qalc.lua')

local function has_duplicate(bufnr, row)
	for _, diag in ipairs(test.diagnostics(bufnr)) do
		if diag.lnum == row - 1 and diag.message:find('Duplicate definition', 1, true) then
			return true
		end
	end
	return false
end

local function check_incomplete_assignment(operator)
	local prefix = 'x ' .. operator .. ' '
	local bufnr = test.attach_lines({
		prefix .. '1',
		'x + 1',
		'# x := 2',
	})
	assert(test.result_at(2, '2'), 'initial dependency was unavailable')

	vim.api.nvim_buf_set_text(bufnr, 0, #prefix, 0, #prefix + 1, { '' })
	assert(test.result_at(2, '1'), 'incomplete assignment lost dependency ownership')

	vim.api.nvim_buf_set_text(bufnr, 2, 0, 2, 2, { '' })
	test.wait_for(function()
		return has_duplicate(bufnr, 3)
	end, 'incomplete assignment lost symbol ownership')

	vim.api.nvim_buf_delete(bufnr, { force = true })
end

check_incomplete_assignment('=')
check_incomplete_assignment(':=')
