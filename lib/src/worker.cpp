#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <libqalculate/Calculator.h>
#include <libqalculate/Function.h>
#include <libqalculate/MathStructure.h>
#include <libqalculate/Variable.h>
#include <uv.h>

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

// get a reference to nvim's loop. we need to do this since uv_default_loop() does NOT
// return the same loop as the one that nvim uses. we pass a uv handle from lua, and then
// extract the inner loop reference
// MUST be done from lua side before submitting any jobs:
//   local dummy = vim.uv.new_timer()
//   lib.init_loop(dummy)
//   dummy:close()
int lua_init_loop(lua_State* L) {
	uv_handle_t** ptr = lua::Userdata<uv_handle_t*>::check(L, 1, "uv_timer");

	if (worker != nullptr && ptr != nullptr && *ptr != nullptr) {
		uv_loop_t* nvim_loop = (*ptr)->loop;
		worker->init_async(nvim_loop);
	}
	return 0;
}

// submits a job to the worker thread. it should have been intialized already
// lib.submit_job(type, bufnr, extmark_id, payload)
int lua_submit_job(lua_State* L) {
	JobType type = static_cast<JobType>(lua::pop<int>(L, 1));
	int bufnr = lua::pop<int>(L, 2);
	int extmark_id = lua::pop<int>(L, 3);
	std::string payload = lua::pop_or<std::string>(L, 4, "");

	if (worker != nullptr) {
		worker->submit_job({type, bufnr, extmark_id, payload});
	}
	return 0;
}

// set the callback used when jobs complete
// lib.set_callback(function(...) ... end)
// callback should be a function of 7 arguments:
// - type (int)
// - bufnr (int)
// - extmark_id (int)
// - output (str)
// - diagnostics (tbl)
// - out_syms (tbl)
// - in_syms (tbl)
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
	calc = new Calculator();
	CALCULATOR = calc;
	calc->loadExchangeRates();
	calc->loadGlobalDefinitions();

	// async remains uninitialized!
	// these must be called before submitting any jobs:
	// - init_async
	// - set_callback

	running = true;
	worker_thread = std::thread(&Worker::main_loop, this);
}

// TODO: extract options
ParseOptions Job::get_parse_options() {
	ParseOptions opts;
	return opts;
}

PrintOptions Job::get_print_options() {
	PrintOptions opts;
	return opts;
}

EvaluationOptions Job::get_eval_options() {
	EvaluationOptions opts;
	return opts;
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
	if (async_handle != nullptr) {
		// do not free until the close callback is called
		uv_close(reinterpret_cast<uv_handle_t*>(async_handle), [](uv_handle_t* h) {
			delete reinterpret_cast<uv_async_t*>(h);
		});
	}

	CALCULATOR = calc;
	delete calc;
	CALCULATOR = nullptr;
}

// main thread
void Worker::init_async(uv_loop_t* loop) {
	async_handle = new uv_async_t();
	uv_async_init(loop, async_handle, Worker::callback);
	async_handle->data = this;
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
static void get_diagnostics(Calculator* calc, JobResult& result) {
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

		result.diagnostics.push_back(diag);
		calc->nextMessage();
	}
}

// worker thread
// remove a specific user-defined symbol
static void delete_sym(Calculator* calc, const std::string& sym) {
	Variable* v = calc->getActiveVariable(sym);
	if (v && v->isLocal()) {
		v->destroy();
		return;
	}
	MathFunction* f = calc->getActiveFunction(sym);
	if (f && f->isLocal()) {
		f->destroy();
	}
}

// worker thread
// clear all user-defined symbols
static void clear_syms(Calculator* calc) {
	for (int i = calc->variables.size() - 1; i >= 0; --i) {
		if (calc->variables[i]->isLocal()) {
			calc->variables[i]->destroy();
		}
	}
	for (int i = calc->functions.size() - 1; i >= 0; --i) {
		if (calc->functions[i]->isLocal()) {
			calc->functions[i]->destroy();
		}
	}
}

// worker thread
// parse an expression and extract assigned and read symbols, along with any messages
static void parse_line(Calculator* calc, Job& job, JobResult& result) {
	MathStructure ast;
	calc->parse(&ast, job.payload, job.get_parse_options());
	get_diagnostics(calc, result);

	// TODO: walk ast and populate result.assigned_symbols & result.read_symbols
}

// worker thread
// evaluate an expression
static void eval_line(Calculator* calc, Job& job, JobResult& result) {
	result.output = calc->calculateAndPrint(
		job.payload,
		2000,
		job.get_eval_options(),
		job.get_print_options()
	);
	get_diagnostics(calc, result);
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

		CALCULATOR = calc;

		JobResult result;
		result.type = job.type;
		result.bufnr = job.bufnr;
		result.extmark_id = job.extmark_id;

		try {
			// delete and clear don't need to notify lua, they merely mutate the calculator state
			// for subsequent operations. because these operations were queued in order we just
			// execute them in order
			if (job.type == JobType::DELETE_SYM) {
				delete_sym(calc, job.payload);
				continue;
			} else if (job.type == JobType::CLEAR_SYMS) {
				clear_syms(calc);
				continue;
			} else if (job.type == JobType::PARSE_LINE) {
				parse_line(calc, job, result);
			} else if (job.type == JobType::EVAL_LINE) {
				eval_line(calc, job, result);
			}
		} catch (const std::exception& e) {
			result.output = "";
			result.diagnostics.clear();

			Diagnostic diag;
			diag.severity = Severity::ERROR;
			diag.msg = e.what();

			result.diagnostics.push_back(diag);
		}

		// push results and notify main thread
		{
			std::lock_guard<std::mutex> lock(queue_mutex);
			output.push(std::move(result));
		}
		uv_async_send(async_handle);
	}
}

// main thread
void Worker::callback(uv_async_t* handle) {
	Worker* self = static_cast<Worker*>(handle->data);
	self->process_results();
}

// main thread
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

			// push 7 args
			lua::push(L, static_cast<int>(res.type));
			lua::push(L, res.bufnr);
			lua::push(L, res.extmark_id);
			lua::push(L, res.output);
			lua::make_array<Diagnostic>(L, res.diagnostics, [](
				lua_State* L,
				const Diagnostic& diag
			) {
				lua_createtable(L, 0, 2);
				lua::push_and_set(L, diag.msg, "message");
				lua::push_and_set(L, static_cast<int>(diag.severity), "severity");
			});
			lua::make_array<std::string>(L, res.out_syms);
			lua::make_array<std::string>(L, res.in_syms);

			// call
			if (lua_pcall(L, 7, 0, 0) != LUA_OK) {
				fprintf(stderr, "qalc error: %s\n", lua_tostring(L, -1));
				lua_pop(L, 1);
			}
		}
	}
}

}
