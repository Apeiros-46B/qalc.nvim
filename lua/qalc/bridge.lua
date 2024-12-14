-- interface with Qalculate and return formatted results
local lib = require('qalc.lib')

-- the `Calculator` object on C++'s side is deallocated when this is `__gc`ed
local calc_handle = lib.init()

local buffer_def_files = {}

local function load_defs(bufnr)
	if buffer_def_files[bufnr] == nil then
		local file = vim.fn.tempname()
		buffer_def_files[bufnr] = file
		io.open(file, 'w'):close() -- create empty file
	else
		lib.reset()
		lib.load_defs(buffer_def_files[bufnr])
	end
end

local function save_defs(bufnr)
	local file = buffer_def_files[bufnr]
	io.open(file, 'w'):close() -- erase file contents
	lib.save_defs(file)
end

local function clear_defs(bufnr)
	if buffer_def_files[bufnr] ~= nil then
		os.remove(buffer_def_files[bufnr])
		buffer_def_files[bufnr] = nil
	end
	lib.reset()
end

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

-- TODO: more intelligently recalculate instead of recalclating the entire buffer
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
	load_defs     = load_defs,
	save_defs     = save_defs,
	clear_defs    = clear_defs,
	__calc_handle = calc_handle,
}
