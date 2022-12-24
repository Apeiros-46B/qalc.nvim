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
    '^save', '^store',
}
-- }}}

-- {{{ patterns for diagnostics
local diagnostic_patterns = {
    error = '^error: (.+)$',
    warn = '^warning: (.+)$',
    unrecognized_opt = '^Unrecognized option%.$',
    unrecognized_asm = '^Unrecognized assumption%.$',
    illegal_val = '^Illegal value%.$',
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
        v = string.gsub(v, '^%s+', '') -- leading
        v = string.gsub(v, '%s+$', '') -- trailing

        -- set value
        results[i] = v
    end
    -- }}}

    return results
end
-- }}}

-- {{{ make results terse
-- (remove everything before the last equals sign)
local function make_terse(results)
    local new_results = {}

    -- iterate over results
    for i, result in pairs(results) do
        -- make sure there are equals signs
        if string.find(result, '=') == nil then
            -- there are no equals signs
            new_results[i] = result
        elseif matches_any(result, diagnostic_patterns) then
            -- shouldn't remove before equals sign, this is a diagnostic
            new_results[i] = result
        elseif string.find(result, '^save') ~= nil then
            -- shouldn't show result, we are saving a variable
            new_results[i] = ''
        else
            -- match everything after last equals sign
            new_results[i] = string.match(result, '= ([^=]*)$')
        end
    end

    return new_results
end
-- }}}

-- {{{ recursive helper function for parsing
local function find_results(parsed, results, result_i, input_i, has_output, bufnr)
    -- get result
    local result = results[result_i]
    if result == nil then return result_i end

    -- match patterns
    local error = string.match(result, diagnostic_patterns.error)
    local warn = string.match(result, diagnostic_patterns.warn)
    local unrecognized_opt = string.match(result, diagnostic_patterns.unrecognized_opt)
    local unrecognized_asm = string.match(result, diagnostic_patterns.unrecognized_asm)
    local illegal_val = string.match(result, diagnostic_patterns.illegal_val)

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
    -- unrecognized option
    elseif unrecognized_opt ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.WARN,
            unrecognized_opt, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + 1, input_i, has_output, bufnr)
    -- unrecognized assumption
    elseif unrecognized_asm ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.WARN,
            unrecognized_asm, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + 1, input_i, has_output, bufnr)
    -- illegal value
    elseif illegal_val ~= nil then
        -- add diagnostic
        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic(
            vim.diagnostic.severity.WARN,
            illegal_val, input_i - 1, bufnr
        )

        -- recurse
        return find_results(parsed, results, result_i + 1, input_i, has_output, bufnr)
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
local function parse_results(bufnr, raw_output, inputs, illegal_indices)
    -- {{{ prepare
    -- create table
    local parsed = { results = {}, diagnostics = {} }

    -- get only the results
    local results = get_results(raw_output, #inputs)
    results[#results] = nil -- remove last newline
    results = make_terse(results) -- make terse

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
    for _, i in pairs(illegal_indices) do
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
