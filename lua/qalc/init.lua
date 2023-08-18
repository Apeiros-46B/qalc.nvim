-- handles setup and defines main functions

-- our namespace
local namespace = vim.api.nvim_create_namespace('qalc')

-- {{{ config & setup
-- {{{ default configuration
local config = {
    -- default name of a newly opened buffer
    -- set to '' or nil to open an unnamed buffer
    bufname = nil, -- string?

    -- extra command arguments for Qalculate
    -- do NOT use the option `-t`/`--terse`; it will break the plugin
    -- example: { '--set', 'angle deg' } to use degrees as the default angle unit
    cmd_args = nil, -- table?

    -- the plugin will set all attached buffers to have this filetype
    -- set to '' or nil to disable setting the filetype
    -- the default is provided for basic syntax highlighting
    set_ft = 'config', -- string?

    -- file extension to automatically attach qalc to
    -- set to '' or nil to disable automatic attaching
    attach_extension = '*.qalc', -- string?

    -- default register to yank results to
    -- default register = '@', '', or nil
    -- clipboard        = '+'
    -- X11 selection    = '*'
    -- other registers not listed are also supported
    -- see `:h setreg()`
    yank_default_register = nil, -- string?

    -- sign shown before result
    sign = '=', -- string

    -- whether or not to show a sign before the result
    show_sign = true, -- boolean

    -- whether or not to right align virtual text
    right_align = false, -- boolean

    -- highlight groups
    highlights = {
        sign     = '@conceal', -- sign before result
        result   = '@string',  -- result in virtual text
    },

    -- diagnostic options
    -- set to nil to respect the options in your neovim configuration
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
local function new_buf(name)
    -- get command
    local cmd = 'enew'

    if name ~= '' and name ~= nil then
        cmd = 'e ' .. name
    elseif config.bufname ~= '' and config.bufname ~= nil then
        cmd = 'e ' .. config.bufname
    end

    -- run command
    vim.cmd(cmd)
end
-- }}}

-- {{{ attach & detach
local should_detach = {}
local attached = {}

-- {{{ attach
local function attach(bufnr)
    -- don't attach if already attached
    if attached[bufnr] then
        return true
    end

    -- should not detach now
    should_detach[bufnr] = nil

    -- make sure buffer is loaded
    vim.fn.bufload(bufnr)

    -- {{{ create callback
    local callback = function()
        -- detach if we should detach
        if should_detach[bufnr] then
            attached[bufnr] = false
            return true
        end

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

    -- add bufnr to attached table
    attached[bufnr] = true
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

-- {{{ yank results
local function yank(bufnr, register)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local val = require('qalc.display').vtexts[bufnr][lnum]
    if val ~= nil then
        vim.fn.setreg(register, val)
    end
end
-- }}}

-- {{{ return module
return {
    -- config
    config = config,
    setup = setup,

    -- new buffer
    new_buf = new_buf,

    -- attach
    attach = {
        buf = attach,
        current = function() attach(vim.api.nvim_get_current_buf()) end,
    },

    -- detach
    detach = {
        buf = detach,
        current = function() detach(vim.api.nvim_get_current_buf()) end,
    },

    -- yank
    yank = {
        buf = yank,
        current = function(register)
            yank(vim.api.nvim_get_current_buf(), register)
        end,
    }
}
-- }}}
