import 'package:discourse_cooking/src/native_runtime.dart';

void main() {
  final clock = Stopwatch()..start();
  var runtime = NativeCookingRuntime();
  final startup = clock.elapsedMicroseconds;
  final result = runtime.evaluate(
    "JSON.stringify([1+2, typeof fetch, typeof XMLHttpRequest, typeof std, typeof os, typeof require, typeof Dart])",
    timeout: const Duration(seconds: 1),
  );
  if (result !=
      '[3,"undefined","undefined","undefined","undefined","undefined","undefined"]') {
    throw StateError(result);
  }
  print(
    'startup_us=$startup heap_bytes=${runtime.memoryUsageBytes} result=$result',
  );
  clock.reset();
  try {
    runtime.evaluate(
      'while(true){}',
      timeout: const Duration(milliseconds: 20),
    );
    throw StateError('Expected timeout');
  } on NativeCookingException catch (error) {
    if (error.kind != NativeCookingError.timeout) rethrow;
    print('interrupt_us=${clock.elapsedMicroseconds}');
  }
  runtime.dispose();
  runtime.dispose();
  runtime = NativeCookingRuntime(maxOutputBytes: 4);
  try {
    runtime.evaluate("'12345'", timeout: const Duration(seconds: 1));
    throw StateError('Expected output limit');
  } on NativeCookingException catch (error) {
    if (error.kind != NativeCookingError.outputLimit) rethrow;
  } finally {
    runtime.dispose();
  }
  try {
    NativeCookingRuntime(memoryLimitBytes: 1);
    throw StateError('Expected initialization allocation failure');
  } on NativeCookingException catch (error) {
    if (error.kind != NativeCookingError.allocation) rethrow;
  }
  print('timeout/output/dispose/initialization-allocation smoke passed');
}
