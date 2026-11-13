import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/coalescing_snapshot_writer.dart';
import 'package:discourse_native/src/data/file_byte_cache_store.dart';
import 'package:discourse_native/src/data/http_basic_auth.dart';
import 'package:discourse_native/src/data/origin_request_gate.dart';
import 'package:discourse_native/src/data/preference_snapshots.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/basic_auth_storage.dart';

void main() {
  test('hydration admission precedes synchronous reader reentry', () async {
    final snapshots = PreferenceSnapshots<String, int>();
    Future<int>? joined;
    var reads = 0;
    final first = snapshots.ensure('layout', () {
      reads++;
      joined = snapshots.ensure('layout', () async {
        reads++;
        return 99;
      });
      return Future.value(7);
    });
    expect(await first, 7);
    expect(await joined, 7);
    expect(reads, 1);
    expect(snapshots.peek('layout'), 7);
  });

  test(
    'synchronous hydration failures settle futures and allow retry',
    () async {
      final snapshots = PreferenceSnapshots<String, int>();
      Future<int>? result;
      expect(() {
        result = snapshots.ensure('layout', () => throw StateError('storage'));
      }, returnsNormally);
      await expectLater(result, throwsStateError);
      expect(await snapshots.ensure('layout', () async => 7), 7);
    },
  );

  test(
    'coalesced replacement writes retain the newest submitter zone',
    () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final contexts = <Object?>[];
      final writer = CoalescingSnapshotWriter<int>(
        owner: Object(),
        key: 'layout',
        writeSnapshot: (value) async {
          contexts.add(Zone.current[#account]);
          if (value == 0) {
            started.complete();
            await release.future;
          }
        },
      );
      final first = runZoned(
        () => writer.save(0),
        zoneValues: {#account: 'first'},
      );
      await started.future;
      final superseded = runZoned(
        () => writer.save(1),
        zoneValues: {#account: 'old'},
      );
      final newest = runZoned(
        () => writer.save(2),
        zoneValues: {#account: 'new'},
      );
      release.complete();
      await Future.wait([first, superseded, newest]);
      expect(contexts, ['first', 'new']);
    },
  );

  test(
    'a queued write failure crosses the submitter error zone without stranding saves',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final observed = Completer<Object>();
      final unexpected = <Object>[];
      final failure = StateError('storage');
      final writer = CoalescingSnapshotWriter<int>(
        owner: Object(),
        key: 'layout',
        writeSnapshot: (value) async {
          if (value == 0) {
            started.complete();
            await release.future;
          } else {
            throw failure;
          }
        },
      );
      final first = writer.save(0);
      await started.future;
      runZonedGuarded(() {
        unawaited(
          writer
              .save(1)
              .then<void>(
                (_) => observed.complete('unexpected success'),
                onError: (Object error) => observed.complete(error),
              ),
        );
      }, (error, _) => unexpected.add(error));
      release.complete();
      await first;
      expect(
        await observed.future.timeout(const Duration(seconds: 2)),
        same(failure),
      );
      expect(unexpected, isEmpty);
    },
  );

  test('file cache owns bytes at write submission', () async {
    final directory = await Directory.systemTemp.createTemp(
      'native-byte-owner-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime.utc(2026);
    final store = FileByteCacheStore(directory, clock: () => now);
    final source = Uint8List.fromList([1, 2, 3]);
    final saving = store.write(
      'image',
      source,
      expiresAt: now.add(const Duration(days: 1)),
    );
    source[0] = 99;
    await saving;
    expect(await store.read('image'), [1, 2, 3]);
  });

  test('retirement subscriptions have independent registration identity', () {
    final lifecycle = SiteLifecycle();
    final lease = lifecycle.capture('https://example.com');
    var calls = 0;
    void cleanup() => calls++;
    final detach = lease.onRetire(cleanup);
    lease.onRetire(cleanup);
    detach();
    detach();
    lifecycle.invalidate('https://example.com');
    expect(calls, 1);
  });

  test(
    'retention owns its submitted origins while waiting in the queue',
    () async {
      final storage = BasicAuthMemoryStorage();
      final store = HttpBasicAuthStore(storage: storage);
      for (final host in ['a', 'b']) {
        await store.remember(
          HttpBasicAuthentication(
            origin: Uri.parse('https://$host.example'),
            username: 'user',
            password: 'password',
          ),
        );
      }
      final sites = ['https://a.example'];
      final retaining = store.retainOrigins(sites);
      sites[0] = 'https://b.example';
      await retaining;
      final reopened = HttpBasicAuthStore(storage: storage);
      await reopened.load();
      expect(reopened.protects(Uri.parse('https://a.example')), isTrue);
      expect(reopened.protects(Uri.parse('https://b.example')), isFalse);
    },
  );

  test('reentrant queue admission cannot exceed the origin capacity', () async {
    final gate = OriginRequestGate(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      maxQueuedPerOrigin: 10,
      cooldownPolicy: OriginRequestCooldownPolicy.wait,
    );
    addTearDown(gate.close);
    final url = Uri.parse('https://example.com');
    final active = await gate.acquire(url);
    Future<OriginRequestLease>? nested;
    var nestedGranted = false;
    var scanning = false;
    final first = gate.acquire(
      url,
      resolvePriority: () {
        if (scanning && nested == null) {
          // Reserve the flag before reentering the admission boundary.
          scanning = false;
          nested = gate.acquire(url).then((lease) {
            nestedGranted = true;
            return lease;
          });
        }
        return OriginRequestPriority.normal;
      },
    );
    scanning = true;
    active.release();
    final firstLease = await first;
    await Future<void>.delayed(Duration.zero);
    expect(nestedGranted, isFalse);
    firstLease.release();
    (await nested)!.release();
  });
  test(
    'a priority callback may revoke its own queued admission by cooldown',
    () async {
      final gate = OriginRequestGate(
        maxConcurrent: 1,
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 10,
        cooldownPolicy: OriginRequestCooldownPolicy.reject,
      );
      addTearDown(gate.close);
      final url = Uri.parse('https://example.com');
      final active = await gate.acquire(url);
      var revoke = false;
      final pending = gate.acquire(
        url,
        resolvePriority: () {
          if (revoke) {
            revoke = false;
            gate.extendCooldown(url, const Duration(seconds: 1));
          }
          return OriginRequestPriority.normal;
        },
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<OriginRequestGateCooldownException>()),
      );
      revoke = true;
      expect(active.release, returnsNormally);
      await rejected;
      final other = await gate.acquire(Uri.parse('https://other.example'));
      other.release();
    },
  );
}
