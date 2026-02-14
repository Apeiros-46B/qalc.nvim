#pragma once

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

extern "C" {
#include <lauxlib.h>
}
#include <uv.h>

#include "calculator.hpp"

namespace worker {

static const char* MT = "libqalcbridge.Worker";
void init_mt(lua_State* L);
void init(lua_State* L);

// called from lua
int lua_submit_job(lua_State* L);
int lua_set_callback(lua_State* L);

// matches vim.diagnostic.severity (can verify with vim.inspect())
enum class Severity: int {
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	HINT = 4,
};

struct Diagnostic {
	Severity severity;
	std::string msg;
};

// TODO: take in print options
struct Job {
	calc::Instance* inst;
	std::string expr;
	int bufnr;
	int extmark_id;
	int inst_ud_ref; // lua registry ref to userdata (prevent gc)
};

// TODO: add diagnostics
struct JobResult {
	std::string output;
	int bufnr;
	int extmark_id;
	int inst_ud_ref;
	std::vector<Diagnostic> diagnostics;
};

class Worker {

public:
	Worker(lua_State* L);
	~Worker();

	void set_callback(int ref);
	void submit_job(Job&& job);

private:
	lua_State* L = nullptr;
	int callback_ref = LUA_NOREF;
	uv_async_t async_handle;

	std::thread worker_thread;
	std::atomic<bool> running{false};

	std::queue<Job> input;
	std::queue<JobResult> output;
	std::mutex queue_mutex;
	std::condition_variable cv;

	void main_loop();
	void process_results();

	static void callback(uv_async_t* handle);

};

}
