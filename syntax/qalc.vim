if exists("b:current_syntax")
	finish
endif

let b:current_syntax = "qalc"
syn iskeyword a-z,A-Z,_

syn match   qalcName     '\a*'
" TODO: add these programmatically somehow, dont want to write them all down
syn keyword qalcConstant e i pi infinity undefined true false yes no answer today tomorrow uptime precision thousand million billion trillion
syn match   qalcConstant 'ans[1-5]\?\|L\d\+'
syn keyword qalcFunction plot lcm gcd abs floor ceil trunc round int frac im re sqrt root sin cos tan sec csc cot sinh cosh tanh sech csch coth asin acos atan atan2 asec acsc acot asinh acosh atanh asech acsch acoth ln limit diff derivative integrate integral extremum sum product dimension inv det identity vector dot cross magnitude mean median mode stderr stdev total horzcat vertcat mergevectors multisolve replace if for foreach
syn match   qalcFunction 'exp2\|exp10\|exp\|log2\|log10\|log\|matrix2vector\|matrix\|solve2\|solve'
syn match   qalcUnknown  /'[^']*'\|"[^"]*"\|\\\a\|[jknpqrvwxyzEIMOQXYZ]*\(\a\@!\)/
syn match   qalcOperator '[+\-*/^%!&|<>=]\|to'
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
