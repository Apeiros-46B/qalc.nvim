if exists("b:current_syntax")
	finish
endif

let b:current_syntax = "qalc"
syn iskeyword a-z,A-Z,48-57,_

syn match   qalcName     '\a*'
" TODO: add these programmatically somehow, dont want to write them all down
syn keyword qalcConstant e i pi infinity undefined true false yes no ans ans1 ans2 ans3 ans4 ans5 answer today tomorrow uptime precision thousand million billion trillion
syn keyword qalcFunction lcm gcd abs floor ceil trunc round int frac im re sqrt root sin cos tan sec csc cot sinh cosh tanh sech csch coth asin acos atan atan2 asec acsc acot asinh acosh atanh asech acsch acoth exp exp2 exp10 log log2 log10 ln limit diff derivative integrate integral extremum sum product dimension inv det identity matrix matrix2vector vector dot cross magnitude mean median mode stderr stdev solve solve2 replace
syn match   qalcUnknown  /'[^']*'\|"[^"]*"\|\\\a\|[jknpqrvwxyzEIMOQXYZ]*\(\a\@!\)/
syn match   qalcOperator '[+\-*/^%!&|=]\|to'
syn match   qalcComment  '#.*$'
syn match   qalcLiteral  '-\?\d\+\(\.\d\+\)\?\(e-\?\d\+\)\?' " decimal
syn match   qalcLiteral  '-\?0x\x\+\(\.\x\+\)\?\(p-\?\d\+\)\?' " hexadecimal
syn match   qalcLiteral  '-\?0o\o\+\(\.\o\+\)\?' " octal
syn match   qalcLiteral  '-\?0b[01]\+\(\.[01]\+\)\?' " binary

hi def link qalcLiteral  Number
hi def link qalcConstant Number
hi def link qalcFunction Function
hi def link qalcUnknown  Type
hi def link qalcOperator Operator
hi def link qalcComment  Comment
