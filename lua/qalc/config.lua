-- handle qalc.nvim configuration
local options = require('qalc.options')
local util = require('qalc.util')

local M = {}

-- default configuration
M.cfg = {
	-- default name of a newly opened buffer
	-- set to '' to open an unnamed buffer
	bufname = '', -- string

	-- default register to yank results to
	-- default register = '@'
	-- clipboard        = '+'
	-- X11 selection    = '*'
	-- other registers not listed are also supported
	-- see `:h setreg()`
	yank_default_register = '@', -- string

	-- qalc CLI-style calculator options (same keys and values as :QalcSet)
	-- e.g. { angle_unit = 'degrees' }
	qalc_options = {},

	display = {
		-- sign shown before result (false to disable)
		sign = '=', -- string or false

		-- placeholder shown while result is evaluating (false to disable)
		placeholder = '...', -- string or false

		-- whether to display multiline results as virtual lines or to collapse
		-- all outputs to compact single-line virtual text
		multiline = true, -- boolean

		-- number of spaces to indent multiline results, -1 means buffer's tabstop
		multiline_indent = -1,

		-- how to display the result sign for multiline results
		-- 'eol': add sign at the end of calculation line like a single-line result
		-- 'before': include sign in indentation, right-aligned before first line
		-- 'none': don't display a sign for multiline results
		multiline_sign_style = 'before',

		-- highlight groups (see `:h nvim_set_hl()`)
		highlights = { -- table
			sign = { link = 'Conceal' }, -- sign before result
			result = { link = '@string' }, -- normal result
		},

		-- diagnostic options (false to respect the options in your Neovim config)
		-- (see `:h vim.diagnostic.config()`)
		diagnostics = { -- table or false
			underline = true,
			virtual_text = false,
			signs = true,
			update_in_insert = true,
			severity_sort = true,
		},

		-- hover options
		-- (see `:h vim.lsp.util.open_floating_preview.Opts`)
		hover = {}
	},

	_sign_hl = 'QalcSign',
	_result_hl = 'QalcResult',
}

M.opts_rev = 0

local function rehighlight()
	vim.api.nvim_set_hl(0, M.cfg._sign_hl, M.cfg.display.highlights.sign)
	vim.api.nvim_set_hl(0, M.cfg._result_hl, M.cfg.display.highlights.result)
end

local function deep_extend_inplace(dest, src)
	for k, v in pairs(src) do
		if type(v) == 'table' and type(dest[k]) == 'table' then
			deep_extend_inplace(dest[k], v)
		else
			dest[k] = type(v) == 'table' and vim.deepcopy(v) or v
		end
	end
end

local function apply_options(before)
	local after = M.options_snapshot()
	if vim.deep_equal(before, after) then return end

	M.opts_rev = M.opts_rev + 1

	require('qalc.bridge').submit_config_update()
	require('qalc.buffer').options_changed(options.requires_reparse(before, after))
end

function M.setup(new_cfg)
	new_cfg = vim.deepcopy(new_cfg or {})
	local values = options.normalize(new_cfg.qalc_options)
	new_cfg.qalc_options = nil

	local before = M.options_snapshot()

	deep_extend_inplace(M.cfg, new_cfg)
	if values ~= nil then
		M.cfg.qalc_options = values
	end

	rehighlight()

	if M.cfg.display.diagnostics ~= false then
		vim.diagnostic.config(M.cfg.display.diagnostics, util.ns)
	end

	apply_options(before)

	for _, state in pairs(require('qalc.buffer').attached_bufs) do
		require('qalc.output').refresh(state, true)
	end
	vim.cmd('redraw!')
end

function M.set_option(name, value)
	local values = options.change(M.cfg.qalc_options, name, value)
	local before = M.options_snapshot()

	M.cfg.qalc_options = values
	apply_options(before)
end

function M.options_snapshot()
	local snapshot = options.snapshot(M.cfg.qalc_options)
	snapshot['output.multiline'] = M.cfg.display.multiline

	return snapshot
end

function M.show_options()
	vim.notify(vim.inspect(options.describe(M.cfg.qalc_options)), vim.log.levels.INFO, {
		title = 'qalc options (overrides)',
	})
end

rehighlight()

return M
