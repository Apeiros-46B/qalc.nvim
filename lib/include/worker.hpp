#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

extern "C" {
#include <lauxlib.h>
}
#include <libqalculate/Calculator.h>
#include <libqalculate/includes.h>
#include <uv.h>

#include "math.hpp"
#include "util.hpp"

namespace worker {

static const char* MT = "libqalcbridge.Worker";
void init_mt(lua_State* L);
void init(lua_State* L);

// called from lua
int lua_init_loop(lua_State* L);
int lua_submit_parse_batch(lua_State* L);
int lua_submit_job(lua_State* L);
int lua_set_callback(lua_State* L);

// matches enum in util.lua
enum class JobType: int {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_BATCH = 3,
	EVAL_LINE = 4,
	GET_DEFS = 5,
};

struct Diagnostic {
	Severity severity;
	std::string msg;

	static void to_lua(lua_State* L, const Diagnostic& self);
};

struct ParseInput {
	std::uint64_t stmt_id;
	std::string text;
};

struct ParseResult {
	std::uint64_t stmt_id;
	std::vector<Diagnostic> diags;
	std::vector<Definition> outputs;
	std::vector<std::string> in_syms;
	std::string norm_expr;

	static void to_lua(lua_State* L, ParseResult& self);
};

// TODO: take in print options
struct Job {
	JobType type = JobType::GET_DEFS;
	int bufnr = 0;
	std::uint64_t id = 0;

	// when type is DELETE_SYM, payload = the symbol to delete
	// when type is CLEAR_SYMS, payload = undefined
	// when type is EVAL_LINE, payload = the line to eval
	// otherwise undefined
	std::string payload;
	std::vector<ParseInput> parse_inputs;

	ParseOptions get_parse_options();
	PrintOptions get_print_options();
	EvaluationOptions get_eval_options();
};

struct JobResult {
	// can never be DELETE_SYM or CLEAR_SYMS, they return no results
	JobType type;
	int bufnr;
	std::uint64_t id;

	// when type is EVAL_LINE, output = calculation result
	// otherwise undefined
	std::string output;

	// empty unless type is EVAL_LINE
	std::vector<Diagnostic> diags;

	// empty unless type is PARSE_BATCH
	std::vector<ParseResult> parse_results;

	// empty unless type is GET_DEFS
	std::vector<Definition> defs;
};

class Worker {

public:
	Worker(lua_State* L);
	~Worker();

	void init_async(uv_loop_t* loop);
	void set_callback(int ref);
	void submit_job(Job&& job);

private:
	lua_State* L = nullptr;
	int callback_ref = LUA_NOREF;
	uv_async_t* async_handle = nullptr;

	std::thread worker_thread;
	std::atomic<bool> running{false};

	std::queue<Job> input;
	std::queue<JobResult> output;
	std::mutex queue_mutex;
	std::condition_variable cv;

	// this is the only calculator instance we can use
	Calculator* calc = nullptr;

	void main_loop();
	void process_results();
	void purge_eval_queue();

	static void callback(uv_async_t* handle);

};

}
