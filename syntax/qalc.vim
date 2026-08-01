if exists("b:current_syntax")
	finish
endif

let b:current_syntax = "qalc"

syn iskeyword @,48-57,$,_,192-255

syn match   qalcName     '\k\+'
syn match   qalcFunction '\k\+\ze\s*('
" TODO: enumerate known vs unknown variables from backend
syn match   qalcUnknown  /'[^']*'\|"[^"]*"\|\\\a\|[knpqrwxyzXYZ]*\(\a\@!\)/
syn match   qalcOperator '[+\-*/^%!&|<>=]\|\<to\>\|\<where\>\|:='
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
hi def link qalcUnit       Type
hi def link qalcUnknown    Identifier
hi def link qalcOperator   Operator
hi def link qalcComment    Comment
