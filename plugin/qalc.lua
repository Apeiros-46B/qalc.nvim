-- initializes plugin
local qalc = require('qalc')

-- {{{ create commands
-- Qalc
vim.api.nvim_create_user_command('Qalc',
    function(tbl)
        -- create a new buffer and attach to it
        qalc.new_buf(tbl.args, tbl.bang)
        qalc.attach.current()
    end,
    -- 0 or 1 args
    { nargs = '?', bang = true }
)

-- QalcAttach
vim.api.nvim_create_user_command('QalcAttach', function(_) qalc.attach.current() end, { nargs = 0 })

-- QalcYank
vim.api.nvim_create_user_command('QalcYank',
    function(tbl)
        qalc.yank.current(tbl.args or qalc.config.yank_default_register or '')
    end,
    { nargs = '?' }
)
-- }}}

-- automatically attach to files with extension set in config
if qalc.config.attach_extension ~= '' then
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'BufRead' }, {
        pattern = { qalc.config.attach_extension },
        command = 'QalcAttach',
    })
end
