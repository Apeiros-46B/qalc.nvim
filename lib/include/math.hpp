#pragma once

#include <string>
#include <vector>

#include <libqalculate/Calculator.h>
#include <libqalculate/MathStructure.h>

// check if a string is a single symbol
bool is_valid_var_name(const std::string& s);

// clean a symbol name, optionally removing backslashes and quotes
std::string clean_symbol_name(std::string s, bool strip_escapes);

// get the canonical name of the given symbol, variable, or unit.
// returns false if the structure is not of those types
bool get_canonical_name(const MathStructure& ast, std::string& out);

// extract dependency information from a structure
// we need to handle a lot of horrific edge cases because qalc's grammar is very complex
// * assignment vs comparison:
// -> abc = 5 looks like an equation but gets transformed into save(5, 'abc') during eval
// -> f(x) = 5x is an equation, NOT a definition or assignment! function defs are f(x) := 5x
// * quoted symbols (e.g. 'x')
// -> when on the LHS of a equality (=)/assignment (:=) or in save(5, 'x'), it saves the
//    value to the UNQUOTED expression. 'x' evaluates to 'x' but x now evaluates to 5.
//    therefore, the unquoted symbol (x) should be tracked as an out sym
// -> when on the RHS of an equality/..., it (quoted or not) should NOT be counted as a
//    dependency because it evaluates to a symbol instead of the actual value
// -> backslashed symbols (\x) seem to have the same behaviour EXCEPT in function defs,
//    in which they serve as implicit positional args (\x = 1st argument, \y = 2nd, etc)
void extract_symbols(
	const MathStructure& ast,
	std::vector<std::string>& in_syms,
	std::vector<std::string>& out_syms,

	// temporary state for recursion
	const std::vector<std::string>& local_vars = {},
	bool is_top_level = true
);

// debug: print the type of a structure
const char* struct_type(StructureType type);

// debug: print the AST of a structure
std::string dump_ast(const MathStructure& ast);
