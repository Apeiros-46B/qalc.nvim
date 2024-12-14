-- handle buffer creation, attach/detach, and yanking result
local cfg = require('qalc.config').cfg

local attached = {}
-- mapping of bufnr -> bool, all buffers in this set should be detached from
local detach_queue = {}
local results = {}

-- {{{ create buffer
local function new_buf(name)
	local cmd = 'enew'

	if name ~= '' and name ~= nil then
		cmd = 'e ' .. name
	elseif cfg.bufname ~= '' then
		cmd = 'e ' .. cfg.bufname
	end

	vim.cmd(cmd)
end
-- }}}

-- {{{ detach
local function queue_detach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- referenced in nvim_buf_attach callback to actually detach the callback
	detach_queue[bufnr] = true

	-- TODO: after detaching from a file and reattaching, all /global/ definitions are gone
	require('qalc.bridge').clear_defs(bufnr)
	require('qalc.output').clear(bufnr)
end

local function detach(bufnr)
	detach_queue[bufnr] = nil
	results[bufnr] = nil
	attached[bufnr] = false
end
-- }}}

-- {{{ attach
local function attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- don't attach twice
	if attached[bufnr] then
		return true
	end

	-- we are attaching; don't detach
	detach_queue[bufnr] = nil
	vim.fn.bufload(bufnr)

	local function cb(_, _, _, first, last)
		if detach_queue[bufnr] then
			detach(bufnr)
			return true -- actually detaches the callback
		end

		first = first or 0
		local result = require('qalc.bridge').eval(bufnr, first, last)
		require('qalc.output').render(bufnr, result, first)
		results[bufnr] = result
	end

	cb() -- update once now
	vim.api.nvim_buf_attach(0, false, { on_lines = cb })
	attached[bufnr] = true

	vim.bo.filetype = 'qalc'
end

local function is_attached(bufnr)
	return attached[bufnr]
end
-- }}}

-- {{{ yank results from current line
local function yank(register, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local val = results[bufnr][lnum]
	if val ~= nil then
		vim.fn.setreg(register, val)
	end
end
-- }}}

return {
	new_buf     = new_buf,
	is_attached = is_attached,
	attach      = attach,
	detach      = queue_detach,
	yank        = yank,
}
