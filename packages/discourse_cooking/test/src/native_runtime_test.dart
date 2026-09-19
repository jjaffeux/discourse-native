import 'package:discourse_cooking/src/native_runtime.dart';
import 'package:test/test.dart';

const timeout = Duration(seconds: 1);
Matcher nativeError(NativeCookingError kind) =>
    isA<NativeCookingException>().having((e) => e.kind, 'kind', kind);

void main() {
  test('blocking Atomics.wait cannot bypass execution deadline', () {
    final vm = NativeCookingRuntime();
    addTearDown(vm.dispose);
    final elapsed = Stopwatch()..start();
    expect(
      () => vm.evaluate(
        'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0)',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<NativeCookingException>()),
    );
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
  });
  test('bare persistent VM has no host or network capabilities', () {
    final vm = NativeCookingRuntime();
    addTearDown(vm.dispose);
    expect(
      vm.evaluate("globalThis.counter = 1; 'ready'", timeout: timeout),
      'ready',
    );
    expect(vm.evaluate("String(++counter)", timeout: timeout), '2');
    expect(
      vm.evaluate(
        "JSON.stringify(['fetch','XMLHttpRequest','WebSocket','require','process','Deno','Bun','std','os','sendMessage','setTimeout'].filter(k => typeof globalThis[k] !== 'undefined'))",
        timeout: timeout,
      ),
      '[]',
    );
    expect(vm.memoryUsageBytes, greaterThan(0));
  });

  test('infinite loop is interrupted and failed VM cannot be reused', () {
    final vm = NativeCookingRuntime();
    addTearDown(vm.dispose);
    final elapsed = Stopwatch()..start();
    expect(
      () => vm.evaluate(
        'while (true) {}',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(nativeError(NativeCookingError.timeout)),
    );
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
    expect(() => vm.evaluate("'ok'", timeout: timeout), throwsStateError);
  });

  test('regexp backtracking and exception conversion obey the deadline', () {
    for (final source in [
      "/(a+)+\$/.test('a'.repeat(50) + '!'); 'done'",
      'throw { toString() { while (true) {} } };',
    ]) {
      final vm = NativeCookingRuntime();
      try {
        expect(
          () => vm.evaluate(source, timeout: const Duration(milliseconds: 20)),
          throwsA(nativeError(NativeCookingError.timeout)),
        );
      } finally {
        vm.dispose();
      }
    }
  });

  test('output limit fails before copying unbounded output', () {
    final vm = NativeCookingRuntime(maxOutputBytes: 32);
    addTearDown(vm.dispose);
    expect(
      () => vm.evaluate("'a'.repeat(10000)", timeout: timeout),
      throwsA(nativeError(NativeCookingError.outputLimit)),
    );
  });

  test('allocation is bounded under deliberate heap growth', () {
    final vm = NativeCookingRuntime(memoryLimitBytes: 2 * 1024 * 1024);
    addTearDown(vm.dispose);
    expect(
      () => vm.evaluate(
        "let a=[]; while(true) a.push(new Array(10000).fill('heap'));",
        timeout: timeout,
      ),
      throwsA(isA<NativeCookingException>()),
    );
    expect(vm.memoryUsageBytes, lessThan(3 * 1024 * 1024));
  });

  test('embedded NUL does not silently truncate source', () {
    final vm = NativeCookingRuntime();
    addTearDown(vm.dispose);
    expect(
      () => vm.evaluate("'before';\u0000'after'", timeout: timeout),
      throwsA(isA<NativeCookingException>()),
    );
  });

  test('dispose is idempotent and rejects later evaluation', () {
    final vm = NativeCookingRuntime();
    vm.dispose();
    vm.dispose();
    expect(() => vm.evaluate("'ok'", timeout: timeout), throwsStateError);
  });
}
