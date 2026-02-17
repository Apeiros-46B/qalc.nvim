#pragma once

#include <string>
#include <vector>

#include <libqalculate/MathStructure.h>
#include <libqalculate/Prefix.h>
#include <libqalculate/Unit.h>
#include <libqalculate/Variable.h>
#include <libqalculate/includes.h>

#include "util.hpp"

struct Definition {
	LspKind type;
	std::string ref_name;
	std::string input_name;
	std::string documentation; // fully formatted markdown string
	std::vector<std::string> all_names;

	static const char* to_lua_kv(lua_State* L, const Definition& self);
};

void populate_def(Calculator* calc, Variable* var, PrintOptions po, Definition& def);
void populate_def(Calculator* calc, Unit* unit, PrintOptions po, Definition& def);
void populate_def(
	Calculator* calc,
	MathFunction* func,
	PrintOptions po,
	Definition& def
);

template<typename T>
void get_all_names(T* expr, std::vector<std::string>& all_names) {
	for (size_t i = 1; i <= expr->countNames(); ++i) {
		all_names.push_back(expr->getName(i).name);
	}
}

// make a definition from an expr and push it to a list of definitions
template<typename T>
void push_def(
	Calculator* calc,
	T* expr,
	PrintOptions po,
	std::vector<Definition>& defs
) {
	if (expr->isLocal() || !expr->isActive()) {
		return;
	}

	Definition def;
	def.ref_name = expr->referenceName();
	def.input_name = expr->preferredInputName().name;

	get_all_names(expr, def.all_names);

	std::string disp_name = expr->preferredDisplayName(false, po.use_unicode_signs).name;
	std::string disp_abbr = expr->preferredDisplayName(true, po.use_unicode_signs).name;
	std::string title = expr->title(false, true);

	def.documentation = "**" + disp_name + "**";
	if (!disp_abbr.empty() && disp_abbr != disp_name) {
		def.documentation += " (" + disp_abbr + ")";
	}
	if (!title.empty()) {
		def.documentation += ": " + title;
	}

	populate_def(calc, expr, po, def);

	std::string desc = expr->description();
	if (!desc.empty()) {
		def.documentation += "\n\n" + strings::preprocess_str(desc);
	}

	defs.push_back(std::move(def));
}

// isn't a populate_def overload because it's a special case
void push_prefix_def(
	Calculator* calc,
	Prefix* prefix,
	PrintOptions po,
	std::vector<Definition>& defs
);

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
