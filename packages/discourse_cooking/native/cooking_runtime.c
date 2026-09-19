// Bare QuickJS embedding: deliberately excludes quickjs-libc and module loaders.
#include "quickjs.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

typedef struct {
  JSRuntime *runtime;
  JSContext *context;
  uint64_t deadline;
  size_t max_output;
  int interrupted;
} Cooker;

static uint64_t monotonic_us(void) {
#ifdef _WIN32
  LARGE_INTEGER ticks, frequency;
  QueryPerformanceCounter(&ticks);
  QueryPerformanceFrequency(&frequency);
  return (uint64_t)((double)ticks.QuadPart * 1000000 / frequency.QuadPart);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
#endif
}

static int interrupt(JSRuntime *runtime, void *opaque) {
  (void)runtime;
  Cooker *c = opaque;
  if (monotonic_us() >= c->deadline) c->interrupted = 1;
  return c->interrupted;
}

EXPORT Cooker *dc_create(size_t memory, size_t stack, size_t output) {
  Cooker *c = calloc(1, sizeof(*c));
  if (!c) return NULL;
  c->runtime = JS_NewRuntime();
  if (!c->runtime) { free(c); return NULL; }
  JS_SetMemoryLimit(c->runtime, memory);
  // Never allow Atomics.wait to block outside interpreter deadline polling.
  JS_SetCanBlock(c->runtime, 0);
  JS_SetMaxStackSize(c->runtime, stack);
  c->context = JS_NewContext(c->runtime);
  if (!c->context) { JS_FreeRuntime(c->runtime); free(c); return NULL; }
  c->max_output = output;
  JS_SetInterruptHandler(c->runtime, interrupt, c);
  return c;
}

EXPORT void dc_destroy(Cooker *c) {
  if (!c) return;
  JS_FreeContext(c->context);
  JS_FreeRuntime(c->runtime);
  free(c);
}

// Status: 0 success, 1 JS exception, 2 deadline, 3 output limit,
// 4 allocation failure, 5 non-string result. Output is always malloc-owned.
EXPORT int dc_evaluate(Cooker *c, const char *source, size_t length,
                       uint64_t timeout_us, char **output, size_t *output_len) {
  *output = NULL;
  *output_len = 0;
  c->interrupted = 0;
  c->deadline = monotonic_us() + timeout_us;
  // Dart isolates can migrate between OS threads between FFI invocations.
  JS_UpdateStackTop(c->runtime);
  JSValue value = JS_Eval(c->context, source, length, "cooking", JS_EVAL_TYPE_GLOBAL);
  int status = 0;
  if (JS_IsException(value)) {
    value = JS_GetException(c->context);
    status = c->interrupted ? 2 : 1;
  } else if (!JS_IsString(value)) {
    JS_FreeValue(c->context, value);
    return 5;
  }
  // Exception conversion remains under the same deadline (custom toString).
  size_t size;
  const char *str = JS_ToCStringLen(c->context, &size, value);
  if (!str) {
    JS_FreeValue(c->context, value);
    JSValue exception = JS_GetException(c->context);
    JS_FreeValue(c->context, exception);
    return c->interrupted ? 2 : 4;
  }
  if (c->interrupted) status = 2;
  if (size > c->max_output) status = 3;
  else {
    *output = malloc(size + 1);
    if (!*output) status = 4;
    else { memcpy(*output, str, size); (*output)[size] = 0; *output_len = size; }
  }
  JS_FreeCString(c->context, str);
  JS_FreeValue(c->context, value);
  return status;
}
EXPORT void dc_free(char *p) { free(p); }
EXPORT int64_t dc_memory(Cooker *c) {
  JSMemoryUsage usage;
  JS_ComputeMemoryUsage(c->runtime, &usage);
  return usage.malloc_size;
}
