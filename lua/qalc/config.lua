-- handle qalc.nvim configuration
local ns = vim.api.nvim_create_namespace('qalc')

-- {{{ default configuration
local cfg = {
	-- extra command arguments to pass to `qalc`
	-- '-t'/'--terse' WILL BREAK the plugin
	-- example: { '--set', 'angle deg' } to use degrees as the default angle unit
	cmd_args = {}, -- table

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

	-- sign shown before result
	sign = '=', -- string

	-- whether or not to show a sign before the result
	show_sign = true, -- boolean

	-- whether or not to right align virtual text
	right_align = false, -- boolean

	-- whether or not to show multiline output as virtual lines
	show_multiline = true, -- boolean

	-- highlight groups
	highlights = {
		sign	           = '@conceal', -- sign before result
		result           = '@string',  -- result in virtual text
		result_multiline = '@string',  -- result in subsequent virtual lines
	},

	-- diagnostic options
	-- set to nil to respect the options in your Neovim configuration
	-- (see `:h vim.diagnostic.config()`)
	diagnostics = { -- table?
		underline = true,
		virtual_text = false,
		signs = true,
		update_in_insert = true,
		severity_sort = true,
	}
}
-- }}}

-- {{{ validate config
local function validate()
	for k, arg in cfg.cmd_args do
		if arg == '-t' or arg == '--terse' then
			vim.notify(
				"The '--terse' flag is not necessary and not supported by qalc.nvim.",
				vim.log.levels.WARN
			)
			cfg.cmd_args[k] = nil
		end
	end
end
-- }}}

-- {{{ setup with user overrides
local function setup(new_cfg)
	require('qalc.util').deep_extend(cfg, new_cfg)
	validate()

	if cfg.diagnostics ~= nil then
		vim.diagnostic.config(cfg.diagnostics, ns)
	end
end
-- }}}

return {
	cfg   = cfg,
	setup = setup,
}
