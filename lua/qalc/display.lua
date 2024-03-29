-- displays parsed results in the form of virtual text and diagnostics

-- lines are 1-indexed
-- vtexts[bufnr][lnum]
local vtexts = {}

-- {{{ clear
-- virtual text
local function clear_vtext(namespace, bufnr)
    vtexts[bufnr] = nil
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

-- diagnostics
local function clear_diagnostics(namespace, bufnr)
    vim.diagnostic.reset(namespace, bufnr)
end

-- everything
local function clear_all(namespace, bufnr)
    clear_vtext(namespace, bufnr)
    clear_diagnostics(namespace, bufnr)
end
-- }}}

-- {{{ update
-- {{{ virtual text
local function update_vtext(namespace, bufnr, config, results)
    -- clear existing virtual text
    clear_vtext(namespace, bufnr)
    vtexts[bufnr] = {}

    -- exit if no results
    if #results == 0 then return end

    -- {{{ iterate over results
    for lnum, result in pairs(results) do
        -- make sure line is non-empty
        if result ~= '' then
            -- {{{ set extmark
            local show_sign = config.show_sign and config.sign ~= '' and config.sign ~= nil

            vtexts[bufnr][lnum] = result

            vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
                -- text
                virt_text = {
                    -- sign
                    (show_sign and {
                        config.sign .. ' ',
                        config.highlights.sign
                    } or nil),

                    -- result
                    { result, config.highlights.result },
                },

                -- position
                virt_text_pos = config.right_align and 'right_align' or 'eol',

                -- highlight mode
                hl_mode = 'combine',
            })
            -- }}}
        end
    end
    -- }}}
end
-- }}}

-- {{{ diagnostics
local function update_diagnostics(namespace, bufnr, diagnostics)
    vim.diagnostic.set(namespace, bufnr, diagnostics)
end
-- }}}

-- {{{ everything
local function update_all(namespace, bufnr, config, items)
    update_vtext(namespace, bufnr, config, items.results)
    update_diagnostics(namespace, bufnr, items.diagnostics)
end
-- }}}
-- }}}

-- {{{ return module
return {
    vtexts = vtexts,

    -- {{{ clear
    clear = {
        all = clear_all,
        vtext = clear_vtext,
        diagnostics = clear_diagnostics,
    },
    -- }}}

    -- {{{ update
    update = {
        all = update_all,
        vtext = update_vtext,
        diagnostics = update_diagnostics,
    },
    -- }}}
}
-- }}}
