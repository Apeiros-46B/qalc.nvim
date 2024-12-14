-- handle qalc.nvim configuration
local ns = vim.api.nvim_create_namespace('qalc')

-- {{{ default configuration
local cfg = {
	-- default name of a newly opened buffer
	bufname = '', -- string

	-- default register to yank results to
	-- default register = '@'
	-- clipboard        = '+'
	-- X11 selection    = '*'
	-- other registers not listed are also supported
	-- see `:h setreg()`
	yank_default_register = '@', -- string

	display = {
		-- sign shown before result (false to disable)
		sign = '=', -- string or false

		-- whether or not to right align virtual text
		right_align = false, -- boolean

		-- display style for multiline results
		-- 'below': virtual lines below
		-- 'collapse': make multiline results single-line
		-- 'extend': virtual text at end of line + aligned virtual lines
		multiline_style = 'below', -- boolean

		-- highlight groups
		highlights = {
			sign	 = '@conceal', -- sign before result
			result = '@string',  -- result in virtual text
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
	},
}
-- }}}

-- {{{ setup with user overrides
local function deep_extend_inplace(dest, src)
	for k, v in pairs(src) do
		if type(v) ~= 'table' then
			dest[k] = v
		else
			deep_extend_inplace(dest[k], v)
		end
	end
end

local function setup(new_cfg)
	deep_extend_inplace(cfg, new_cfg)
	if cfg.diagnostics ~= false then
		vim.diagnostic.config(cfg.diagnostics, ns)
	end
end
-- }}}

return {
	cfg   = cfg,
	setup = setup,
}
