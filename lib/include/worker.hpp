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
int lua_get_defs(lua_State* L);
int lua_submit_eval_batch(lua_State* L);
int lua_submit_parse_batch(lua_State* L);
int lua_set_callback(lua_State* L);

// matches enum in util.lua
enum class JobType: int {
	PARSE_BATCH = 1,
	EVAL_BATCH = 2,
	GET_DEFS = 3,
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

struct EvalInput {
	std::uint64_t stmt_id;
	std::string expr;
	std::string error;
};

struct EvalResult {
	std::uint64_t stmt_id;
	std::string output;
	std::vector<Diagnostic> diags;

	static void to_lua(lua_State* L, EvalResult& self);
};

struct EvalBatch {
	std::uint64_t doc_id = 0;
	std::uint64_t generation = 0;
	bool reset = false;
	std::vector<std::string> deletions;
	std::vector<EvalInput> inputs;
};

struct EvalBatchResult {
	std::uint64_t doc_id = 0;
	std::uint64_t generation = 0;
	bool complete = false;
	std::vector<EvalResult> results;

	static void to_lua(lua_State* L, EvalBatchResult& self);
};

// TODO: take in print options
struct Job {
	JobType type = JobType::GET_DEFS;
	int bufnr = 0;
	std::uint64_t req_id = 0;

	std::vector<ParseInput> parse_inputs;
	EvalBatch eval_batch;
};

struct JobResult {
	JobType type;
	int bufnr;
	std::uint64_t req_id;

	// empty unless type is PARSE_BATCH
	std::vector<ParseResult> parse_results;
	EvalBatchResult eval_batch;

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

	static void callback(uv_async_t* handle);

};

}
