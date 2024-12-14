-- {{{ user commands
vim.api.nvim_create_user_command('Qalc',
	function(cmd)
		local buffer = require('qalc.buffer')
		buffer.new_buf(cmd.args)
		buffer.attach()
	end,
	{ nargs = '?' }
)

vim.api.nvim_create_user_command('QalcAttach',
	function(_)
		require('qalc.buffer').attach()
	end,
	{ nargs = 0 }
)

vim.api.nvim_create_user_command('QalcYank',
	function(cmd)
		require('qalc.buffer').yank(
			cmd.args or require('qalc.config').cfg.yank_default_register or ''
		)
	end,
	{ nargs = '?' }
)
-- }}}

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
	pattern = { '*.qalc' },
	command = 'QalcAttach',
})
