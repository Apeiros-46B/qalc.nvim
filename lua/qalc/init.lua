-- handles setup and defines main functions

-- our namespace
local namespace = vim.api.nvim_create_namespace('qalc')

-- {{{ config & setup
-- {{{ default configuration
local config = {
    -- default name of a newly opened buffer
    -- leave empty or nil to open an unnamed buffer
    bufname = '', -- string

    -- extra command arguments for Qalculate
    -- do NOT use the option `-t`/`--terse`; it will break the plugin
    -- example: { '--set', 'angle deg' } to use degrees as the default angle unit
    cmd_args = {}, -- table

    -- the plugin will set all attached buffers to have this filetype
    set_ft = 'qalc', -- string

    -- file extension to automatically attach qalc to
    attach_extension = '*.qalc', -- string

    -- whether or not to show a sign before the result
    show_sign = true, -- boolean

    -- sign shown before result
    sign = '=', -- string

    -- whether or not to right align virtual text
    right_align = false, -- boolean

    -- highlight groups
    highlights = {
        number   = '@number',
        operator = '@operator',
        unit     = '@field',
        sign     = '@conceal', -- sign before result
        result   = '@string',  -- result in virtual text
    },

    -- diagnostic options
    -- this can also be set to `nil` to respect the options in your neovim configuration
    -- (see `:h vim.diagnostic.config()`)
    diagnostics = { -- table|nil
        underline = true,
        virtual_text = false,
        signs = true,
        update_in_insert = true,
        severity_sort = true,
    }
}
-- }}}

-- {{{ setup function
local function setup(new_config)
    -- extend default config with new keys
    config = vim.tbl_deep_extend('force', config, new_config)

    -- setup diagnostic options for our namespace
    if config.diagnostics ~= nil then
        vim.diagnostic.config(config.diagnostics, namespace)
    end
end
-- }}}
-- }}}

-- {{{ create a buffer
local function newbuf(name)
    -- get command
    local cmd = 'enew'

    if name ~= '' and name ~= nil then
        cmd = 'e ' .. name
    elseif config.bufname ~= '' then
        cmd = 'e ' .. config.bufname
    end

    -- run command
    vim.cmd(cmd)
end
-- }}}

-- {{{ attach & detach
local should_detach = {}

-- {{{ attach
local function attach(bufnr)
    -- should not detach now
    should_detach[bufnr] = nil

    -- make sure buffer is loaded
    vim.fn.bufload(bufnr)

    -- {{{ create callback
    local callback = function()
        -- detach if we should detach
        if should_detach[bufnr] then return true end

        -- get buf contents
        local input = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        -- run job, parser and updater
        require('qalc.job').run(namespace, input, config)
    end
    -- }}}

    -- call the callback now to update
    callback()

    -- attach to buffer updates
    vim.api.nvim_buf_attach(0, false, { on_lines = callback })

    -- set the filetype to desired one
    vim.bo.filetype = config.set_ft
end
-- }}}

-- {{{ detach
local function detach(bufnr)
    -- used in callback
    should_detach[bufnr] = true

    -- clear
    require('qalc.display').clear.all(namespace, bufnr)
end
-- }}}
-- }}}

-- {{{ return module
return {
    -- config
    config = config,
    setup = setup,

    -- new buffer
    newbuf = newbuf,

    -- attach
    attach = attach,
    attach_current = function() attach(vim.fn.bufnr()) end,

    -- detach
    detach = detach,
    detach_current = function() detach(vim.fn.bufnr()) end,
}
-- }}}
