-- parses output from Qalculate

-- {{{ utility
-- {{{ patterns for parsing
-- TODO: test and add RPN commands

-- {{{ expressions that should not be allowed
local illegal_cmds = {
    '^clear$',
    '^find', '^list',
    '^exrates$',
    '^help',
    '^info',
    '^mode$',
    '^store',
    '^quit$', '^exit$',

    '^/$' -- "unknown command"
}
-- }}}

-- {{{ expressions that output the previous value (no output if no previous value)
local output_previous_cmds = {
    '^approximate$',
    '^assume',
    '^base',
    '^clear history$',
    '^exact$',
    -- `expand` outputs `0 = 0` if no previous value for some reason
    -- same with `partial fraction`
    '^set',
    '^to', '^convert', '^%-%>'
}
-- }}}

-- {{{ expressions that do not produce output at all
local no_output_cmds = {
    -- misc
    '^%#%s*.*$', -- comment
    '^%s*$',     -- line with either nothing or only whitespace

    -- commands
    '^delete',
    '^function',
    '^MC$', '^MS$', '^M%+$', '^M%-$',
    '^save',
}
-- }}}

-- {{{ patterns for diagnostics
local non_prefixed_warnings = {
    unrecognized_opt = '^Unrecognized option%.$',
    unrecognized_asm = '^Unrecognized assumption%.$',
    illegal_val = '^Illegal value%.$',
}

local diagnostic_patterns = {
    error  = '^error: (.+)$',
    warn   = '^warning: (.+)$',
    npwarn = '^npwarning: (.+)$' -- originally non-prefixed warnings
}
-- }}}
-- }}}

-- {{{ match against multiple patterns
local function matches_any(s, patterns)
    for _, pattern in pairs(patterns) do
        if string.find(s, pattern) ~= nil then return true end
    end

    return false
end
-- }}}

-- {{{ check if an expression returns output
local has_previous_output = false

local function outputs(line)
    -- check for expressions that return no output
    if matches_any(line, no_output_cmds) then return false end

    -- check for expressions that only return output if there is a previous result
    if matches_any(line, output_previous_cmds) then return has_previous_output end

    -- otherwise, there is output
    has_previous_output = true
    return true
end
-- }}}

-- {{{ make diagnostic
local diagnostic_template = {
    col = 0,
    end_col = -1,
    source = 'qalc',
}

local function diagnostic(severity, message, lnum, bufnr)
    local new = vim.fn.copy(diagnostic_template)

    new.severity = severity
    new.message = message
    new.lnum = lnum
    new.bufnr = bufnr

    return new
end
-- }}}
-- }}}

-- {{{ parse input
local function parse_input(input)
    local illegal = {}

    for i, line in pairs(input) do
        -- check for illegal commands
        if matches_any(line, illegal_cmds) then
            input[i] = '' -- do nothing for this command
            illegal[#illegal+1] = i -- used for diagnostics
            break
        end
    end

    return input, illegal
end
-- }}}

-- {{{ get results from raw output
-- (remove input and leading/trailing spaces)
local function get_results(raw_output, input_length)
    -- {{{ remove all input expressions
    local results = {}

    -- iterate over lines of raw output starting from input index
    for i = input_length, #raw_output do
        -- add result to results table
        results[#results+1] = raw_output[i]
    end
    -- }}}

    -- {{{ trim leading and trailing spaces
    for i, v in pairs(results) do
        -- remove
        v = string.gsub(v, '\\r$', '') -- trailing CR (left from CRLF on Win32)
        v = string.gsub(v, '^%s+', '') -- leading
        v = string.gsub(v, '%s+$', '') -- trailing

        -- set value
        results[i] = v
    end
    -- }}}

    return results
end
-- }}}

-- {{{ prepare results for parsing
-- (remove everything before the last equals sign)
local function prepare_results(results)
    local new_results = {}

    -- iterate over results
    for i, result in pairs(results) do
        if matches_any(result, diagnostic_patterns) then
            -- shouldn't remove before equals sign, this is a diagnostic
            new_results[i] = result
        elseif matches_any(result, non_prefixed_warnings) then
            -- make it easier to parse
            new_results[i] = 'npwarning: ' .. result
            table.insert(new_results, i + 1, '')
        elseif string.find(result, '[≈=]') == nil then
            -- there are no equals signs
            new_results[i] = result
        else
            -- match everything after last equals sign
            new_results[i] = string.match(result, '[≈=] ([^≈=]*)$')
        end
    end

    return new_results
end
-- }}}

-- {{{ helper function for parsing
local function find_results(parsed, results, result_i, input_i, has_output, bufnr)
    -- get result
    local result = results[result_i]
    if result == nil then return result_i end

    -- match patterns
    local error   = string.match(result, diagnostic_patterns.error)
    local warn    = string.match(result, diagnostic_patterns.warn)
    local setwarn = string.match(result, diagnostic_patterns.npwarn)

    -- {{{ find
    -- error
    if has_output and error ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.ERROR,
            error, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + 1, input_i, has_output, bufnr)
    -- warn
    elseif has_output and warn ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.WARN,
            warn, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + 1, input_i, has_output, bufnr)
    -- warning from set or related commands
    elseif setwarn ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.WARN,
            setwarn, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + (has_output and 1 or 2), input_i, has_output, bufnr)
    -- normal/no diagnostics needed
    else
        -- add result
        parsed.results[input_i] = (has_output and results[result_i] or '')
        return result_i + 1
    end
    -- }}}

end
-- }}}

-- {{{ parse results
local function parse_results(bufnr, raw_output, inputs, illegal, config)
    -- {{{ prepare
    -- create table
    local parsed = { results = {}, diagnostics = {} }

    -- get only the results
    local results = get_results(raw_output, config.use_pty and #inputs or 1)
    results[#results] = nil -- remove last newline
    results = prepare_results(results) -- make terse

    -- indices
    local input_i = 1
    local result_i = 1
    -- }}}

    -- {{{ loop
    while true do
        -- get input line
        local input = inputs[input_i]
        if input == nil then break end

        -- check if the input line returns output
        if outputs(input) then -- has output
            result_i = find_results(parsed, results, result_i, input_i, true, bufnr)
        else -- has no output
            find_results(parsed, results, result_i, input_i, false, bufnr)
        end

        input_i = input_i + 1
    end
    -- }}}

    -- {{{ add illegal commands to diagnostics
    for _, i in pairs(illegal) do
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.HINT,
            'This command is designed to be used in an interactive session; it has been disabled in qalc.nvim.',
            i - 1, bufnr
        )
    end
    -- }}}

    return parsed
end
-- }}}

-- return module
return { input = parse_input, results = parse_results }
