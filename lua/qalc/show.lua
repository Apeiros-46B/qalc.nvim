-- shows parsed results to user

-- {{{ update virtual text
local function update_vtext(namespace, bufnr, config, results)
    -- clear namespace
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

    -- {{{ iterate over results
    for linenum, result in pairs(results) do
        -- make sure line is non-empty
        if result ~= '' then
            -- {{{ set extmark
            vim.api.nvim_buf_set_extmark(bufnr, namespace, linenum - 1, 0, {
                -- text
                virt_text = {
                    { -- equals sign
                        config.equals_sign and '= ' or '',
                        config.highlights.equals
                    },
                    { result, config.highlights.result }, -- result
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

-- {{{ update diagnostics
local function update_diagnostics(namespace, bufnr, diagnostics)
    vim.diagnostic.set(namespace, bufnr, diagnostics)
end
-- }}}

-- {{{ update everything
local function all(namespace, bufnr, config, items)
    update_vtext(namespace, bufnr, config, items.results)
    update_diagnostics(namespace, bufnr, items.diagnostics)
end
-- }}}

return {
    update_all = all,
    update_vtext = update_vtext,
    update_diagnostics = update_diagnostics
}
