-- handle buffer creation, attach/detach, and yanking result
local ns = vim.api.nvim_create_namespace('qalc')
local cfg = require('qalc.config').cfg
local bridge = require('qalc.bridge')
local output = require('qalc.output')

local attached = {}
local detach_queue = {} -- more like a set
local results = {}

-- {{{ create buffer
local function new_buf(name)
	local cmd = 'enew'

	if name ~= '' and name ~= nil then
		cmd = 'e ' .. name
	elseif cfg.bufname ~= '' and cfg.bufname ~= nil then
		cmd = 'e ' .. cfg.bufname
	end

	vim.cmd(cmd)
end
-- }}}

-- {{{ detach
local function queue_detach(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- referenced in nvim_buf_attach callback to actually detach
	detach_queue[bufnr] = true
end

local function detach(bufnr)
	attached[bufnr] = false
	results[bufnr] = nil
	bridge.kill(bufnr)
	output.clear(ns)
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

			-- detach from nvim_buf_attach
			return true
		end

		local input = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local res = bridge.run(bufnr, input, first, last)

		output.render(ns, res)
		results[bufnr] = res
	end

	cb() -- update once now
	vim.api.nvim_buf_attach(0, false, { on_lines = cb })
	attached[bufnr] = true

	vim.bo.filetype = 'qalc'
end
-- }}}

-- {{{ yank results from current line
local function yank(bufnr, register)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local val = results[bufnr][lnum]
	if val ~= nil then
		vim.fn.setreg(register, val)
	end
end
-- }}}

local with_nil_variant = require('qalc.util').with_nil_variant

return {
	new_buf = new_buf,
	attach  = with_nil_variant(attach, 'current'),
	detach  = with_nil_variant(queue_detach, 'current'),
	yank    = with_nil_variant(yank, 'current'),
}