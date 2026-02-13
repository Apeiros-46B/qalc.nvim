#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <uv.h>

#include "calculator.hpp"
#include "util.hpp"
#include "worker.hpp"

// TODO: verify and test
namespace worker {

static Worker* worker = nullptr;

void init_mt(lua_State* L) {
	luaL_newmetatable(L, MT);

	// create a destructor for the worker thread
	lua_pushcfunction(L, [](lua_State* L) {
		Worker** w_ptr = lua::Userdata<Worker*>::check(L, 1, MT);
		if (*w_ptr) {
			delete *w_ptr;
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
	int bufnr = lua_tointeger(L, 3);
	int extmark_id = lua_tointeger(L, 4);

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

// main thread (libuv event loop)
void Worker::callback(uv_async_t* handle) {
	Worker* self = static_cast<Worker*>(handle->data);
	self->process_results();
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

		// at the end of the scope, don't let the stack grow past what it is now
		lua::StackGuard guard(L, 0);

		if (callback_ref != LUA_NOREF) {
			// push the callback onto the stack
			lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);

			// TODO: unwrap JobResult onto the stack and build the diagnostics table,
			// then call the callback with those values
		}

		// IMPORTANT[2]: unref the instance, so the calculator can be gc'ed if it is no
		// longer present on the lua side (if it's not in the buffer table).
		// see IMPORTANT[1]
		luaL_unref(L, LUA_REGISTRYINDEX, res.inst_ud_ref);
	}
}

}
