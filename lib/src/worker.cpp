#include <atomic>
#include <condition_variable>
#include <libqalculate/includes.h>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <libqalculate/Calculator.h>
#include <uv.h>

#include "calculator.hpp"
#include "util.hpp"
#include "worker.hpp"

namespace worker {

static Worker* worker = nullptr;

void init_mt(lua_State* L) {
	luaL_newmetatable(L, MT);

	// create a destructor for the worker thread
	lua_pushcfunction(L, [](lua_State* L) {
		Worker** w_ptr = lua::Userdata<Worker*>::check(L, 1, MT);
		if (*w_ptr) {
			delete *w_ptr;
			if (worker == *w_ptr) {
				worker = nullptr;
			}
			*w_ptr = nullptr;
		}
		// we don't try to delete the w_ptr itself. it is memory allocated by lua, not us
		return 0;
	});
	lua_setfield(L, -2, "__gc");
	lua_pop(L, 1);
}

// initialises the given callback in the registry and spawns the worker
void init(lua_State* L) {
	Worker** ptr = lua::Userdata<Worker*>::push(L, MT);
	*ptr = new Worker(L);
	lua_setfield(L, LUA_REGISTRYINDEX, MT); // use mt name as identifier
	// this registry value keeps the worker alive until nvim exits
	// (at which point it calls __gc, which destroys the underlying obj)

	worker = *ptr;
}

// submits a job to the worker thread. it should have been intiialized
// lib.submit_job(inst, bufnr, extmark_id, expr)
int lua_submit_job(lua_State* L) {
	calc::Instance* inst = lua::Userdata<calc::Instance>::check(
		L, 1,
		calc::MT
	);
	std::string expr = lua::check<std::string>(L, 2);
	int bufnr = lua::check<int>(L, 3);
	int extmark_id = lua::check<int>(L, 4);

	// IMPORTANT[1]: reference the instance userdata in the registry so if the user
	// closes the buffer right after submitting a job, there is no risk of
	// trying to read a calculator that just got freed by lua gc. this MUST be
	// unref'd when the worker thread is done with this specific job.
	// see IMPORTANT[2]
	lua_pushvalue(L, 1);
	int inst_ud_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	if (worker != nullptr) {
		worker->submit_job({inst, expr, bufnr, extmark_id, inst_ud_ref});
	}
	return 0;
}

// lib.set_callback(function(bufnr, extmark_id, output, diagnostics) ... end)
int lua_set_callback(lua_State* L) {
	if (!lua_isfunction(L, 1)) {
		luaL_error(L, "expected function as arg 1");
	}

	int callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	if (worker != nullptr) {
		worker->set_callback(callback_ref);
	}
	return 0;
}

Worker::Worker(lua_State* L): L{L} {
	uv_loop_t* loop = uv_default_loop();
	uv_async_init(loop, &async_handle, callback);
	async_handle.data = this;
	running = true;
	worker_thread = std::thread(&Worker::main_loop, this);
}

Worker::~Worker() {
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		running = false;
	}
	cv.notify_all();
	if (worker_thread.joinable()) {
		worker_thread.join();
	}
	uv_close((uv_handle_t*)&async_handle, nullptr);
}

// main thread
void Worker::set_callback(int ref) {
	// cleanup old callback, if any
	if (callback_ref != LUA_NOREF) {
		luaL_unref(L, LUA_REGISTRYINDEX, callback_ref);
	}
	callback_ref = ref;
}

// main thread
void Worker::submit_job(Job&& job) {
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		input.push(std::move(job));
	}
	cv.notify_one();
}

// worker thread
static std::string eval(Job& job, std::vector<Diagnostic>& diagnostics) {
	// this is safe because we are the only thread processing jobs
	job.inst->make_current();
	auto calc = job.inst->inner;

	// TODO: need to pass eval options and print options to here
	std::string result = calc->calculateAndPrint(job.expr, 2000);

	CalculatorMessage* msg;
	while ((msg = calc->message()) != nullptr) {
		Diagnostic diag;

		diag.msg = msg->c_message();
		switch (msg->type()) {
			case MESSAGE_INFORMATION:
				diag.severity = Severity::INFO;
				break;
			case MESSAGE_WARNING:
				diag.severity = Severity::WARN;
				break;
			case MESSAGE_ERROR:
				diag.severity = Severity::ERROR;
				break;
		}

		diagnostics.push_back(diag);
		calc->nextMessage();
	}

	return result;
}

// worker thread
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
			result.output = eval(job, result.diagnostics);
		} catch (const std::exception& e) {
			result.output = "";
			result.diagnostics.clear();

			Diagnostic diag;
			diag.severity = Severity::ERROR;
			diag.msg = e.what();

			result.diagnostics.push_back(diag);
		}

		{
			std::lock_guard<std::mutex> lock(queue_mutex);
			output.push(std::move(result));
		}

		// notify main thread
		uv_async_send(&async_handle);
	}
}

// main thread (libuv event loop)
void Worker::callback(uv_async_t* handle) {
	Worker* self = static_cast<Worker*>(handle->data);
	self->process_results();
}

// push 1 (table)
static void build_diagnostics_table(
	lua_State* L,
	std::vector<Diagnostic>& diagnostics
) {
	lua::StackGuard guard(L, 1);

	lua_createtable(L, static_cast<int>(diagnostics.size()), 0);

	int i = 1;
	for (Diagnostic& diag : diagnostics) {
		lua_createtable(L, 0, 2);
		lua::push_and_set(L, diag.msg, "message");
		lua::push_and_set(L, static_cast<int>(diag.severity), "severity");

		lua_rawseti(L, -2, i++);
	}
}

// main thread (libuv event loop)
void Worker::process_results() {
	std::queue<JobResult> ready_results;
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		ready_results.swap(output);
	}

	while (!ready_results.empty()) {
		JobResult res = ready_results.front();
		ready_results.pop();

		// at the end of the scope, shrink the stack back to where it is now
		lua::StackGuard guard(L, 0);

		if (callback_ref != LUA_NOREF) {
			// push the callback onto the stack
			lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);

			lua::push(L, res.bufnr);
			lua::push(L, res.extmark_id);
			lua::push(L, res.output);
			build_diagnostics_table(L, res.diagnostics);

			if (lua_pcall(L, 4, 0, 0) != LUA_OK) {
				fprintf(stderr, "qalc error: %s\n", lua_tostring(L, -1));
				lua_pop(L, 1);
			}
		}

		// IMPORTANT[2]: unref the instance, so the calculator can be gc'ed if it is no
		// longer present on the lua side (if it's not in the buffer table).
		// see IMPORTANT[1]
		luaL_unref(L, LUA_REGISTRYINDEX, res.inst_ud_ref);
	}
}

}
