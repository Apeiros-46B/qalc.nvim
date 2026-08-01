-- commands
vim.api.nvim_create_user_command('Qalc',
	function(cmd)
		local buffer = require('qalc.buffer')
		buffer.new_buf(cmd.args)
		buffer.attach()
	end,
	{ nargs = '?' }
)
vim.api.nvim_create_user_command('QalcAttach',
	function(_) require('qalc.buffer').attach() end,
	{ nargs = 0 }
)
vim.api.nvim_create_user_command('QalcReset',
	function(_) require('qalc.buffer').hard_reset() end,
	{ nargs = 0 }
)
vim.api.nvim_create_user_command('QalcYank',
	function(cmd)
		local register = cmd.args
		if register == '' then
			register = require('qalc.config').cfg.yank_default_register or ''
		end
		require('qalc.output').yank_result(register)
	end,
	{ nargs = '?' }
)

local augroup = vim.api.nvim_create_augroup('QalcBufferManagement', { clear = true })

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
	group = augroup,
	pattern = { '*.qalc' },
	callback = function(args)
		require('qalc.buffer').attach(args.buf)
	end,
})

-- sync state whenever focusing a buffer
vim.api.nvim_create_autocmd('BufEnter', {
	group = augroup,
	pattern = '*',
	callback = function(args)
		vim.schedule(function()
			require('qalc.buffer').focus_buffer(args.buf)
		end)
	end
})
