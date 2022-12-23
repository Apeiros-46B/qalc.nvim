-- parses output from Qalculate

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
-- }}}

-- {{{ check if an expression returns output
local previous_output = false

local function outputs(line)
    -- check for expressions that return no output
    for _, pattern in pairs(no_output_cmds) do
        if string.find(line, pattern) ~= nil then return false end
    end

    -- check for expressions that only return output if there is a previous result
    for _, pattern in pairs(output_previous_cmds) do
        if string.find(line, pattern) ~= nil then return previous_output end
    end

    -- otherwise, there is output
    previous_output = true
    return true
end
-- }}}

-- {{{ parse input
local function parse_input(input)
    local illegal = {}

    for i, line in pairs(input) do
        for _, pattern in pairs(illegal_cmds) do
            if string.find(line, pattern) ~= nil then
                input[i] = '' -- do nothing for this command
                illegal[#illegal+1] = i -- used for diagnostics
                break
            end
        end
    end

    return input, illegal
end
-- }}}

-- {{{ parse results
-- {{{ get results (remove input and leading/trailing spaces)
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

-- {{{ make results terse (remove everything before the last equals sign)
local function make_terse(results)
    local new_results = {}

    -- iterate over results
    for i, result in pairs(results) do
        -- make sure there are equals signs
        if string.find(result, '=') == nil then
            -- there are no equals signs
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

-- {{{ parse results
local function parse_results(bufnr, raw_output, inputs, illegal_indices)
    -- create table
    local parsed = { results = {}, diagnostics = {} }

    -- {{{ process given parameters
    -- get only the results
    local results = get_results(raw_output, #inputs)
    results[#results] = nil -- remove last newline
    results = make_terse(results)
    -- }}}

    -- {{{ parse
    -- indices
    local input_i = 1
    local result_i = 1

    -- {{{ template for diagnostics
    local diagnostic_template = {
        bufnr = bufnr,
        col = 0,
        end_col = -1,
        source = 'qalc',
    }
    -- }}}

    -- loop
    while true do
        -- get input line
        local input = inputs[input_i]
        if input == nil then break end

        -- check if the input line returns output
        if outputs(input) then -- has output
            -- get result line
            local result = results[result_i]
            if result == nil then break end

            -- {{{ check for diagnostics
            local error = string.match(result, '^error: (.+)$')
            local warn = string.match(result, '^warning: (.+)$')

            if error ~= nil then -- error
                -- {{{ get diagnostic
                local diagnostic = vim.fn.copy(diagnostic_template)

                diagnostic.severity = vim.diagnostic.severity.ERROR
                diagnostic.message = error
                diagnostic.lnum = input_i - 1

                parsed.diagnostics[#parsed.diagnostics+1] = diagnostic
                -- }}}

                -- get result
                parsed.results[input_i] = results[result_i + 1]

                -- inc 2 times
                result_i = result_i + 2
            elseif warn ~= nil then -- warn
                -- {{{ get diagnostic
                local diagnostic = vim.fn.copy(diagnostic_template)

                diagnostic.severity = vim.diagnostic.severity.WARN
                diagnostic.message = warn
                diagnostic.lnum = input_i - 1

                parsed.diagnostics[#parsed.diagnostics+1] = diagnostic
                -- }}}

                -- get result
                parsed.results[input_i] = results[result_i + 1]

                -- inc 2 times
                result_i = result_i + 2
            else -- no diagnostic
                -- get result
                parsed.results[input_i] = results[result_i]

                -- inc once
                result_i = result_i + 1
            end
            -- }}}
        else -- has no output
            parsed.results[input_i] = ''
        end

        input_i = input_i + 1
    end
    -- }}}

    -- {{{ add illegal commands to diagnostics
    for _, i in pairs(illegal_indices) do
        local diagnostic = vim.fn.copy(diagnostic_template)

        diagnostic.severity = vim.diagnostic.severity.HINT
        diagnostic.message = 'This command is disabled in qalc.nvim due to their being designed for interactive use'
        diagnostic.lnum = i - 1

        parsed.diagnostics[#parsed.diagnostics+1] = diagnostic
    end
    -- }}}

    return parsed
end
-- }}}
-- }}}

-- {{{ parse, run, and show
-- TODO: move to init.lua
local previous_job = 0

local function process_contents(namespace, input, config)
    -- stop previous job
    vim.fn.jobstop(previous_job)

    -- parse input
    local new_input, illegal_indices = parse_input(input)

    -- start new job
    previous_job = require('qalc.calc').run(new_input, config, function(_, raw_output, _)
        -- get bufnr
        local bufnr = vim.fn.bufnr()

        -- parse output
        local parsed = parse_results(bufnr, raw_output, new_input, illegal_indices)

        -- update
        require('qalc.show').update_all(namespace, bufnr, config, parsed)
    end)
end
-- }}}

return { process_contents = process_contents }
