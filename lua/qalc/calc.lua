-- starts Qalculate as a job and sends given input through stdin

local function run(input, config, callback)
    -- get command
    local cmd = vim.tbl_flatten({ 'qalc', '-f', '-', config.cmd_args })

    -- {{{ start a job
    local job = vim.fn.jobstart(
        cmd,
        {
            on_stdout = callback,
            stdout_buffered = true,
            pty = true,
        }
    )
    -- }}}

    -- {{{ send input to job
    -- add EOF as last entry of contents
    input[#input+1] = [[]]

    -- send input
    vim.fn.chansend(job, input)
    vim.fn.chanclose(job, 'stdin')
    -- }}}

    -- return jobid
    return job
end

return { run = run }
