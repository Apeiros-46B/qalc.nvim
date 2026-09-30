# qalc.nvim

*inspired by [quickmath.nvim](https://github.com/jbyuki/quickmath.nvim)*

A Neovim plugin for reactive spreadsheet-like calculations with unit conversions, algebra, calculus, graph plotting, and more. Powered by [`libqalculate`](https://github.com/Qalculate/libqalculate).

![screenshot](assets/screenshot.png)

## Features

- For supported functions, constants, units, etc, see [the `libqalculate` README](https://github.com/Qalculate/libqalculate#examples-expressions)
- Syntax highlighting
- Plotting (use `plot(f(x))` function)
- Warnings and errors from expressions are shown as diagnostics
- [`nvim-cmp`](https://github.com/hrsh7th/nvim-cmp) integration for autocomplete of functions, constants, variables, and units

## Installation

Requires Neovim >=0.12, CMake >=3.10, libqalculate >=5.0.0, LuaJIT, and libuv.
If you want to use the `plot` feature, you also need gnuplot. The libuv headers
and library used to build the plugin must be ABI-compatible with the version
your Neovim was built with.

Install using your preferred plugin manager (example for [lazy.nvim](https://github.com/folke/lazy.nvim)):

```lua
{
    'Apeiros-46B/qalc.nvim',
    opts = {},
}
```

You can lazy load if you want (with `ft = 'qalc', cmd = 'Qalc'`) but most of
the plugin loading is already deferred.

### cmp integration

Add `{ name = 'qalc' }` to your cmp sources.

### Nix build

If you have [Nix](https://nixos.org/) available on your system, you can use it
to build the C++ backend:

```lua
{
    'Apeiros-46B/qalc.nvim',
    build = 'build_nix.lua',
    opts = {},
}
```

## Usage

Edit a file with extension `.qalc` or use the `:Qalc` command. The `:Qalc`
command optionally accepts one argument; the name of the newly created buffer.

Alternatively, you can attach to an existing buffer using `:QalcAttach`.

You can yank the result on the current line with `:QalcYank`, which takes an
optional register (see `:h setreg()`). The default register can be configured
(see below).

If the state of the buffer is somehow broken, you can use `:QalcReset` to force
a rebuild of the dependency graph and re-evaluate every line.

libqalculate's parse, print, and evaluation options can be changed while the
plugin is running. `:QalcSet` accepts a scoped struct field and a value:

```vim
:QalcSet parse.angle_unit radians
:QalcSet print.base hexadecimal
:QalcSet evaluation.approximation exact
```

Use `:QalcSet` without arguments to show the current overrides.

## Potentially unexpected behaviours

- 1:1 feature parity with `qalc` CLI frontend is a non-goal. Calling `qalc` as
  a subprocess (which was what this plugin used to do) is slow and prone to
  bugs, and perfectly emulating its behaviour using the C++ library is almost
  impossible [due to how complex their frontend
  is](https://github.com/Qalculate/libqalculate/blob/master/src/qalc.cc).
  Notable features that will not be supported are interactive commands (like
  `set` and `delete`), `ans` variables, and the legacy `function` syntax (use
  `f(x) := ...` instead).
  - Implicit multiplication of symbols (`xy` = `x * y`) is forcibly disabled
    and cannot be manually re-enabled, because it causes issues with extracting
    symbol dependencies to build the dependency graph. Numeric implicit
    multiplication (`2x`) or implicit multiplication with a space (`x y`) is
    still allowed. The `limit_implicit_multiplication` option cannot be overridden.
  - Unknown-symbol parsing is always enabled so dependency tracking can
    recognize variables before their definitions. The `unknowns_enabled` option
    cannot be overridden.
  - Dependency tracking treats functions and variables as if they were in one
    namespace even though libqalculate treats them as separate, so don't give a
    function and a variable the same name.
- The buffer does not evaluate top-down like code; defined variables can
  be referenced anywhere (akin to a 1D spreadsheet with named values).
- If you have multiple large qalc buffers, you may experience some lag when
  switching between them. This is due to a technical limitation of
  `libqalculate` that I unfortunately can't really do anything about.

<details>
  <summary>Technical details</summary>

  For some reason, the `Calculator` struct in `libqalculate` is a stateful
  singleton and instantiating more than one leads to a double free when their
  destructors fire. My workaround in this plugin is to clear the state and
  re-evaluate the entire buffer when you switch to it, and unfortunately I
  don't think there's a better way.

  I tried juggling multiple `Calculator` structs and swapping out the global
  singleton pointer (which the destructor does some cleanup on, from what I
  could gather), but it seems like the rest of the calculator state like loaded
  definitions is global anyways and not encapsulated within the struct itself,
  making multiple instances useless in the first place and making the double
  free difficult to avoid.
</details>

## Configuration

To configure, call the `setup` function.

```lua
require('qalc').setup({
    -- these option groups are overrides, an empty group means use defaults that
    -- match the default behavior of the `qalc` CLI as closely as possible
	parse_options = {
		angle_unit = 'radians',
	},
	print_options = {
		base = 16,
	},
	evaluation_options = {
		approximation = 'exact',
	},
})
```

<details>
  <summary>Default configuration</summary>

  ```lua
  M.cfg = {
      -- default name of a newly opened buffer
      -- set to '' to open an unnamed buffer
      bufname = '', -- string

      -- default register to yank results to
      -- default register = '@'
      -- clipboard        = '+'
      -- X11 selection    = '*'
      -- other registers not listed are also supported
      -- see `:h setreg()`
      yank_default_register = '@', -- string

      -- libqalculate options, enum values accept names or integers
      --> https://qalculate.github.io/reference/structParseOptions.html
      parse_options = {},
      --> https://qalculate.github.io/reference/structPrintOptions.html
      print_options = {},
      --> https://qalculate.github.io/reference/structEvaluationOptions.html
      evaluation_options = {},

      display = {
          -- sign shown before result (false to disable)
          sign = '=', -- string or false

          -- placeholder shown while result is evaluating (false to disable)
          placeholder = '...', -- string or false

          -- whether or not to right align virtual text
          right_align = false, -- boolean

          -- display style for multiline results
          -- 'below': virtual lines below
          -- 'collapse': make multiline results single-line
          -- 'extend': virtual text at end of line + aligned virtual lines
          multiline_style = 'below', -- string

          -- highlight groups (see `:h nvim_set_hl()`)
          highlights = { -- table
              sign = { link = '@conceal' }, -- sign before result
              result = { link = '@string' }, -- normal result
          },

          -- diagnostic options (false to respect the options in your Neovim config)
          -- (see `:h vim.diagnostic.config()`)
          diagnostics = { -- table or false
              underline = true,
              virtual_text = false,
              signs = true,
              update_in_insert = true,
              severity_sort = true,
          },

          -- hover options
          -- (see `:h vim.lsp.util.open_floating_preview.Opts`)
          hover = {}
      },
  }
  ```
</details>
