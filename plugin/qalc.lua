-- initializes plugin
local qalc = require('qalc')

-- create :Qalc command
vim.api.nvim_create_user_command('Qalc',
    function(tbl)
        -- create a new buffer and attach to it
        qalc.newbuf(tbl.args)
        qalc.attach_current()
    end,
    -- 0 or 1 args
    { nargs = '?' }
)

-- automatically attach to files with extension set in config
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'BufRead' }, {
    pattern = { qalc.config.attach_extension },
    callback = qalc.attach_current,
})
