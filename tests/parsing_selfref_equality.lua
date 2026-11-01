local source = debug.getinfo(1, 'S').source:sub(2)
local test = dofile(vim.fs.dirname(source) .. '/support/qalc.lua')

local bufnr = test.attach_lines({ 'x = x + 1', 'x = 1', 'x + 1' })
for _, diag in ipairs(test.diagnostics(bufnr)) do
	assert(
		not diag.message:find('Duplicate definition', 1, true),
		'self-referential equation was treated as a definition'
	)
end
assert(test.result_at(3, '2'), 'the actual definition did not supply x')
