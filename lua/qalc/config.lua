-- handle qalc.nvim configuration
local options = require('qalc.options')
local util = require('qalc.util')

local M = {}

-- default configuration
M.cfg = {
	-- default name of a newly opened buffer
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
	options = {},

	display = {
		-- sign shown before result (false to disable)
		sign = '=', -- string or false

		-- placeholder shown while result is evaluating (false to disable)
		placeholder = '...', -- string or false

		-- whether or not to right align virtual text
		right_align = false, -- boolean

		-- display style for multiline results
		-- 'below': virtual lines below
		-- 'collapse': make multiline results single-line
		-- 'extend': virtual text at end of line + aligned virtual lines
		multiline_style = 'below', -- boolean

		-- highlight groups (see `:h nvim_set_hl()`)
		highlights = { -- table
			sign = { link = '@conceal' }, -- sign before result
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

local function apply_options(values)
	if values == nil or vim.deep_equal(M.cfg.options, values) then return end

	local before = M.options_snapshot()
	local after = options.snapshot(values)

	M.cfg.options = values
	M.opts_rev = M.opts_rev + 1

	require('qalc.bridge').submit_config_update()
	require('qalc.buffer').options_changed(options.requires_reparse(before, after))
end

function M.setup(new_cfg)
	local values
	new_cfg, values = options.normalize_cfg(new_cfg)

	deep_extend_inplace(M.cfg, new_cfg)
	rehighlight()

	if M.cfg.display.diagnostics ~= false then
		vim.diagnostic.config(M.cfg.display.diagnostics, util.ns)
	end

	apply_options(values)
end

function M.set_option(name, value)
	apply_options(options.change(M.cfg.options, name, value))
end

function M.options_snapshot()
	return options.snapshot(M.cfg.options)
end

function M.show_options()
	vim.notify(vim.inspect(options.describe(M.cfg.options)), vim.log.levels.INFO, {
		title = 'qalc options (overrides)',
	})
end

rehighlight()

return M
