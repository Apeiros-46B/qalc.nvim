// this is horrible and honestly most of it is LLM written, but it works (i think)
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

#include <algorithm>
#include <cctype>
#include <string>
#include <sstream>
#include <vector>

#include <libqalculate/Function.h>
#include <libqalculate/MathStructure.h>
#include <libqalculate/Unit.h>
#include <libqalculate/Variable.h>

#include "math.hpp"

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

void extract_symbols(
	const MathStructure& ast,
	std::vector<std::string>& in_syms,
	std::vector<std::string>& out_syms,

	const std::vector<std::string>& local_vars,
	bool is_top_level
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
			if (ast.countChildren() < 2) break;

			// getChild is one-indexed for some strange reason
			const MathStructure* lhs = ast.getChild(1);
			const MathStructure* rhs = ast.getChild(2);
			if (lhs == nullptr || rhs == nullptr) break;

			std::string lhs_str;
			if (!get_canonical_name(*lhs, lhs_str)) break;

			// since we disable implicit multiplication, we don't need to reconstruct symbols
			if (is_valid_var_name(lhs_str)) {
				out_syms.push_back(lhs_str);
				extract_symbols(*rhs, in_syms, out_syms, local_vars, false);
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
							out_syms.push_back(canonical_target);
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
								out_syms.push_back(sig);
							}
						} else {
							std::string f_name = sig.substr(0, paren_start);
							f_name.erase(
								std::remove_if(f_name.begin(), f_name.end(), ::isspace),
								f_name.end()
							);

							if (is_valid_var_name(f_name)) {
								out_syms.push_back(f_name);
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
					extract_symbols(*rhs, in_syms, out_syms, new_locals, false);
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
			extract_symbols(*child, in_syms, out_syms, local_vars, false);
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
