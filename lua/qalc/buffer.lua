-- handle buffer creation, attach/detach, and yanking result
-- TODO: probably need to rework this entirely for the new async architecture
local cfg = require('qalc.config').cfg

local attached_instances = {}
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

	require('qalc.output').clear(bufnr)
end

local function detach(bufnr)
	detach_queue[bufnr] = nil
	results[bufnr] = nil

	-- dropping the ref is enough to gc it eventually
	attached_instances[bufnr] = nil
end
-- }}}

-- {{{ attach
local function attach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- don't attach twice
	if attached_instances[bufnr] ~= nil then
		return true
	end

	-- we are attaching; don't detach
	detach_queue[bufnr] = nil
	vim.fn.bufload(bufnr)

	local inst = require('qalc.lib').make_instance()
	local function cb(_, _, _, first, last)
		if detach_queue[bufnr] then
			detach(bufnr)
			return true -- actually detaches the callback
		end

		first = first or 0
		-- TODO:
		-- local result = require('qalc.bridge').eval(bufnr, first, last)
		-- require('qalc.output').render(bufnr, result, first)
		results[bufnr] = result
	end

	cb() -- update once now
	vim.api.nvim_buf_attach(0, false, { on_lines = cb })
	attached_instances[bufnr] = inst

	vim.bo.filetype = 'qalc'
end

local function is_attached(bufnr)
	return attached_instances[bufnr]
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
