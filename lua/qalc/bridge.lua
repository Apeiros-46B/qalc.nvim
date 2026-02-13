-- interface with Qalculate and return formatted results
local lib = require('qalc.lib')

-- the `Calculator` object on C++'s side is deallocated when this is `__gc`ed
-- TODO: replace this with a table that stores a calc::Instance userdata per buf
local calc_handle = lib.init()

local buffer_def_files = {}

local diagnostic_template = {
	col = 0,
	end_col = -1,
	source = 'qalc',
}

local function push_diagnostic(l, bufnr, lnum, severity, message)
	local new = vim.fn.copy(diagnostic_template)

	new.bufnr = bufnr
	new.lnum = lnum
	new.severity = severity
	new.message = message

	l[#l+1] = new
end

-- TODO: more intelligently recalculate instead of recalculating the entire buffer (build a dep graph with extmarks?)
-- TODO: also handle the edge case of circular deps, probably need to warn
local function eval(bufnr, first, last)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local result = {
		values = {},
		diagnostics = {},
	}

	local lnum = 0
	local severity = vim.diagnostic.severity
	for _, line in pairs(lines) do
		local all_whitespace = string.find(line, '^%s*$')
		local comment = string.find(line, '^%s*#.*$')
		if (not all_whitespace) and (not comment) then
			local raw = lib.eval(line)
			result.values[lnum] = raw.result

			for _, v in ipairs(raw.info_msgs) do
				push_diagnostic(result.diagnostics, bufnr, lnum, severity.INFO, v)
			end
			for _, v in ipairs(raw.warn_msgs) do
				push_diagnostic(result.diagnostics, bufnr, lnum, severity.WARN, v)
			end
			for _, v in ipairs(raw.err_msgs) do
				push_diagnostic(result.diagnostics, bufnr, lnum, severity.ERROR, v)
			end
		end
		lnum = lnum + 1
	end

	return result
end

return {
	eval          = eval,
	__calc_handle = calc_handle,
}
