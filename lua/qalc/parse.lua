-- TODO: parses output from Qalculate

-- {{{ patterns for parsing
-- TODO: test and add RPN commands

-- {{{ expressions that should not be allowed at all
local illegal_exprs = {
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
local output_previous_exprs = {
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
local no_output_exprs = {
    -- commands
    '^delete',
    '^function',
    '^MC$', '^MS$', '^M%+$', '^M%-$',
    '^save', '^store',

    -- other
    '^%#%s*.*$', -- comment
    '^%s*$',     -- line with either nothing or only whitespace
}
-- }}}

-- {{{ diagnostics
local diagnostic_patterns = {
    ['^error: .+$'] = vim.diagnostic.severity.ERROR,
    ['^warning: .+$'] = vim.diagnostic.severity.WARN,
}
-- }}}
-- }}}

-- {{{ get results (remove input and leading/trailing spaces)
local function get_results(data, input_length)
    -- {{{ remove all input expressions
    local results = {}

    -- iterate over data starting from input index
    for i = input_length, #data do
        -- add result to results table
        results[#results+1] = data[i]
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

-- {{{ make results terse (remove everything before the last equals sign)
local function terse(results)
    local new_results = {}

    -- iterate over results
    for i, result in pairs(results) do
        -- make sure there are equals signs
        if string.find(result, '=') == nil then
            -- no equals signs
            new_results[i] = result
        elseif string.find(result, '^save') ~= nil then
            -- shouldn't show result, we are saving a variable
            new_results[i] = ''
        else
            -- match everything after last equals sign
            new_results[i] = string.match(result, '= [^=]*$')
        end
    end

    return new_results
end
-- }}}

local function add_empty_lines(results, input)
    return results
end

local previous_job = 0
local function parse(namespace, input, config)
    -- stop previous job
    vim.fn.jobstop(previous_job)

    -- start new job
    previous_job = require('qalc.calc').run(input, config, function(job, data, event)
        -- {{{ process returned data
        --> get only results
        local results = get_results(data, #input)

        --> remove last newline
        results[#results] = nil

        --> make terse
        results = terse(results)

        --> add empty lines
        results = add_empty_lines(results, input)
        -- }}}

        -- update virtual text
        require('qalc.show').update_vtext(namespace, vim.fn.bufnr(), config, results)
    end)
end

return { parse = parse }
