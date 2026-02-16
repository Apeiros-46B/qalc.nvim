-- handle qalc.nvim configuration
local ns_ui = vim.api.nvim_create_namespace('qalc_ui')

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

		-- highlight groups (see `:h nvim_set_hl()`)
		highlights = { -- table
			sign = { link = '@conceal' }, -- sign before result
			result = { link = '@string' }, -- normal result
			flash = { fg = 'fg' } -- flashing result
		},

		flash = { -- table
			enable = true, -- boolean
			duration = 0.05, -- how long each step should be, in seconds
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

	_sign_hl = 'QalcSign',
	_result_hl = 'QalcResult',
	_flash_hl = 'QalcFlash',
}

local function rehighlight()
	vim.api.nvim_set_hl(0, M.cfg._sign_hl, M.cfg.display.highlights.sign)
	vim.api.nvim_set_hl(0, M.cfg._result_hl, M.cfg.display.highlights.result)
	vim.api.nvim_set_hl(0, M.cfg._flash_hl, M.cfg.display.highlights.flash)
end

local function deep_extend_inplace(dest, src)
	for k, v in pairs(src) do
		if type(v) ~= 'table' then
			dest[k] = v
		else
			deep_extend_inplace(dest[k], v)
		end
	end
end

function M.setup(new_cfg)
	deep_extend_inplace(M.cfg, new_cfg)
	rehighlight()
	if M.cfg.diagnostics ~= false then
		vim.diagnostic.config(M.cfg.diagnostics, ns_ui)
	end
end

rehighlight()

return M
