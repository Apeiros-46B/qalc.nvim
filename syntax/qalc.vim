if exists("b:current_syntax")
	finish
endif

let b:current_syntax = "qalc"

syn iskeyword @,48-57,$,_,192-255

syn match   qalcName     '\k\+'
syn match   qalcFunction 'exp2\|exp10\|exp\|log2\|log10\|log\|matrix2vector\|matrix\|solve2\|solve'
syn match   qalcUnknown  /'[^']*'\|"[^"]*"\|\\\a\|[knpqrwxyzXYZ]*\(\a\@!\)/
syn match   qalcOperator '[+\-*/^%!&|<>=]\|to\|:='
syn match   qalcComment  '#.*$'
syn match   qalcLiteral  '-\?\d\+\(\.\d\+\)\?\(e-\?\d\+\)\?' " decimal
syn match   qalcLiteral  '-\?0x\x\+\(\.\x\+\)\?\(p-\?\d\+\)\?' " hexadecimal
syn match   qalcLiteral  '-\?0o\o\+\(\.\o\+\)\?' " octal
syn match   qalcLiteral  '-\?0b[01]\+\(\.[01]\+\)\?' " binary

lua<<EOF
local bridge = package.loaded['qalc.bridge']
if bridge then
	bridge.syntax_highlight()
end
EOF

" some of these are generated dynamically, see bridge.lua
hi def link qalcLiteral    Number
hi def link qalcConstant   Constant
hi def link qalcFunction   Function
hi def link qalcPrefixUnit Type
hi def link qalcUnit       Type
hi def link qalcUnknown    Keyword
hi def link qalcOperator   Operator
hi def link qalcComment    Comment
