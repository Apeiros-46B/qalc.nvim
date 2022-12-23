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

    -- default filetype to set qalc buffers to
    set_ft = 'qalc', -- string

    -- file extension to automatically attach qalc to
    attach_extension = '*.qalc', -- string

    -- whether or not to show an equals sign before the result
    equals_sign = true, -- boolean

    -- whether or not to right align virtual text
    right_align = false, -- boolean

    -- highlight groups
    highlights = {
        number   = '@number',
        operator = '@operator',
        unit     = '@field',
        equals   = '@conceal', -- equals sign before result
        result   = '@string',  -- result in virtual text
    },

    -- diagnostic options
    diagnostics = {
        -- severities
        -- keys correspond to Qalculate output, values are diagnostic severities
        severity = { -- table
            warning = vim.diagnostic.severity.WARN,
            error = vim.diagnostic.severity.ERROR,
        },

        -- options
        -- this can also be set to `nil` to respect the options in your neovim configuration
        -- (see `:h vim.diagnostic.config()`)
        opts = { -- table|nil
            underline = true,
            virtual_text = false,
            signs = true,
            update_in_insert = true,
            severity_sort = true,
        }
    }
}
-- }}}

-- {{{ setup function
local function setup(new_config)
    -- extend default config with new keys
    config = vim.tbl_deep_extend('force', config, new_config)

    -- setup diagnostic options for our namespace
    vim.diagnostic.config(config.diagnostics.opts, namespace)
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

local function attach(bufnr)
    -- we should not detach
    should_detach[bufnr] = nil

    -- attach
    local callback = function()
        -- detach if we should detach
        if should_detach[bufnr] then return true end

        -- make sure it's loaded
        vim.fn.bufload(bufnr)

        -- get buf contents
        local contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        -- run calculator
        require('qalc.parse').parse(namespace, contents, config)
    end
    vim.api.nvim_buf_attach(0, false, { on_lines = callback })

    -- call the callback now to update
    callback()

    -- set the filetype to desired one
    vim.bo.filetype = config.set_ft
end

local function detach(bufnr)
    should_detach[bufnr] = true
end
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
