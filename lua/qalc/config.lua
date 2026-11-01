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

local function apply_options(changed, reparse)
	if not changed then return end

	M.opts_rev = M.opts_rev + 1
	require('qalc.buffer').options_changed(reparse)
end

-- full of hacks but idk how to make this better idk im tired i maybe shouldnt
-- have delayed this rewrite for 4 years
function M.setup(new_cfg)
	new_cfg = vim.deepcopy(new_cfg or {})

	local values = new_cfg.qalc_options
	if values == nil then values = {} end

	local changed, reparse = options.set(values)
	if new_cfg.qalc_options ~= nil then M.cfg.qalc_options = values end
	new_cfg.qalc_options = nil

	local multiline = new_cfg.display and new_cfg.display.multiline
	changed = changed or (multiline ~= nil and multiline ~= M.cfg.display.multiline)

	deep_extend_inplace(M.cfg, new_cfg)
	rehighlight()

	if M.cfg.display.diagnostics ~= false then
		vim.diagnostic.config(M.cfg.display.diagnostics, util.ns)
	end

	apply_options(changed, reparse)

	for _, state in pairs(require('qalc.buffer').attached_bufs) do
		require('qalc.output').refresh(state, true)
	end
	vim.cmd('redraw!')
end

function M.set_options(values)
	apply_options(options.set(values))
end

function M.reset_options(names)
	apply_options(options.reset(names))
end

function M.set_option(name, value)
	assert(type(name) == 'string', 'qalc: option name must be a string')
	if value == nil then
		M.reset_options({ name })
	else
		M.set_options({ [name] = value })
	end
end

function M.show_options()
	vim.notify(vim.inspect(options.describe()), vim.log.levels.INFO, {
		title = 'currently set qalc option overrides',
	})
end

rehighlight()

return M
