> [!IMPORTANT]
> This branch is not ready for use. There are still a few issues that need to be addressed before it is merged to main.

# TODO

- Implement a way to alter `ParseOptions`, `PrintOptions`, and `EvaluationOptions` (this is normally done with `set` in the `qalc` program, but qalc.nvim now uses the library directly, so this functionality needs to be separately addressed)
- Write CMake files for dependencies so that users don't have to have `pkg-config` installed in order to build the plugin

# qalc.nvim

*inspired by [quickmath.nvim](https://github.com/jbyuki/quickmath.nvim)*

A Neovim plugin for reactive spreadsheet-like calculations with unit conversions, algebra, calculus, graph plotting, and more. Powered by [`libqalculate`](https://github.com/Qalculate/libqalculate).

![screenshot](assets/screenshot.png)

## Features

- For supported functions, constants, units, etc, see [the `libqalculate` README](github.com/Qalculate/libqalculate#examples-expressions)
- Syntax highlighting
- Plotting (use `plot(f(x))` function)
- Warnings and errors from expressions are shown as diagnostics
- [`nvim-cmp`](https://github.com/hrsh7th/nvim-cmp) integration for autocomplete of functions, constants, variables, and units

## Installation

Requires CMake, pkg-config, LuaJIT, and libqalculate to be installed.

Install using your preferred plugin manager:

- [vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'Apeiros-46B/qalc.nvim', { 'do': { -> luafile build.lua } }
```

- [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{
    'Apeiros-46B/qalc.nvim',
    opts = {},
}
```

You can lazy load if you want (with `ft = 'qalc', cmd = 'Qalc'`) but most of the plugin loading is already deferred.

### cmp integration

Add `{ name = 'qalc' }` to your cmp sources. Loading should work perfectly if you use lazy.nvim. I have not tested cmp integration on other plugin managers.

### Nix

If you have [Nix](https://nixos.org/) available on your system, you can use it to build the C++ backend:

```vim
Plug 'Apeiros-46B/qalc.nvim', { 'do': { -> luafile build_nix.lua } }
```

```lua
{
    'Apeiros-46B/qalc.nvim',
    build = 'build_nix.lua',
    opts = {},
}
```

## Usage

Edit a file with extension `.qalc` or use the `:Qalc` command.
The `:Qalc` command optionally accepts one argument; the name of the newly created buffer.

Alternatively, you can attach to an existing buffer using `:QalcAttach`.

You can yank the result on the current line with `:QalcYank`, which takes an optional register (see `:h setreg()`). The default register can be configured (see below).

If the state of the buffer is somehow broken, you can use `:QalcReset` to force a rebuild of the dependency graph and re-evaluate every line.

With the exception of interactive session commands (like `set`, `delete`, `info` etc), all lines are evaluated like `qalc` commands.

## Potentially unexpected behaviours

- 1:1 feature parity with `qalc` CLI frontend is a non-goal. Calling `qalc` as a subprocess is slow and prone to bugs, and perfectly emulating its behaviour using the C++ library is almost impossible [due to how complex their frontend is](https://github.com/Qalculate/libqalculate/blob/master/src/qalc.cc). Notable features that will not be supported are interactive commands (like `set` and `delete`), `ans` variables, and the legacy `function` syntax (use `f(x) := ...` instead).
- If you constantly switch between multiple huge qalc buffers, you may experience some lag. This is due to a technical limitation of `libqalculate` (the `Calculator` is a stateful singleton), so the plugin has to clear the state and re-evaluate the entire buffer when you switch to it.
- The buffer does not evaluate top-down like code; defined variables can referenced anywhere (akin to a 1D spreadsheet with named values).

## Configuration

To configure, call the `setup` function.

```lua
require('qalc').setup({
    -- your config goes here
})
```

Keep in mind that this plugin is still under development so configuration keys may change or be removed at any time.

<details>
  <summary>Default configuration</summary>

  TODO: update this section when configuration is finalized

  ```lua
  local config = {
      -- extra command arguments for Qalculate
      -- do NOT use the option `-t`/`--terse`; it will break the plugin
      -- example: { '--set', 'angle deg' } to use degrees as the default angle unit
      cmd_args = {}, -- table

      -- default name of a newly opened buffer
      -- set to '' to open an unnamed buffer
      bufname = '', -- string

      -- the plugin will set all attached buffers to have this filetype
      -- set to '' to disable setting the filetype
      -- the default is provided for basic syntax highlighting
      set_ft = 'config', -- string

      -- file extension to automatically attach qalc to
      -- set to '' to disable automatic attaching
      attach_extension = '*.qalc', -- string

      -- default register to yank results to
      -- default register = '@'
      -- clipboard        = '+'
      -- X11 selection    = '*'
      -- other registers not listed are also supported
      -- see `:h setreg()`
      yank_default_register = '@', -- string

      -- sign shown before result
      sign = '=', -- string

      -- whether or not to show a sign before the result
      show_sign = true, -- boolean

      -- whether or not to right align virtual text
      right_align = false, -- boolean

      -- highlight groups
      highlights = {
          sign     = '@conceal', -- sign before result
          result   = '@string',  -- result in virtual text
      },

      -- diagnostic options
      -- set to nil to respect the options in your neovim configuration
      -- (see `:h vim.diagnostic.config()`)
      diagnostics = { -- table?
          underline = true,
          virtual_text = false,
          signs = true,
          update_in_insert = true,
          severity_sort = true,
      }
  }
  ```
</details>
