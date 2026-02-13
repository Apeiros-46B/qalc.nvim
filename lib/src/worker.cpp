#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>

extern "C" {
#include <lua.h>
}
#include <uv.h>

#include "calculator.hpp"
#include "util.hpp"
#include "worker.hpp"

namespace worker {

// TODO: called from luaopen
void Worker::init(lua_State* L) {
	L = L;
	uv_loop_t* loop = uv_default_loop();
	uv_async_init(loop, &async_handle, callback);
	async_handle.data = this;

	running = true;
	worker = std::thread(&Worker::main_loop, this);
}

// TODO: how to call this reliably? VimExit?
void Worker::deinit() {
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		running = false;
	}
	cv.notify_all();
	if (worker.joinable()) worker.join();

	uv_close((uv_handle_t*)&async_handle, nullptr);
}

// TODO: make an init method which sets up the callback
// for returning JobResults to lua

// exposed to Lua
// usage: lib.eval_async(calc_userdata, "1+1")
int Worker::lua_eval_async(lua_State* L) {
	calc::Instance* inst = lua::Userdata<calc::Instance>::check(L, 1, calc::CALC_METATABLE);
	std::string expr = lua::check<std::string>(L, 2);

	// TODO

	return 0;
}

// TODO: test
void Worker::submit_job(Job&& job) {
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		input.push(std::move(job));
	}
	cv.notify_one();
}

// TODO: test
void Worker::main_loop() {
	while (true) {
		Job job;
		{
			std::unique_lock<std::mutex> lock(queue_mutex);
			cv.wait(lock, [this] {
				return !input.empty() || !running;
			});
			if (!running && input.empty()) break;

			job = std::move(input.front());
			input.pop();
		}

		JobResult result;
		result.bufnr = job.bufnr;
		result.extmark_id = job.extmark_id;
		result.inst_ud_ref = job.inst_ud_ref;

		try {
			// this is safe because we are the only thread processing jobs
			job.inst->make_current();

			// TODO: actually use the calculator
			// job.inst->eval(job.expression)...

			result.success = true;
			result.output = "Calculated: " + job.expr;
		} catch (const std::exception& e) {
			result.success = false;
			result.output = e.what();
		}

		{
			std::lock_guard<std::mutex> lock(queue_mutex);
			output.push(std::move(result));
		}

		// notify main thread
		uv_async_send(&async_handle);
	}
}

void Worker::callback(uv_async_t* handle) {
	Worker* self = static_cast<Worker*>(handle->data);
	self->process_results();
}

void Worker::process_results() {
	std::queue<JobResult> ready_results;
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		ready_results.swap(output);
	}

	while (!ready_results.empty()) {
		JobResult res = ready_results.front();
		ready_results.pop();

		// TODO
	}
}

}
