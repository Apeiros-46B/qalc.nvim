#pragma once

#include <functional>
#include <limits>
#include <map>
#include <string>
#include <vector>

#include "options.hpp"

namespace options {

// validation rules for an option
enum class Kind { BOOLEAN, ENUM, INTEGER, BASE };

// additional assignments caused by setting an option
enum class Coupling {
	NONE,
	SEPARATORS, // setting ignore_comma disables ignore_dot and decimal_comma
	PARSING_MODE, // setting or resetting parsing_mode resets rpn_syntax
};

struct Choice {
	long long input; // qalc CLI numeric code
	long long value; // underlying setter value
	std::vector<std::string> labels; // names, first one is canonical
};
using Choices = std::vector<Choice>;

// how to set or reset a specific option
struct Binding {
	using Setter = std::function<void(Options&, Calculator*, long long)>;
	using Resetter = std::function<void(Options&, Calculator*)>;

	Setter set;
	Resetter reset;

	Binding(Setter set = {}, Resetter reset = {});
};

struct Option {
	std::string name;
	std::vector<std::string> aliases;
	// value -> another target option
	// for example:
	// - exp=10 -> scientific_notation
	// - exp=e -> exp_display=e
	// - exp=pow10 -> exp_display=pow10
	std::map<std::string, std::string> redirects;

	Kind kind;
	Choices choices;
	Coupling coupling = Coupling::NONE;
	Binding binding;

	std::vector<long long> excluded;
	long long min = std::numeric_limits<int>::min();
	long long max = std::numeric_limits<int>::max();
	bool reparse = false;
	bool accept_boolean = false;

	// find an option choice with the given name
	const Choice* find_choice(const std::string& text) const;

	// find an option choice with the given numeric value
	const Choice* find_choice(long long input) const;

	// return all valid values as strings
	std::vector<std::string> candidates() const;
};

// boolean control for another option, e.g. exact=true becomes approximation=0
struct Shortcut {
	std::string name;
	std::vector<std::string> aliases;
	const char* target; // in the exact=true example, this is "approximation"
	long long off;
	long long on; // in the exact=true example, this is 0
};

// a validated set/reset operation
struct Assignment {
	const Option* opt;
	long long value;
	bool reset;
	std::string label;
	long long display_num;

	static Assignment from_choice(const Option& opt, const Choice& choice);
	static Assignment from_integer(const Option& opt, long long input);
	static Assignment make_reset(const Option& opt);
	bool is_same_value(const Assignment& other) const;
	void push_display(lua_State* L) const;
};

class Assignments {
public:
	static Assignments read(lua_State* L, int index, bool reset);
	void push_receipt(lua_State* L) const;
	ConfigUpdate to_update() const;

private:
	std::map<std::string, Assignment> entries;

	static Assignment parse_assignment(lua_State* L, int index, const Option& opt);
	static Assignment read_assignment(
		lua_State* L,
		const std::string& name,
		int index,
		bool reset
	);
	void insert(const Assignment& assignment);
	void add(const Assignment& assignment);
};

}
