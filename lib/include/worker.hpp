#pragma once

#include <uv.h>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <atomic>

#include "calculator.hpp"

namespace worker {

enum class Severity: int {
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	HINT = 4,
};

struct Diagnostic {
	Severity severity;
	int col; // 0-indexed (-1 if unknown)
	int end_col;
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
	bool success;
};

class Worker {
public:
	static Worker& get() {
		static Worker instance;
		return instance;
	}

	void init(lua_State* L);
	void deinit();

	// exposed to lua
	static int lua_eval_async(lua_State* L);

private:
	lua_State* L = nullptr;
	uv_async_t async_handle;
	std::thread worker;
	std::atomic<bool> running{false};

	std::queue<Job> input;
	std::queue<JobResult> output;
	std::mutex queue_mutex;
	std::condition_variable cv;

	void submit_job(Job&& job);
	void main_loop();
	void process_results();

	static void callback(uv_async_t* handle);
};

} // namespace calc
