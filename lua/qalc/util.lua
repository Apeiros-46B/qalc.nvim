-- vim.tbl_deep_extend returns a new table (new reference), this mutates the original table
local function tbl_deep_extend(dest, src)
    for k, v in pairs(src) do
        if type(v) ~= 'table' then
            dest[k] = v
        else
            tbl_deep_extend(dest[k], v)
        end
    end
end

return {
    tbl_deep_extend = tbl_deep_extend,
}
