qalc.nvim has been completely rewritten and is not backwards-compatible with
the first version. It is a lot faster and less buggy now, and has some
additional features, so it should be worth it to switch in most cases. If you
don't want to or can't migrate, use the `legacy` branch, which is no longer
maintained.

Most of the incompatibilities arise from no longer using a `qalc` subprocess to
eval

# Improvements

- More features (syntax highlighting, cmp autocomplete, hover docs)
- Much better performance due to incremental recalculation + not using a
subprocess
- Structured outputs and diagnostics, avoids guessing which output lines
belonged to which expressions which fixes the weird multiline bugs of v1.
Multiline output is fully supported now
- Other bugfixes

# Incompatibilities

## Install/config

- A native build step is now required, see the new [install instructions in the
main README](README.md#installation)
- The config schema has changed, see the [new one in the main
README](README.md#configuration)

## Usage

`:QalcAttach` has been removed, use `:setfiletype qalc` instead. Also, your
existing files may no longer work depending on what features they use:

- Evaluation order of a file is not top to bottom anymore, it goes in
dependency order instead. This means dependencies can be declared after their
dependents in the file
- Repeated definitions are now errors, use unique names for sequence-like behavior
- The original `qalc` CLI's shared preferences and definitions are not loaded
- CLI/session behaviors like `set`/`assume`/`base`/`ans`/RPN stack commands are
not supported anymore. For the first three, see [Runtime option
setting](README.md#runtime-option-setting). Instead of `ans`, use named
variables. RPN stack manipulation commands are not planned to be supported due
to the new eval order, but RPN syntax itself can still be enabled with the
`parsing_mode` option
- Implicit multiplication is limited and unknown symbol parsing is on to allow
building a dependency graph. For the former, change `xy` to `x y`. `2x` is
still fine as-is. The latter probably shouldn't affect much
- `function f ...\x` definitions aren't supported anymore, use `f(x) := ...x`
instead

## Additional

See [Unfinished](README.md#unfinished) and [Quirks](README.md#quirks) sections
in the main README for additional detail.
