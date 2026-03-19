#pragma once

#include <atomic>
#include <condition_variable>
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
int lua_submit_job(lua_State* L);
int lua_set_callback(lua_State* L);

// matches enum in util.lua
enum class JobType: int {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_LINE = 3,
	EVAL_LINE = 4,
	GET_DEFS = 5,
	ABORT = 6,
};

struct Diagnostic {
	Severity severity;
	std::string msg;

	static void to_lua(lua_State* L, const Diagnostic& self);
};

// TODO: take in print options
struct Job {
	JobType type;
	int bufnr;
	int extmark_id;

	// when type is DELETE_SYM, payload = the symbol to delete
	// when type is CLEAR_SYMS, payload = undefined
	// when type is PARSE_LINE, payload = the line to parse
	// when type is EVAL_LINE, payload = the line to eval
	// otherwise undefined
	std::string payload;

	ParseOptions get_parse_options();
	PrintOptions get_print_options();
	EvaluationOptions get_eval_options();
};

struct JobResult {
	// can never be DELETE_SYM, CLEAR_SYMS, or ABORT, they return no results
	JobType type;
	int bufnr;
	int extmark_id;

	// when type is EVAL_LINE, output = calculation result
	// otherwise undefined
	std::string output;

	// empty unless type is PARSE_LINE, EVAL_LINE
	std::vector<Diagnostic> diagnostics;

	// empty unless type is PARSE_LINE
	std::vector<Definition> out_syms;
	std::vector<std::string> in_syms;

	// empty unless type is GET_DEFS
	std::vector<Definition> definitions;
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
	uv_async_t* async_handle;

	std::thread worker_thread;
	std::atomic<bool> running{false};
	std::atomic<bool> aborted{false};

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
