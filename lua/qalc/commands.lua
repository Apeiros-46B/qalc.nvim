-- setup user commands and autocommands
local buffer = require('qalc.buffer')
local bridge = require('qalc.bridge')

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

-- definition handling
-- TODO: re-add this when intelligent calculation is added
-- vim.api.nvim_create_autocmd({ 'BufEnter' }, {
-- 	callback = function(args)
-- 		if buffer.is_attached(args.buf) then
-- 			bridge.load_defs(args.buf)
-- 		end
-- 	end,
-- })
-- vim.api.nvim_create_autocmd({ 'BufLeave' }, {
-- 	callback = function(args)
-- 		if buffer.is_attached(args.buf) then
-- 			bridge.save_defs(args.buf)
-- 		end
-- 	end,
-- })
-- vim.api.nvim_create_autocmd({ 'BufUnload', 'BufDelete', 'BufWipeout' }, {
-- 	callback = function(args)
-- 		if buffer.is_attached(args.buf) then
-- 			bridge.clear_defs(args.buf)
-- 			buffer.detach()
-- 		end
-- 	end,
-- })
