-- handle qalc.nvim configuration
local ns_ui = vim.api.nvim_create_namespace('qalc_ui')
local options = require('qalc.options')

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

	-- libqalculate options, enum values accept names or integers
	--> https://qalculate.github.io/reference/structParseOptions.html
	parse_options = {},
	--> https://qalculate.github.io/reference/structPrintOptions.html
	print_options = {},
	--> https://qalculate.github.io/reference/structEvaluationOptions.html
	evaluation_options = {},

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

-- both setup and runtime changes passed as complete opt groups
local function apply_option_groups(opt_groups)
	local changed = false
	local parse_changed = false

	for group, values in pairs(opt_groups) do
		if not vim.deep_equal(M.cfg[group], values) then
			M.cfg[group] = values
			changed = true
			parse_changed = parse_changed or group == 'parse_options'
		end
	end

	if changed then
		M.opts_rev = M.opts_rev + 1

		-- don't load qalc.buffer if not loaded since we might be in setup.
		-- if we're in setup we don't need to fire the hook anyway so this is fine
		local buffer = package.loaded['qalc.buffer']
		if type(buffer) == 'table' and buffer.options_changed then
			buffer.options_changed(parse_changed)
		end
	end
end

local function set_keys(tgt, keys, v)
	for i = 1, #keys - 1 do
		local k = keys[i]

		if type(tgt[k]) ~= 'table' then
			-- resetting an absent child should not create an empty parent
			if v == nil then return end
			tgt[k] = {}
		end

		tgt = tgt[k]
	end

	tgt[keys[#keys]] = v
end

function M.setup(new_cfg)
	local opt_groups
	new_cfg, opt_groups = options.normalize_cfg(new_cfg)

	deep_extend_inplace(M.cfg, new_cfg)
	rehighlight()

	if M.cfg.display.diagnostics ~= false then
		vim.diagnostic.config(M.cfg.display.diagnostics, ns_ui)
	end

	apply_option_groups(opt_groups)
end

function M.set_option(path, val)
	local updates = options.normalize_cmd(path, val)
	local opt_groups = {}

	for _, update in ipairs(updates) do
		local group = update.group

		if not opt_groups[group] then
			opt_groups[group] = vim.deepcopy(M.cfg[group])
		end

		set_keys(opt_groups[group], update.keys, update.val)
	end

	apply_option_groups(opt_groups)
end

function M.options_snapshot()
	return {
		parse = M.cfg.parse_options,
		print = M.cfg.print_options,
		evaluation = M.cfg.evaluation_options,
	}
end

function M.show_options()
	vim.notify(vim.inspect(M.options_snapshot()), vim.log.levels.INFO, {
		title = 'qalc options',
	})
end

rehighlight()

return M
