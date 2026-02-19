// sym extraction is horrible and honestly some of it is LLM written, but it works
// we rely on these assumptions:
// - limit_implicit_multiplication is forced true (otherwise this would be impossible)
// - legacy `function f 2\x` syntax is forbidden (use f(x) := 2x instead)

// FIX: nested equality-like assignments are broken:
// -> `a = b = 1` assigns the value `b = 1` (whether b is equal to 1) to `a`
//    currently the algorithm treats `a` as an input symbol instead of output
//    (this should be b is input, a is output)
// -> `a = b = c = 1` assigns the value `b = c = 1` (whether b == c == 1) to `a`
//    (this should be b, c are input, a is output)
//
// nested := assignments seem to be fine though; `a := b := 1` assigns 1 to both
// `a` and `b` as expected, and the algorithm treats both `a` and `b` as output

// FIX: save() to define functions with implicit parameters probably doesn't work

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <sstream>
#include <vector>

extern "C" {
#include "lua.h"
}
#include <libqalculate/Calculator.h>
#include <libqalculate/DataSet.h>
#include <libqalculate/Function.h>
#include <libqalculate/MathStructure.h>
#include <libqalculate/Prefix.h>
#include <libqalculate/Unit.h>
#include <libqalculate/Variable.h>
#include <libqalculate/includes.h>

#include "math.hpp"
#include "util.hpp"

Definition::Definition() {}

Definition::Definition(LspKind type, std::string ref_name):
	type{type}, ref_name{ref_name}, input_name{ref_name}, documentation{""}
{}

void Definition::to_lua(lua_State* L, const Definition& self) {
	lua_createtable(L, 0, 5);

	lua::push_and_set(L, static_cast<int>(self.type), "type");
	lua::push_and_set(L, self.ref_name, "ref_name");
	lua::push_and_set(L, self.input_name, "input_name");
	lua::push_and_set(L, self.documentation, "documentation");

	lua::make_array<std::string>(L, self.all_names);
	lua_setfield(L, -2, "all_names");
}

// similar logic to libqalculate/qalc.cc "bool show_object_into(string name)"
void populate_def(
	Calculator* calc,
	Variable* var,
	PrintOptions po,
	Definition& def
) {
	std::string val;

	if (var->isKnown()) {
		def.type = LspKind::CONST;
		val = calc->print(static_cast<KnownVariable*>(var)->get(), 100, po);
	} else {
		def.type = LspKind::VAR;
		def.documentation += ": Unknown Variable";
		val = calc->print(var, 100, po);
	}

	if (!val.empty()) {
		def.documentation += " = `" + val + "`";
	}
}

static std::string split_composite(CompositeUnit* unit, PrintOptions po) {
	return unit->print(po, true, TAG_TYPE_TERMINAL, false, false);
}

void populate_def(
	Calculator* calc,
	Unit* unit,
	PrintOptions po,
	Definition& def
) {

	def.type = LspKind::UNIT;

	switch (unit->subtype()) {
		case SUBTYPE_BASE_UNIT: {
			def.documentation += " (Base unit)";
			break;
		}
		case SUBTYPE_ALIAS_UNIT: {
			AliasUnit* alias = static_cast<AliasUnit*>(unit);
			def.documentation += " -> `";

			// only show the scale factor if it's not 1
			std::string relation = calc->localizeExpression(alias->expression() );
			if (relation != "1") {
				def.documentation += relation + " ";
			}

			Unit* base = alias->firstBaseUnit();
			std::string base_name;
			if (base->subtype() == SUBTYPE_COMPOSITE_UNIT) {
				if (relation == "1") {
					// unscaled alias pointing to a composite (N -> kg m/s^2)
					// we should split it
					base_name = split_composite(static_cast<CompositeUnit*>(base), po);
				} else {
					// scaled alias (hp -> 745.69 W)
					base_name = base->preferredDisplayName(
						po.abbreviate_names,
						po.use_unicode_signs
					).name;
				}
			} else {
				// alias pointing to another type of unit
				base_name = base->print(po);
			}
			def.documentation += base_name + "`";

			if (!alias->inverseExpression().empty()) {
				def.documentation += "\n\n**Inverse relation**: `" + base_name + " -> ";
				def.documentation += calc->localizeExpression(alias->inverseExpression()).c_str();
				def.documentation += " " + alias->print(po) + "`";
			}

			bool is_relative = false;
			if (!alias->uncertainty(&is_relative).empty()) {
				std::string uncertainty = calc->localizeExpression(alias->uncertainty());
				def.documentation += "\n\n**Uncertainty:** `" + uncertainty + "`";
				if (is_relative) {
					def.documentation += " (relative)";
				}
			}

			break;
		}
		case SUBTYPE_COMPOSITE_UNIT: {
			CompositeUnit* composite = static_cast<CompositeUnit*>(unit);
			def.documentation += " = `" + split_composite(composite, po) + "`";
			break;
		}
		default: {
			std::string val = calc->print(unit, 100, po);
			if (!val.empty()) {
				def.documentation += " = `" + val + "`";
			}
		}
	}
}

void populate_def(
	Calculator* calc,
	MathFunction* func,
	PrintOptions po,
	Definition& def
) {
	def.type = LspKind::FUNC;

	int args_count = func->maxargs();
	if (args_count < 0) {
		args_count = std::max(
			static_cast<int>(func->lastArgumentDefinitionIndex()),
			func->minargs() + 1
		);
	}

	std::string sig = "\n\n**Signature**: `" + def.input_name + "(";
	std::string arg_list;

	if (args_count == 0) {
		sig += ")`";
	} else {
		arg_list = "\n\n**Arguments**:\n";

		for (int i = 1; i <= args_count; ++i) {
			Argument* arg = func->getArgumentDefinition(i);

			std::string arg_name;
			std::string arg_desc;

			if (arg && !arg->name().empty()) {
				arg_name = arg->name();
			} else {
				// fallback to numbered arguments
				arg_name = "argument";
				if (i > 1 || func->maxargs() != 1) {
					arg_name += " " + std::to_string(i);
				}
			}

			if (arg) {
				arg_desc = strings::preprocess_str(arg->printlong());
			} else {
				// fallback to generic argument description
				arg_desc = "a free value";
			}

			bool is_opt = (i > func->minargs());

			if (i > 1) {
				sig += is_opt ? "[, " : ", ";
			} else {
				sig += is_opt ? "[" : "";
			}
			sig += arg_name;

			if (is_opt) {
				sig += "]";
			}

			arg_list += "- `" + arg_name + "`: " + arg_desc;
			if (is_opt) {
				arg_list += " *(optional)*";
				std::string default_val = func->getDefaultValue(i);
				if (!default_val.empty() && default_val != "\"\"") {
					arg_list += " *(default: " + default_val + ")*";
				}
			}
			if (i != args_count) {
				arg_list += "\n";
			}
		}

		if (func->maxargs() < 0) {
			sig += ", ...";
		}

		sig += ")`";
	}

	def.documentation += sig + arg_list;

	// dataset handling (e.g. `atom()`)
	if (func->subtype() == SUBTYPE_DATA_SET) {
		DataSet* set = static_cast<DataSet*>(func);
		def.documentation += "\n\n**Properties**:\n";

		DataPropertyIter it;
		DataProperty* prop = set->getFirstProperty(&it);

		while (prop) {
			if (!prop->isHidden()) {
				std::string prop_str = "- ";

				if (!prop->title(false).empty()) {
					prop_str += "**" + prop->title() + "**: ";
				}

				for (size_t i = 1; i <= prop->countNames(); i++) {
					if (i > 1) prop_str += ", ";
					prop_str += "`" + prop->getName(i) + "`";
				}

				if (prop->isKey()) {
					prop_str += " *(key)*";
				}

				if (!prop->description().empty()) {
					std::string desc = prop->description();
					prop_str += "\n  " + strings::preprocess_str(desc, true);
				}

				def.documentation += prop_str + "\n";
			}
			prop = set->getNextProperty(&it);
		}
	}

	// expression macros like `gammainc = gamma(\x)-igamma(\x,\y)`
	if (func->subtype() == SUBTYPE_USER_FUNCTION) {
		UserFunction* userfunc = static_cast<UserFunction*>(func);

		// TODO: do we need to pass ParseOptions in here?
		std::string expr_str = calc->unlocalizeExpression(userfunc->formula());

		for (size_t i = 1; i <= userfunc->countSubfunctions(); ++i) {
			std::string search = "\\" + std::to_string(i);
			std::string replace = userfunc->getSubfunction(i);

			size_t pos = 0;
			while ((pos = expr_str.find(search, pos)) != std::string::npos) {
				expr_str.replace(pos, search.length(), replace);
				pos += replace.length();
			}
		}

		if (!expr_str.empty()) {
			def.documentation += "\n\n**Expression**: `" + expr_str + "`";
		}
	}
}

void push_prefix_def(
	Calculator* calc,
	Prefix* pref,
	PrintOptions po,
	std::vector<Definition>& defs
) {
	Definition def;
	def.type = LspKind::ENUM_MB;
	def.ref_name = pref->referenceName();
	def.input_name = pref->preferredInputName().name;

	get_all_names(pref, def.all_names);

	std::string disp_name = pref->longName(po.use_unicode_signs);
	std::string disp_abbr = pref->shortName(po.use_unicode_signs);

	def.documentation = "**" + disp_name + "**";
	if (!disp_abbr.empty() && disp_abbr != disp_name) {
		def.documentation += " (" + disp_abbr + ")";
	}

	std::string type;
	std::string value;

	switch (pref->type()) {
		case PREFIX_BINARY: {
			int exp = static_cast<BinaryPrefix*>(pref)->exponent();
			value = "2^" + std::to_string(exp);
			type = "Binary prefix";
			break;
		}
		case PREFIX_DECIMAL: {
			int exp = static_cast<DecimalPrefix*>(pref)->exponent();
			value = "10^" + std::to_string(exp);
			type = "Decimal prefix";
			break;
		}
		default: {
			value = pref->value().print(po);
			type = "Prefix";
			break;
		}
	}

	if (!value.empty()) {
		def.documentation += " = `" + value + "`";
	}
	def.documentation += "\n\n**" + type + "**";

	defs.push_back(std::move(def));
}

bool is_valid_var_name(const std::string& s) {
	if (s.empty()) return false;
	if (s == "undefined") return false;
	if (!std::isalpha(s[0]) && s[0] != '_') return false;
	for (char c : s) {
		if (!std::isalnum(c) && c != '_') return false;
	}
	return true;
}

std::string clean_symbol_name(std::string s, bool strip_escapes) {
	// remove accidental spaces
	s.erase(std::remove_if(s.begin(), s.end(), ::isspace), s.end());

	// remove escapes if needed (for LHS definitions)
	if (strip_escapes && !s.empty()) {
		// handle quote escapes (e.g., 'x' -> x or "x" -> x)
		if (s.length() >= 2) {
			if ((s.front() == '\'' && s.back() == '\'') ||
				(s.front() == '"' && s.back() == '"')) {
				s = s.substr(1, s.length() - 2);
			}
		}
		// handle backslash escape (e.g., \x -> x)
		if (s.front() == '\\') {
			s = s.substr(1);
		}
	}

	return s;
}

bool get_canonical_name(const MathStructure& ast, std::string& out) {
	switch (ast.type()) {
		case STRUCT_SYMBOLIC: {
			out = ast.symbol();
			return true;
		}
		case STRUCT_VARIABLE: {
			out = ast.variable()->referenceName();
			return true;
		}
		case STRUCT_UNIT: {
			out = ast.unit()->referenceName();
			return true;
		}
		default: return false;
	}
}

#define SKIP_WHILE(i, s, pred) while (i < s.length() && pred(s[i])) i++;

// check if string starts with "VAR =" (ignore ==, !=, <=, etc)
static std::string get_assignment_target(const std::string& s) {
	if (s.empty()) {
		return "";
	}

	size_t i = 0;
	SKIP_WHILE(i, s, isspace);
	if (i >= s.length()) {
		return "";
	}

	// don't start identifiers with digits
	if (isdigit(s[i])) {
		return "";
	}

	// don't start with an equals sign if it stands alone, but unicode like "µ" is valid
	// safe bet: check for '='
	if (s[i] == '=') {
		return "";
	}

	// capture identifier
	size_t start = i;
	while (i < s.length() && !isspace(s[i]) && s[i] != '=') {
		// standard operators might split tokens but for "var =", usually it looks like
		// "var =" or "var=". if it's "a+b=", that is a comparison, not assignment
		char c = s[i];
		if (c == '+' || c == '-' || c == '*' || c == '/' ||
			c == '^' || c == '!' || c == '<' || c == '>') {
			return "";
		}
		i++;
	}

	if (i == start) {
		return "";
	}
	std::string var_name = s.substr(start, i - start);

	SKIP_WHILE(i, s, isspace);

	if (i < s.length() && s[i] == '=') {
		// don't match '=='
		if (i + 1 < s.length() && s[i+1] == '=') {
			return "";
		}

		// check prev char, make sure it isn't <, >, !, ~
		if (i > 0) {
			char prev = s[i-1];
			if (prev == '<' || prev == '>' || prev == '!' || prev == '~') {
				return "";
			}
		}

		return var_name;
	}
	return "";
}

void extract_symbols(
	const MathStructure& ast,
	std::vector<std::string>& in_syms,
	std::vector<Definition>& out_syms,

	bool is_top_level,
	const std::string& payload,
	const std::vector<std::string>& local_vars
) {
	switch (ast.type()) {
		// although quoted symbols (like 'x') evaluate to themselves and don't depend on the
		// value of the underlying variable, sometimes variables are parsed as symbols, so we
		// should consider them anyways
		case STRUCT_SYMBOLIC: {
			PrintOptions po;
			po.use_unicode_signs = false;
			std::string printed = ast.print(po);

			// literal symbols and implicit parameters (\x) are in single quotes (e.g., 'x')
			// unknown variables/functions are enclosed in double quotes (e.g., "fghi")
			if (!printed.empty() && printed.front() == '\'') {
				break; // ignore single quoted symbols and implicit parameters entirely
			}

			std::string name = ast.symbol();
			if (!is_valid_var_name(name)) break;
			if (std::find(local_vars.begin(), local_vars.end(), name) == local_vars.end()) {
				in_syms.push_back(name);
			}
			break;
		}

		case STRUCT_VARIABLE:
		case STRUCT_UNIT: {
			std::string name;
			if (!get_canonical_name(ast, name)) break;

			// leave escapes intact for RHS dependencies
			name = clean_symbol_name(name, false);
			if (!is_valid_var_name(name)) break;
			if (std::find(local_vars.begin(), local_vars.end(), name) == local_vars.end()) {
				in_syms.push_back(name);
			}
			break;
		}

		case STRUCT_COMPARISON: {
			if (!is_top_level) break;
			if (ast.comparisonType() != ComparisonType::COMPARISON_EQUALS) break;
			if (ast.countChildren() < 1) break;

			// getChild is one-indexed for some strange reason
			const MathStructure* lhs = ast.getChild(1);
			const MathStructure* rhs = ast.getChild(2);
			if (lhs == nullptr) break;

			std::string lhs_str;
			if (!get_canonical_name(*lhs, lhs_str)) break;

			// since we disable implicit multiplication, we don't need to reconstruct symbols
			if (is_valid_var_name(lhs_str)) {
				out_syms.push_back({LspKind::VAR, lhs_str});
				if (rhs != nullptr) {
					extract_symbols(*rhs, in_syms, out_syms, false, "", local_vars);
				}
				return;
			}
			break;
		}

		case STRUCT_FUNCTION: {
			if (ast.function() != nullptr) {
				std::string fn_name = ast.function()->name();

				// qalc rewrites explicit assignment (:=) as save()
				if (fn_name == "save" && ast.countChildren() >= 2) {
					const MathStructure* rhs = ast.getChild(1);
					const MathStructure* lhs = ast.getChild(2);
					if (lhs == nullptr || rhs == nullptr) break;

					std::vector<std::string> new_locals = local_vars;
					std::string canonical_target;

					if (!lhs->isSymbolic() && get_canonical_name(*lhs, canonical_target)) {
						canonical_target = clean_symbol_name(canonical_target, true);
						if (is_valid_var_name(canonical_target)) {
							out_syms.push_back({LspKind::VAR, canonical_target});
						}
					} else {
						// no canonical name; it's a function signature
						PrintOptions po;
						po.use_unicode_signs = false;
						std::string sig = clean_symbol_name(lhs->print(po), true);

						size_t paren_start = sig.find('(');
						if (paren_start == std::string::npos) {
							// no parentheses, plain variable assignment like x := 1
							if (is_valid_var_name(sig)) {
								out_syms.push_back({LspKind::VAR, sig});
							}
						} else {
							std::string f_name = sig.substr(0, paren_start);
							f_name.erase(
								std::remove_if(f_name.begin(), f_name.end(), ::isspace),
								f_name.end()
							);

							if (is_valid_var_name(f_name)) {
								out_syms.push_back({LspKind::FUNC, f_name});
							}

							size_t paren_end = sig.find(')');
							if (paren_end != std::string::npos) {
								std::string args_str = sig.substr(
									paren_start + 1,
									paren_end - paren_start - 1
								);
								std::stringstream ss(args_str);
								std::string arg;
								while (std::getline(ss, arg, ',')) {
									arg = clean_symbol_name(arg, true);
									if (is_valid_var_name(arg)) {
										new_locals.push_back(arg);
									}
								}
							}
						}
					}
					extract_symbols(*rhs, in_syms, out_syms, false, "", new_locals);
					return;
				} else {
					// normal function call (e.g., sin(x) or myfunc(5))
					if (!is_valid_var_name(fn_name)) break;
					if (std::find(local_vars.begin(), local_vars.end(), fn_name) == local_vars.end()) {
						in_syms.push_back(fn_name);
					}
				}
			}
			break;
		}

		default:
			break;
	}

	// fallback for others
	for (size_t i = 1; i <= ast.countChildren(); ++i) {
		if (const MathStructure* child = ast.getChild(i)) {
			extract_symbols(*child, in_syms, out_syms, false, "", local_vars);
		}
	}

	// promote inputs to outputs in incomplete equality-assignments "a ="
	if (is_top_level && out_syms.empty() && !payload.empty()) {
		std::string target = get_assignment_target(payload);

		if (!target.empty()) {
			auto it = std::find_if(
				in_syms.begin(),
				in_syms.end(),
				[&](const std::string& sym) { return sym == target; }
			);
			if (it != in_syms.end()) {
				out_syms.push_back({LspKind::VAR, *it});
				in_syms.erase(it);
			} else {
				// it wasn't in the in_syms
				out_syms.push_back({LspKind::VAR, target});
			}
		}
	}
}

const char* struct_type(StructureType type) {
	switch (type) {
		case STRUCT_MULTIPLICATION: return "mult";
		case STRUCT_INVERSE:        return "inv";
		case STRUCT_DIVISION:       return "slash";
		case STRUCT_ADDITION:       return "add";
		case STRUCT_NEGATE:         return "sub";
		case STRUCT_POWER:          return "pow";
		case STRUCT_NUMBER:         return "num";
		case STRUCT_UNIT:           return "unit";
		case STRUCT_SYMBOLIC:       return "sym";
		case STRUCT_FUNCTION:       return "fn";
		case STRUCT_VARIABLE:       return "var";
		case STRUCT_VECTOR:         return "vec";
		case STRUCT_BITWISE_AND:    return "band";
		case STRUCT_BITWISE_OR:     return "bor";
		case STRUCT_BITWISE_XOR:    return "bxor";
		case STRUCT_BITWISE_NOT:    return "bnot";
		case STRUCT_LOGICAL_AND:    return "and";
		case STRUCT_LOGICAL_OR:     return "or";
		case STRUCT_LOGICAL_XOR:    return "xor";
		case STRUCT_LOGICAL_NOT:    return "not";
		case STRUCT_COMPARISON:     return "cmp";
		case STRUCT_UNDEFINED:      return "undef";
		case STRUCT_ABORTED:        return "aborted";
		case STRUCT_DATETIME:       return "datetime";

		default: return "?";
	}
}

std::string dump_ast(const MathStructure& ast) {
	std::string res = struct_type(ast.type());

	if (ast.type() == STRUCT_VARIABLE || ast.type() == STRUCT_SYMBOLIC ||
		ast.type() == STRUCT_UNIT || ast.type() == STRUCT_NUMBER || ast.type() == STRUCT_FUNCTION) {
		res += "[" + ast.print() + "]";
	}

	if (ast.countChildren() > 0) {
		res += " {";
		for (size_t i = 1; i <= ast.countChildren(); ++i) {
			if (const MathStructure* child = ast.getChild(i)) {
				res += dump_ast(*child);
				if (i < ast.countChildren()) res += ", ";
			}
		}
		res += "}";
	}
	return res;
}
