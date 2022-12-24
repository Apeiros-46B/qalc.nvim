# qalc.nvim

*inspired by [quickmath.nvim](https://github.com/jbyuki/quickmath.nvim)*

A Neovim plugin that creates/attaches to a buffer and runs [`qalc`](https://github.com/Qalculate/libqalculate) on the contents

![screenshot](assets/screenshot.png)

## Features

- Automatically evaluates [`qalc`](https://github.com/Qalculate/libqalculate) commands in a Neovim buffer and shows results in virtual text
- Shows warnings and errors as Neovim diagnostics

## Installation

Requires the [`qalc`](https://github.com/Qalculate/libqalculate) binary executable and in `PATH`.

Install using your preferred plugin manager:

- [vim-plug](https://github.com/junegunn/vim-plug).
```vim
Plug 'Apeiros-46B/qalc.nvim'
```

- [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use 'Apeiros-46B/qalc.nvim'
```

## Usage

Edit a file with extension `.qalc` or use the `:Qalc` command.  
The `:Qalc` command optionally accepts one argument, which will be used as the name of the newly created buffer.

All commands/expressions accepted in the buffer are no different from [`qalc`](https://github.com/Qalculate/libqalculate) commands.

## Configuration

To configure, call the `setup` function

```lua
require('qalc').setup({
    -- your config goes here
})
```

<details>
  <summary>Default configuration</summary>

  ```lua
  local config = {
      -- default name of a newly opened buffer
      -- leave empty or nil to open an unnamed buffer
      bufname = '', -- string

      -- extra command arguments for Qalculate
      -- do NOT use the option `-t`/`--terse`; it will break the plugin
      -- example: { '--set', 'angle deg' } to use degrees as the default angle unit
      cmd_args = {}, -- table

      -- the plugin will set all attached buffers to have this filetype
      set_ft = 'qalc', -- string

      -- file extension to automatically attach qalc to
      attach_extension = '*.qalc', -- string

      -- whether or not to show a sign before the result
      show_sign = true, -- boolean

      -- sign shown before result
      sign = '=', -- string

      -- whether or not to right align virtual text
      right_align = false, -- boolean

      -- highlight groups
      highlights = {
          number   = '@number',
          operator = '@operator',
          unit     = '@field',
          sign     = '@conceal', -- sign before result
          result   = '@string',  -- result in virtual text
      },

      -- diagnostic options
      -- this can also be set to `nil` to respect the options in your neovim configuration
      -- (see `:h vim.diagnostic.config()`)
      diagnostics = { -- table|nil
          underline = true,
          virtual_text = false,
          signs = true,
          update_in_insert = true,
          severity_sort = true,
      }
  }
  ```
</details>

## Planned Features

List of features I will most likely implement in the near future (if I have enough free time)

- Keyboard shortcut to copy result
- Syntax highlighting
- Less buggy parser (especially for `set` command)
- (Long-term) [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) integration for completion of variables, functions, and units
