#include <chrono>
#include <cstddef>
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
#include <libqalculate/includes.h>
#include <uv.h>

#include "math.hpp"
#include "util.hpp"
#include "worker.hpp"

namespace worker {

static Worker* worker = nullptr;

constexpr int EVAL_TIMEOUT_MS = 2000;
constexpr const char* TIMEOUT_MSG = "Calculation exceeded the 2-second time limit.";
constexpr const char* SKIPPED_TIMEOUT_MSG = "Calculation skipped because an earlier calculation timed out.";
constexpr const char* SKIPPED_FAILURE_MSG = "Calculation skipped because the evaluation transaction failed.";

// {{{ lua serialization
void Diagnostic::to_lua(lua_State* L, const Diagnostic& self) {
	lua_createtable(L, 0, 2);
	// :h vim.Diagnostic.Set
	lua::push_and_set(L, static_cast<int>(self.severity), "severity");
	lua::push_and_set(L, self.msg, "message");
}

void ParseResult::to_lua(lua_State* L, ParseResult& self) {
	lua_createtable(L, 0, 5);
	lua::push_and_set(L, static_cast<double>(self.stmt_id), "stmt_id");

	lua::make_array<Diagnostic>(L, self.diags, Diagnostic::to_lua);
	lua_setfield(L, -2, "diags");
	lua::make_array<Definition>(L, self.outputs, Definition::to_lua);
	lua_setfield(L, -2, "outputs");
	lua::make_array<std::string>(L, self.in_syms);
	lua_setfield(L, -2, "in_syms");
	lua::push_and_set(L, self.norm_expr, "norm_expr");
}

void EvalResult::to_lua(lua_State* L, EvalResult& self) {
	lua_createtable(L, 0, 3);
	lua::push_and_set(L, static_cast<double>(self.stmt_id), "stmt_id");
	lua::push_and_set(L, self.output, "output");
	lua::make_array<Diagnostic>(L, self.diags, Diagnostic::to_lua);
	lua_setfield(L, -2, "diags");
}

void EvalBatchResult::to_lua(lua_State* L, EvalBatchResult& self) {
	lua_createtable(L, 0, 4);
	lua::push_and_set(L, static_cast<double>(self.doc_id), "doc_id");
	lua::push_and_set(L, static_cast<double>(self.generation), "generation");
	lua::push_and_set(L, self.complete, "complete");
	lua::make_array<EvalResult>(L, self.results, EvalResult::to_lua);
	lua_setfield(L, -2, "results");
}
// }}}

// {{{ other lua plumbing
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
// }}}

// {{{ lua-exposed functions
int lua_get_defs(lua_State* L) {
	if (worker != nullptr) {
		Job job;
		job.type = JobType::GET_DEFS;
		job.opts.read_lua(L, 1);
		worker->submit_job(std::move(job));
	}
	return 0;
}

// lib.submit_eval_batch(bufnr, doc_id, generation, reset, deletions, inputs, opts)
int lua_submit_eval_batch(lua_State* L) {
	// TODO: cleanup, this is very messy
	Job job;
	job.type = JobType::EVAL_BATCH;
	job.bufnr = lua::pop<int>(L, 1);
	job.eval_batch.doc_id = static_cast<std::uint64_t>(luaL_checknumber(L, 2));
	job.eval_batch.generation = static_cast<std::uint64_t>(luaL_checknumber(L, 3));
	job.eval_batch.reset = lua::pop<bool>(L, 4);

	luaL_checktype(L, 5, LUA_TTABLE);
	std::size_t deletion_count = lua_objlen(L, 5);
	job.eval_batch.deletions.reserve(deletion_count);
	for (std::size_t i = 1; i <= deletion_count; ++i) {
		lua_rawgeti(L, 5, static_cast<int>(i));
		job.eval_batch.deletions.push_back(lua::pop<std::string>(L, -1));
		lua_pop(L, 1);
	}

	luaL_checktype(L, 6, LUA_TTABLE);
	std::size_t input_count = lua_objlen(L, 6);
	job.eval_batch.inputs.reserve(input_count);
	for (std::size_t i = 1; i <= input_count; ++i) {
		lua_rawgeti(L, 6, static_cast<int>(i));
		luaL_checktype(L, -1, LUA_TTABLE);

		lua_getfield(L, -1, "stmt_id");
		std::uint64_t stmt_id = static_cast<std::uint64_t>(
			luaL_checknumber(L, -1)
		);
		lua_pop(L, 1);

		lua_getfield(L, -1, "expr");
		std::string expr = lua::pop<std::string>(L, -1);
		lua_pop(L, 1);

		lua_getfield(L, -1, "error");
		std::string error = lua::pop_or<std::string>(L, -1, "");
		lua_pop(L, 1);
		lua_pop(L, 1);

		job.eval_batch.inputs.push_back({
			stmt_id,
			std::move(expr),
			std::move(error),
		});
	}
	job.opts.read_lua(L, 7);

	if (worker != nullptr) {
		worker->submit_job(std::move(job));
	}
	return 0;
}

// lib.submit_parse_batch(bufnr, req_id, inputs, opts)
int lua_submit_parse_batch(lua_State* L) {
	int bufnr = lua::pop<int>(L, 1);
	std::uint64_t req_id = static_cast<std::uint64_t>(luaL_checknumber(L, 2));
	luaL_checktype(L, 3, LUA_TTABLE);

	Job job;
	job.type = JobType::PARSE_BATCH;
	job.bufnr = bufnr;
	job.req_id = req_id;

	std::size_t count = lua_objlen(L, 3);
	job.parse_inputs.reserve(count);
	for (std::size_t i = 1; i <= count; ++i) {
		lua_rawgeti(L, 3, static_cast<int>(i));
		luaL_checktype(L, -1, LUA_TTABLE);

		lua_getfield(L, -1, "stmt_id");
		std::uint64_t stmt_id = static_cast<std::uint64_t>(
			luaL_checknumber(L, -1)
		);
		lua_pop(L, 1);

		lua_getfield(L, -1, "text");
		std::string text = lua::pop<std::string>(L, -1);
		lua_pop(L, 1);
		lua_pop(L, 1);

		job.parse_inputs.push_back({stmt_id, std::move(text)});
	}
	job.opts.read_lua(L, 4);

	if (worker != nullptr) {
		worker->submit_job(std::move(job));
	}
	return 0;
}

// set the callback used when jobs complete
// lib.set_callback(function(...) ... end)
// callback should be a function of 6 arguments:
// - type (int)
// - bufnr (int)
// - req_id (number)
// - defs (tbl)
// - parse_results (tbl)
// - eval_batch (tbl or nil)
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
// }}}

Worker::Worker(lua_State* L): L{L} {
	calc = new Calculator();
	CALCULATOR = calc;
	calc->setPrecision(10); // qalc CLI's default startup precision
	calc->loadExchangeRates();
	calc->loadGlobalDefinitions();

	// SECURITY: remove "command" function
	// risk of RCE since it allows qalc files to execute arbitrary shell commands
	for (auto* func : calc->functions) {
		if (func && func->name() == "command") {
			func->destroy();
			break;
		}
	}

	// async remains uninitialized!
	// these MUST be called before submitting any jobs:
	// - init_async
	// - set_callback

	running.store(true);
	worker_thread = std::thread(&Worker::main_loop, this);
}

Worker::~Worker() {
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		running.store(false);
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
	uv_async_init(loop, async_handle, &Worker::callback);
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

// {{{ request handlers
// worker thread
static void get_diags(
	Calculator* calc,
	std::vector<Diagnostic>& diags
) {
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

		diags.push_back(diag);
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
	for (std::size_t i = calc->variables.size(); i > 0; --i) {
		if (calc->variables[i - 1]->isLocal()) {
			calc->variables[i - 1]->destroy();
		}
	}
	for (std::size_t i = calc->functions.size(); i > 0; --i) {
		if (calc->functions[i - 1]->isLocal()) {
			calc->functions[i - 1]->destroy();
		}
	}
}

// worker thread
// parse an expression and extract assigned and read symbols, along with any messages
static void parse_line(
	Calculator* calc,
	const ParseInput& input,
	ParseResult& result,
	const ParseOptions& opts
) {
	std::string expr = input.text;
	// thankfully this exists
	transform_expression_for_equals_save(expr, opts);

	MathStructure ast;
	calc->parse(&ast, expr, opts);
	if (
		ast.type() == STRUCT_COMPARISON &&
		ast.comparisonType() == ComparisonType::COMPARISON_EQUALS
	) {
		// prevent calculateAndPrint() from reinterpreting the comparison as a save
		expr = "(" + expr + ")";
	}
	if (expr != input.text) {
		result.norm_expr = expr;
	}
	get_diags(calc, result.diags);
	extract_syms(calc, ast, result.in_syms, result.outputs);
	extract_fn_calls(calc, input.text, result.in_syms);
}

// worker thread
// parse a job's batch of exprs. see parse_line
static void parse_batch(Calculator* calc, Job& job, JobResult& result) {
	result.parse_results.reserve(job.parse_inputs.size());

	for (const ParseInput& input : job.parse_inputs) {
		ParseResult parsed;
		parsed.stmt_id = input.stmt_id;

		try {
			parse_line(calc, input, parsed, job.opts.parse);
		} catch (const std::exception& e) {
			get_diags(calc, parsed.diags);
			parsed.diags.push_back({Severity::ERROR, e.what()});
		}

		result.parse_results.push_back(std::move(parsed));
	}
}

// worker thread
// evaluate an expression
static bool eval_line(
	Calculator* calc,
	const EvalInput& input,
	EvalResult& result,
	const Options& opts
) {
	auto started_at = std::chrono::steady_clock::now();
	result.output = calc->calculateAndPrint(
		input.expr,
		EVAL_TIMEOUT_MS,
		opts.eval,
		opts.print
	);
	auto elapsed = std::chrono::steady_clock::now() - started_at;

	get_diags(calc, result.diags);

	// for debugging symbol extraction
	// MathStructure ast;
	// calc->parse(&ast, input.expr, opts.parse);
	// get_diags(calc, result.diags);
	// extract_symbols(calc, ast, result.in_syms, result.out_syms);
	// result.output = dump_ast(ast);

	return result.output == "aborted"
		|| elapsed >= std::chrono::milliseconds(EVAL_TIMEOUT_MS);
}

static void append_skipped_results(
	const std::vector<EvalInput>& inputs,
	std::size_t first,
	EvalBatchResult& result,
	const char* message
) {
	for (std::size_t i = first; i < inputs.size(); ++i) {
		EvalResult skipped;
		skipped.stmt_id = inputs[i].stmt_id;
		skipped.diags.push_back({Severity::ERROR, message});

		result.results.push_back(std::move(skipped));
	}
}

// worker thread
// evaluate a job's batch of exprs. see eval_line
static void eval_batch(Calculator* calc, Job& job, JobResult& job_result) {
	// TODO: very defensive err handling code can probably be cleaned up somehow
	const EvalBatch& batch = job.eval_batch;

	EvalBatchResult& result = job_result.eval_batch;
	result.doc_id = batch.doc_id;
	result.generation = batch.generation;
	result.complete = true;
	result.results.reserve(batch.inputs.size());

	// pre cleanup
	try {
		if (batch.reset) {
			clear_syms(calc);
		} else {
			for (const std::string& symbol : batch.deletions) {
				delete_sym(calc, symbol);
			}
		}
	} catch (const std::exception& e) {
		result.complete = false;

		if (!batch.inputs.empty()) {
			EvalResult failed;
			failed.stmt_id = batch.inputs[0].stmt_id;

			get_diags(calc, failed.diags);
			failed.diags.push_back({Severity::ERROR, e.what()});

			result.results.push_back(std::move(failed));
			append_skipped_results(batch.inputs, 1, result, SKIPPED_FAILURE_MSG);
		}
		return;
	}

	// eval each expr
	for (std::size_t i = 0; i < batch.inputs.size(); ++i) {
		const EvalInput& input = batch.inputs[i];

		EvalResult evaluated;
		evaluated.stmt_id = input.stmt_id;

		if (!input.error.empty()) {
			evaluated.diags.push_back({Severity::ERROR, input.error});
			result.results.push_back(std::move(evaluated));
			continue;
		}

		try {
			if (eval_line(calc, input, evaluated, job.opts)) {
				evaluated.diags.push_back({Severity::ERROR, TIMEOUT_MSG});
				evaluated.output.clear();

				result.results.push_back(std::move(evaluated));
				result.complete = false;
				append_skipped_results(
					batch.inputs,
					i + 1,
					result,
					SKIPPED_TIMEOUT_MSG
				);

				return;
			}
		} catch (const std::exception& e) {
			get_diags(calc, evaluated.diags);
			evaluated.diags.push_back({Severity::ERROR, e.what()});
			evaluated.output.clear();

			result.results.push_back(std::move(evaluated));
			result.complete = false;
			append_skipped_results(
				batch.inputs,
				i + 1,
				result,
				SKIPPED_FAILURE_MSG
			);
			return;
		}

		result.results.push_back(std::move(evaluated));
	}
}

// worker thread
// enumerate all global definitions
static void get_defs(
	Calculator* calc,
	JobResult& result,
	const PrintOptions& opts
) {
	for (auto* func : calc->functions) {
		push_def(calc, func, opts, result.defs);
	}
	for (auto* var : calc->variables) {
		push_def(calc, var, opts, result.defs);
	}
	for (auto* unit : calc->units) {
		push_def(calc, unit, opts, result.defs);
	}
	for (auto* pref : calc->prefixes) {
		push_prefix_def(calc, pref, opts, result.defs);
	}
}
// }}}

// {{{ process requests
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
		result.req_id = job.req_id;

		try {
			switch (job.type) {
				case JobType::PARSE_BATCH: {
					parse_batch(calc, job, result);
					break;
				}
				case JobType::EVAL_BATCH: {
					eval_batch(calc, job, result);
					break;
				}
				case JobType::GET_DEFS: {
					get_defs(calc, result, job.opts.print);
					break;
				}
			}
		} catch (const std::exception& e) {
			fprintf(stderr, "qalc worker error: %s\n", e.what());

			if (job.type == JobType::PARSE_BATCH) {
				result.parse_results.clear();

				for (const ParseInput& input : job.parse_inputs) {
					ParseResult failed;
					failed.stmt_id = input.stmt_id;
					failed.diags.push_back({Severity::ERROR, e.what()});
					result.parse_results.push_back(std::move(failed));
				}
			} else if (job.type == JobType::EVAL_BATCH) {
				result.eval_batch.doc_id = job.eval_batch.doc_id;
				result.eval_batch.generation = job.eval_batch.generation;
				result.eval_batch.complete = false;
				result.eval_batch.results.clear();

				if (!job.eval_batch.inputs.empty()) {
					EvalResult failed;
					failed.stmt_id = job.eval_batch.inputs[0].stmt_id;
					failed.diags.push_back({Severity::ERROR, e.what()});

					result.eval_batch.results.push_back(std::move(failed));
					append_skipped_results(
						job.eval_batch.inputs,
						1,
						result.eval_batch,
						SKIPPED_FAILURE_MSG
					);
				}
			}
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
void Worker::process_results() {
	std::queue<JobResult> ready_results;
	{
		std::lock_guard<std::mutex> lock(queue_mutex);
		ready_results.swap(output);
	}

	while (!ready_results.empty()) {
		JobResult res = std::move(ready_results.front());
		ready_results.pop();

		// prevent stack leak in loop
		lua::StackGuard guard(L, 0);

		if (callback_ref != LUA_NOREF) {
			// pushes 1 item (the callback)
			lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);

			// pushes 6 args
			lua::push(L,
				static_cast<int>(res.type),
				res.bufnr,
				static_cast<double>(res.req_id)
			);
			lua::make_array<Definition>(L, res.defs, Definition::to_lua);
			lua::make_array<ParseResult>(L, res.parse_results, ParseResult::to_lua);
			if (res.type == JobType::EVAL_BATCH) {
				EvalBatchResult::to_lua(L, res.eval_batch);
			} else {
				lua_pushnil(L);
			}

			// pops callback + 6 args (7 items)
			if (lua_pcall(L, 6, 0, 0) != LUA_OK) {
				fprintf(stderr, "qalc error: %s\n", lua_tostring(L, -1));
				lua_pop(L, 1);
			}
		}
	}
}

// main thread
void Worker::callback(uv_async_t* handle) {
	Worker* self = static_cast<Worker*>(handle->data);
	self->process_results();
}
// }}}

}
