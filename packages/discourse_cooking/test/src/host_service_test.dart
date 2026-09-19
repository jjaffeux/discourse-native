import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

CookingRequest request({
  String raw = '**hello**',
  String site = 'a',
  String account = '1',
  Map<String, Object?> settings = const {},
}) => CookingRequest(
  raw: raw,
  snapshot: CookingSnapshot(
    siteId: site,
    accountId: account,
    siteSettings: settings,
  ),
);

final class FakeRuntime implements CookingRuntimePort {
  bool healthy = true;
  bool ready = true;
  bool throwOnStart = false;
  bool throwOnCook = false;
  int starts = 0;
  int calls = 0;
  int disposals = 0;
  Completer<bool>? startup;
  final pending = <Completer<CookingResult>>[];

  @override
  bool get isHealthy => healthy;
  @override
  Future<bool> start() async {
    starts++;
    if (throwOnStart) throw StateError('startup failed');
    final result = await (startup?.future ?? Future.value(ready));
    if (!result) healthy = false;
    return result;
  }

  @override
  Future<CookingResult> cook(CookingRequest request) {
    calls++;
    if (throwOnCook) throw StateError('transport failed');
    final result = Completer<CookingResult>();
    pending.add(result);
    return result.future;
  }

  void finish(String html) =>
      pending.removeAt(0).complete(CookingResult(html: html));

  @override
  Future<void> dispose() async {
    disposals++;
    healthy = false;
    for (final result in pending) {
      result.complete(
        CookingResult(html: '', failure: CookingFailure.disposed),
      );
    }
    pending.clear();
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'oversized source is rejected before identity or runtime work',
    () async {
      var factories = 0;
      final host = CookingHostService(
        runtimeFactory: () {
          factories++;
          return FakeRuntime();
        },
      );
      addTearDown(host.dispose);
      final result = await host.cook(request(raw: 'x' * 1000000));
      expect(result.failure, CookingFailure.inputLimit);
      expect(result.requestFingerprint, isNull);
      expect(result.html.length, lessThan(8300));
      expect(factories, 0);
    },
  );

  test(
    'coalesces equal immutable requests and caches completed results',
    () async {
      final runtime = FakeRuntime();
      final host = CookingHostService(runtimeFactory: () => runtime);
      addTearDown(host.dispose);
      final first = host.cook(request());
      final second = host.cook(request());
      expect(identical(first, second), isTrue);
      await flush();
      expect(runtime.calls, 1);
      runtime.finish('<p>hello</p>');
      final result = await first;
      expect(result.requestFingerprint, request().fingerprint);
      expect(await host.cook(request()), same(result));
      expect(runtime.calls, 1);
      expect(host.cachedResultCount, 1);
    },
  );

  test(
    'context, site, account and source cannot share cached results',
    () async {
      final runtime = FakeRuntime();
      final host = CookingHostService(runtimeFactory: () => runtime);
      addTearDown(host.dispose);
      for (final input in [
        request(),
        request(site: 'b'),
        request(account: '2'),
        request(raw: 'changed'),
        request(settings: {'enable_emoji': false}),
      ]) {
        final result = host.cook(input);
        await flush();
        runtime.finish('<p>${runtime.calls}</p>');
        expect((await result).html, '<p>${runtime.calls}</p>');
      }
      expect(runtime.calls, 5);
    },
  );

  test(
    'LRU and byte limits evict results, including oversized output',
    () async {
      final runtime = FakeRuntime();
      final host = CookingHostService(
        runtimeFactory: () => runtime,
        maxCacheEntries: 2,
        maxCacheBytes: 4096,
      );
      addTearDown(host.dispose);
      Future<void> cook(String raw, [String html = '<p>ok</p>']) async {
        final result = host.cook(request(raw: raw));
        await flush();
        runtime.finish(html);
        await result;
      }

      await cook('a');
      await cook('b');
      await host.cook(request(raw: 'a'));
      await cook('c');
      expect(host.cachedResultCount, 2);
      await host.cook(request(raw: 'a'));
      expect(runtime.calls, 3);
      await cook('b');
      expect(runtime.calls, 4);
      await cook('large', 'x' * 5000);
      expect(host.cachedResultCount, 2);
      expect(host.cachedBytes, lessThanOrEqualTo(4096));
    },
  );

  test(
    'invalidation rejects races and retains occupied admission slots',
    () async {
      final runtime = FakeRuntime();
      final host = CookingHostService(
        runtimeFactory: () => runtime,
        maxPending: 1,
      );
      addTearDown(host.dispose);
      final old = host.cook(request());
      await flush();
      host.invalidate();
      expect((await old).failure, CookingFailure.stale);
      expect(
        (await host.cook(request(account: '2'))).failure,
        CookingFailure.busy,
      );
      runtime.finish('<p>private old account</p>');
      await flush();
      expect(host.cachedResultCount, 0);
      final fresh = host.cook(request(account: '2'));
      await flush();
      runtime.finish('<p>new</p>');
      expect((await fresh).html, '<p>new</p>');
      expect(runtime.calls, 2);
    },
  );

  test('queue bound still permits coalescing an admitted request', () async {
    final runtime = FakeRuntime();
    final host = CookingHostService(
      runtimeFactory: () => runtime,
      maxPending: 1,
    );
    addTearDown(host.dispose);
    final first = host.cook(request());
    expect(host.cook(request()), same(first));
    expect(
      (await host.cook(request(raw: 'other'))).failure,
      CookingFailure.busy,
    );
    await flush();
    runtime.finish('done');
    await first;
  });

  test('startup failure recreates with bounded exponential cooldown', () async {
    var now = DateTime.utc(2026);
    final runtimes = <FakeRuntime>[];
    final host = CookingHostService(
      clock: () => now,
      runtimeFactory: () {
        final runtime = FakeRuntime()..ready = runtimes.length >= 2;
        runtimes.add(runtime);
        return runtime;
      },
    );
    addTearDown(host.dispose);
    expect(await host.start(), isFalse);
    for (var i = 0; i < 10; i++) {
      expect((await host.cook(request())).failure, CookingFailure.unavailable);
    }
    expect(runtimes.length, 1);
    now = now.add(const Duration(seconds: 2));
    expect(await host.start(), isFalse);
    expect(runtimes.first.disposals, 1);
    now = now.add(const Duration(seconds: 3));
    expect(await host.start(), isFalse);
    expect(runtimes.length, 2);
    now = now.add(const Duration(seconds: 1));
    expect(await host.start(), isTrue);
    expect(runtimes.length, 3);
  });

  test(
    'fatal transport failure retires runtime without retrying the request',
    () async {
      var now = DateTime.utc(2026);
      final runtimes = <FakeRuntime>[];
      final host = CookingHostService(
        clock: () => now,
        runtimeFactory: () {
          final runtime = FakeRuntime();
          runtimes.add(runtime);
          return runtime;
        },
      );
      addTearDown(host.dispose);
      final first = host.cook(request());
      await flush();
      runtimes.single.healthy = false;
      runtimes.single.pending
          .removeAt(0)
          .complete(CookingResult(html: '', failure: CookingFailure.timeout));
      expect((await first).failure, CookingFailure.timeout);
      expect(runtimes.length, 1);
      expect((await host.cook(request())).failure, CookingFailure.unavailable);
      now = now.add(const Duration(seconds: 2));
      final next = host.cook(request());
      await flush();
      expect(runtimes.length, 2);
      runtimes.last.finish('recovered');
      expect((await next).html, 'recovered');
    },
  );

  test('throwing ports cannot bypass cooldown with a healthy flag', () async {
    for (final atStart in [true, false]) {
      var now = DateTime.utc(2026);
      final runtimes = <FakeRuntime>[];
      final host = CookingHostService(
        clock: () => now,
        runtimeFactory: () {
          final runtime = FakeRuntime()
            ..throwOnStart = atStart
            ..throwOnCook = !atStart;
          runtimes.add(runtime);
          return runtime;
        },
      );
      expect((await host.cook(request())).failure, CookingFailure.unavailable);
      for (var i = 0; i < 10; i++) {
        expect(
          (await host.cook(request())).failure,
          CookingFailure.unavailable,
        );
      }
      expect(runtimes.length, 1);
      expect(runtimes.single.calls, atStart ? 0 : 1);
      expect(runtimes.single.starts, 1);
      now = now.add(const Duration(seconds: 2));
      expect((await host.cook(request())).failure, CookingFailure.unavailable);
      expect(runtimes.length, 2);
      expect(runtimes.first.disposals, 1);
      await host.dispose();
    }
  });

  test(
    'dispose during startup rejects callers and never replaces runtime',
    () async {
      final runtime = FakeRuntime()..startup = Completer<bool>();
      final host = CookingHostService(runtimeFactory: () => runtime);
      final result = host.cook(request());
      await flush();
      final disposing = host.dispose();
      expect((await result).failure, CookingFailure.disposed);
      runtime.startup!.complete(true);
      await disposing;
      await host.dispose();
      expect(runtime.disposals, 1);
      expect(runtime.calls, 0);
      expect(await host.start(), isFalse);
      expect((await host.cook(request())).failure, CookingFailure.disposed);
    },
  );

  test(
    'real persistent worker is cached and invalidated through host port',
    () async {
      final host = CookingHostService();
      addTearDown(host.dispose);
      expect(await host.start(), isTrue);
      final first = await host.cook(request());
      expect(first.isFallback, isFalse);
      expect(first.html, contains('<strong>hello</strong>'));
      expect(await host.cook(request()), same(first));
      host.invalidate();
      expect(await host.cook(request()), isNot(same(first)));
    },
  );
}
