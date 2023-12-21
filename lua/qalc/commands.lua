-- setup user commands and autocommands
local buffer = require('qalc.buffer')

-- {{{ user commands
vim.api.nvim_create_user_command('Qalc',
	function(cmd)
		buffer.new_buf(cmd.args)
		buffer.attach.current()
	end,
	{ nargs = '?' }
)

vim.api.nvim_create_user_command('QalcAttach',
	function(_)
		buffer.attach.current()
	end,
	{ nargs = 0 }
)

vim.api.nvim_create_user_command('QalcYank',
	function(cmd)
		buffer.yank.current(
			nil,
			cmd.args or require('qalc.config').cfg.yank_default_register or ''
		)
	end,
	{ nargs = '?' }
)
-- }}}

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'BufRead' }, {
	pattern = { '*.qalc' },
	command = 'QalcAttach',
})
