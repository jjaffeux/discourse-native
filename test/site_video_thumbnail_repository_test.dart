import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_thumbnail_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
final _source = Uri.parse('$_site/uploads/clip.mp4');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coalesces consumers and reuses successful thumbnails', () async {
    final harness = _Harness();
    final first = harness.acquire();
    final second = harness.acquire();
    await _flush();
    expect(harness.jobs, hasLength(1));
    first.dispose();
    expect(harness.jobs.single.cancelled, isFalse);
    final bytes = Uint8List.fromList([1, 2, 3]);
    harness.jobs.single.result.complete(bytes);
    expect(await first.result, same(bytes));
    expect(await second.result, same(bytes));
    second.dispose();
    expect(await harness.acquire().result, same(bytes));
    expect(harness.jobs, hasLength(1));
  });

  test('cancels abandoned work and starts the next queued preview', () async {
    final harness = _Harness(maxConcurrent: 1);
    final first = harness.acquire();
    final removed = harness.acquire('removed');
    final next = harness.acquire('next');
    await _flush();
    expect(harness.jobs, hasLength(1));
    removed.dispose();
    first.dispose();
    expect(await first.result, isNull);
    expect(await removed.result, isNull);
    await _flush();
    expect(harness.jobs.first.cancelled, isTrue);
    expect(harness.jobs, hasLength(2));
    expect(harness.jobs.last.source.path, '/uploads/next.mp4');
    harness.jobs.first.result.complete(Uint8List.fromList([9]));
    harness.jobs.last.result.complete(Uint8List.fromList([2]));
    expect(await next.result, orderedEquals([2]));
    harness.acquire();
    await _flush();
    expect(
      harness.jobs,
      hasLength(3),
      reason: 'Cancelled bytes are not cached',
    );
  });

  test('bounds concurrency and the pending backlog', () async {
    final harness = _Harness(maxConcurrent: 2, maxPending: 3);
    final requests = [
      for (var index = 0; index < 4; index++) harness.acquire('$index'),
    ];
    await _flush();
    expect(harness.jobs, hasLength(2));
    expect(await requests.last.result, isNull);
    harness.jobs.first.result.complete(Uint8List.fromList([1]));
    await _flush();
    expect(harness.jobs, hasLength(3));
  });

  test(
    'forgets cached bytes and cancels work on account replacement',
    () async {
      final harness = _Harness();
      final first = harness.acquire();
      await _flush();
      harness.jobs.single.result.complete(Uint8List.fromList([1]));
      await first.result;
      final pending = harness.acquire('pending');
      await _flush();
      harness.lifecycle.invalidate(_site);
      harness.repository.forget(_site);
      expect(await pending.result, isNull);
      expect(harness.jobs.last.cancelled, isTrue);
      harness.acquire();
      await _flush();
      expect(harness.jobs, hasLength(3));
    },
  );

  test(
    'rejects late bytes after lifecycle invalidation without explicit forget',
    () async {
      final harness = _Harness();
      final first = harness.acquire();
      await _flush();
      harness.lifecycle.invalidate(_site);
      final replacement = harness.acquire();
      await _flush();
      harness.jobs.first.result.complete(Uint8List.fromList([1]));
      harness.jobs.last.result.complete(Uint8List.fromList([2]));
      expect(await first.result, isNull);
      expect(await replacement.result, orderedEquals([2]));
      expect(await harness.acquire().result, orderedEquals([2]));
    },
  );

  test('briefly caches failures and permits retry after cooldown', () async {
    final harness = _Harness();
    final first = harness.acquire();
    await _flush();
    harness.jobs.single.result.completeError(StateError('Unsupported codec'));
    expect(await first.result, isNull);
    expect(await harness.acquire().result, isNull);
    expect(harness.jobs, hasLength(1));
    harness.now = harness.now.add(const Duration(seconds: 31));
    harness.acquire();
    await _flush();
    expect(harness.jobs, hasLength(2));
  });

  test(
    'evicts least recently used thumbnails within the byte budget',
    () async {
      final harness = _Harness(maxCachedBytes: 5);
      for (final name in ['first', 'second']) {
        final request = harness.acquire(name);
        await _flush();
        harness.jobs.last.result.complete(Uint8List.fromList([1, 2, 3]));
        await request.result;
      }
      expect(await harness.acquire('second').result, orderedEquals([1, 2, 3]));
      harness.acquire('first');
      await _flush();
      expect(harness.jobs, hasLength(3));
    },
  );

  test(
    'rejects unsafe sources and releases all active work on disposal',
    () async {
      final harness = _Harness();
      for (final source in [
        'file:///tmp/video.mp4',
        'https://user:pass@forum.example/a.mp4',
      ]) {
        expect(
          await harness.repository
              .acquire(siteUrl: _site, url: Uri.parse(source))
              .result,
          isNull,
        );
      }
      expect(harness.jobs, isEmpty);
      final pending = harness.acquire();
      await _flush();
      harness.repository.dispose();
      expect(await pending.result, isNull);
      expect(harness.jobs.single.cancelled, isTrue);
      expect(await harness.acquire().result, isNull);
    },
  );

  test(
    'native bridge passes only the resolved URL and cancels by request id',
    () async {
      const channel = MethodChannel('org.discourse.native/video_thumbnails');
      final calls = <MethodCall>[];
      final response = Completer<Uint8List?>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'generate' ? response.future : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final request = generateNativeVideoThumbnail(_source);
      await _flush();
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments.keys, unorderedEquals(['id', 'url']));
      expect(arguments['url'], _source.toString());
      request.dispose();
      request.dispose();
      await _flush();
      expect(calls, hasLength(2));
      expect(calls.last.method, 'cancel');
      expect(calls.last.arguments, {'id': arguments['id']});
      response.complete(null);
      expect(await request.result, isNull);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Harness {
  _Harness({
    int maxConcurrent = 2,
    int maxPending = 32,
    int maxCachedBytes = 1024,
  }) {
    repository = SiteVideoThumbnailRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: lifecycle,
      maxConcurrent: maxConcurrent,
      maxPending: maxPending,
      maxCachedBytes: maxCachedBytes,
      clock: () => now,
      generator: (source) {
        final job = _Extraction(source);
        jobs.add(job);
        return VideoThumbnailRequest(
          job.result.future,
          () => job.cancelled = true,
        );
      },
    );
    addTearDown(repository.dispose);
  }

  final lifecycle = SiteLifecycle();
  final jobs = <_Extraction>[];
  var now = DateTime(2026);
  late final SiteVideoThumbnailRepository repository;

  VideoThumbnailRequest acquire([String name = 'clip']) => repository.acquire(
    siteUrl: _site,
    url: Uri.parse('$_site/uploads/$name.mp4'),
  );
}

final class _Extraction {
  _Extraction(this.source);

  final Uri source;
  final result = Completer<Uint8List?>();
  bool cancelled = false;
}
