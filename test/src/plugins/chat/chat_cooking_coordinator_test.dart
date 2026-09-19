import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/plugins/chat/chat_cooking_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/manual_scheduler.dart';

const _site = 'https://chat.example';
const _otherSite = 'https://other.example';

void main() {
  group('ChatCookingCoordinator', () {
    test('coalesces drafts before building snapshots', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final first = harness.schedule('draft', 'a');
      harness.clock.advance(const Duration(milliseconds: 30));
      final second = harness.schedule('draft', 'ab');
      harness.clock.advance(const Duration(milliseconds: 30));
      final last = harness.schedule('draft', 'abc');

      expect(await first, isNull);
      expect(await second, isNull);
      expect(harness.assembled, isEmpty);
      expect(harness.clock.activeTimerCount, 1);
      harness.clock.advance(const Duration(milliseconds: 39));
      await _flush();
      expect(harness.started, isEmpty);
      harness.clock.advance(const Duration(milliseconds: 1));
      await _flush();
      expect(harness.assembled, ['abc']);
      expect(harness.started.map((job) => job.raw), ['abc']);
      expect(harness.clock.activeTimerCount, 0);
      final result = CookingResult(html: '<p>abc</p>');
      harness.started.single.completion.complete(result);
      expect(await last, same(result));
    });

    test('urgent work defers assembly without a debounce timer', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final result = harness.schedule('send', 'sent', urgent: true);

      // The caller can stage a row and return its send handle in this stack.
      expect(harness.assembled, isEmpty);
      expect(harness.started, isEmpty);
      expect(harness.clock.activeTimerCount, 0);
      await _flush();
      expect(harness.assembled, ['sent']);
      harness.finishNext();
      expect((await result)?.html, 'sent');
    });

    test('urgent jobs run FIFO before ready drafts', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final active = harness.schedule('active', 'active', urgent: true);
      await _flush();
      final draftOne = harness.schedule('draft-1', 'draft-1');
      final draftTwo = harness.schedule('draft-2', 'draft-2');
      harness.clock.advance(const Duration(milliseconds: 40));
      final send = harness.schedule('send', 'send', urgent: true);
      final edit = harness.schedule('edit', 'edit', urgent: true);
      await _flush();
      expect(harness.assembled, ['active']);

      for (final expected in ['active', 'send', 'edit', 'draft-1', 'draft-2']) {
        expect(harness.started.last.raw, expected);
        harness.finishNext();
        await _flush();
      }
      expect(harness.assembled, [
        'active',
        'send',
        'edit',
        'draft-1',
        'draft-2',
      ]);
      expect(
        await Future.wait([active, send, edit, draftOne, draftTwo]),
        everyElement(isNotNull),
      );
    });

    test('A/B/A revisions cannot revive an older active result', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final first = harness.schedule('draft', 'A', urgent: true);
      await _flush();
      final middle = harness.schedule('draft', 'B', urgent: true);
      final last = harness.schedule('draft', 'A', urgent: true);
      expect(await first, isNull);
      expect(await middle, isNull);
      await _flush();
      expect(harness.assembled, ['A']);

      harness.finishNext(html: 'old A');
      await _flush();
      expect(harness.assembled, ['A', 'A']);
      harness.finishNext(html: 'new A');
      expect((await last)?.html, 'new A');
    });

    test(
      'cancelled active work keeps its physical slot until completion',
      () async {
        final harness = _Harness();
        addTearDown(harness.coordinator.dispose);
        final active = harness.schedule('active', 'active', urgent: true);
        await _flush();
        harness.coordinator.cancel('active');
        final send = harness.schedule('send', 'send', urgent: true);
        expect(await active, isNull);
        await _flush();
        expect(harness.started.length, 1);
        harness.finishNext();
        await _flush();
        expect(harness.started.map((job) => job.raw), ['active', 'send']);
        harness.finishNext();
        expect((await send)?.html, 'send');
      },
    );

    test(
      'stale queued work never assembles and stale completions are dropped',
      () async {
        final harness = _Harness();
        addTearDown(harness.coordinator.dispose);
        var current = true;
        final staleQueued = harness.schedule(
          'queued',
          'queued',
          isCurrent: () => current,
        );
        current = false;
        harness.clock.advance(const Duration(milliseconds: 40));
        expect(await staleQueued, isNull);
        expect(harness.assembled, isEmpty);

        current = true;
        final staleActive = harness.schedule(
          'active',
          'active',
          urgent: true,
          isCurrent: () => current,
        );
        await _flush();
        current = false;
        harness.finishNext();
        expect(await staleActive, isNull);
      },
    );

    test(
      'cancel removes queued timers without affecting a reused key',
      () async {
        final harness = _Harness();
        addTearDown(harness.coordinator.dispose);
        final old = harness.schedule('draft', 'old');
        harness.coordinator.cancel('draft');
        expect(harness.clock.activeTimerCount, 0);
        final next = harness.schedule('draft', 'next');
        expect(await old, isNull);
        harness.clock.advance(const Duration(milliseconds: 40));
        await _flush();
        expect(harness.assembled, ['next']);
        harness.finishNext();
        expect((await next)?.html, 'next');
      },
    );

    test('forget invalidates only its site including active work', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final active = harness.schedule('active', 'active', urgent: true);
      await _flush();
      final queued = harness.schedule('queued', 'queued');
      final other = harness.schedule('other', 'other', siteUrl: _otherSite);
      harness.coordinator.forget(_site);
      expect(await active, isNull);
      expect(await queued, isNull);
      expect(harness.clock.activeTimerCount, 1);
      harness.clock.advance(const Duration(milliseconds: 40));
      harness.finishNext();
      await _flush();
      expect(harness.assembled, ['active', 'other']);
      harness.finishNext();
      expect((await other)?.html, 'other');
    });

    test(
      'dispose settles all consumers, cancels timers and observes late errors',
      () async {
        final harness = _Harness();
        final active = harness.schedule('active', 'active', urgent: true);
        await _flush();
        final queued = harness.schedule('queued', 'queued');
        harness.coordinator.dispose();
        harness.coordinator.dispose();
        expect(harness.clock.activeTimerCount, 0);
        expect(await active, isNull);
        expect(await queued, isNull);
        expect(await harness.schedule('later', 'later'), isNull);
        harness.started.single.completion.completeError(StateError('late'));
        await _flush();
        harness.clock.advance(const Duration(days: 1));
        await _flush();
        expect(harness.assembled, ['active']);
      },
    );

    test('disposal before the drain prevents urgent assembly', () async {
      final harness = _Harness();
      final pending = harness.schedule('urgent', 'urgent', urgent: true);
      harness.coordinator.dispose();
      expect(await pending, isNull);
      expect(harness.assembled, isEmpty);
    });

    test(
      'bounds queued drafts before assembly by keeping newest work',
      () async {
        final harness = _Harness(maxQueuedJobs: 2);
        addTearDown(harness.coordinator.dispose);
        final active = harness.schedule('active', 'active', urgent: true);
        await _flush();
        final drafts = [
          for (var index = 0; index < 100; index++)
            harness.schedule('draft-$index', 'draft-$index'),
        ];
        expect(harness.clock.activeTimerCount, 2);
        expect(await Future.wait(drafts.take(98)), everyElement(isNull));
        expect(harness.assembled, ['active']);
        harness.clock.advance(const Duration(milliseconds: 40));
        harness.finishNext();
        await _flush();
        harness.finishNext();
        await _flush();
        harness.finishNext();
        expect(await active, isNotNull);
        expect(await Future.wait(drafts.skip(98)), everyElement(isNotNull));
        expect(harness.assembled, ['active', 'draft-98', 'draft-99']);
      },
    );

    test(
      'urgent admission displaces drafts and protects queued urgent work',
      () async {
        final harness = _Harness(maxQueuedJobs: 2);
        addTearDown(harness.coordinator.dispose);
        final draft = harness.schedule('draft', 'draft');
        final first = harness.schedule('send-1', 'send-1', urgent: true);
        final second = harness.schedule('send-2', 'send-2', urgent: true);
        final rejectedUrgent = harness.schedule(
          'send-3',
          'send-3',
          urgent: true,
        );
        final rejectedDraft = harness.schedule('next-draft', 'next-draft');
        expect(await draft, isNull);
        expect(await rejectedUrgent, isNull);
        expect(await rejectedDraft, isNull);
        expect(harness.clock.activeTimerCount, 0);
        expect(harness.assembled, ['send-1']);
        harness.finishNext();
        await _flush();
        harness.finishNext();
        expect(await first, isNotNull);
        expect(await second, isNotNull);
        expect(harness.assembled, ['send-1', 'send-2']);
      },
    );

    for (final failure in ['builder', 'current', 'cook-sync', 'cook-async']) {
      test(
        '$failure failure settles null and permits subsequent work',
        () async {
          var shouldFail = true;
          final coordinator = ChatCookingCoordinator(
            cook: (request) {
              if (shouldFail && failure == 'cook-sync') {
                throw StateError(failure);
              }
              if (shouldFail && failure == 'cook-async') {
                return Future.error(StateError(failure));
              }
              return Future.value(CookingResult(html: request.raw));
            },
          );
          addTearDown(coordinator.dispose);
          Future<CookingResult?> schedule() => coordinator.schedule(
            key: 'key',
            siteUrl: _site,
            urgent: true,
            buildRequest: () {
              if (shouldFail && failure == 'builder') throw StateError(failure);
              return _request('source');
            },
            isCurrent: () {
              if (shouldFail && failure == 'current') throw StateError(failure);
              return true;
            },
          );
          expect(await schedule(), isNull);
          shouldFail = false;
          expect((await schedule())?.html, 'source');
        },
      );
    }

    test(
      'reentrant builder replacement cannot cook or remove the new job',
      () async {
        final harness = _Harness();
        addTearDown(harness.coordinator.dispose);
        late Future<CookingResult?> next;
        final first = harness.coordinator.schedule(
          key: 'key',
          siteUrl: _site,
          urgent: true,
          isCurrent: () => true,
          buildRequest: () {
            next = harness.schedule('key', 'replacement', urgent: true);
            return _request('superseded');
          },
        );
        expect(await first, isNull);
        await _flush();
        expect(harness.started.map((job) => job.raw), ['replacement']);
        harness.finishNext();
        expect((await next)?.html, 'replacement');
      },
    );

    test('reentrant freshness check cannot build cancelled work', () async {
      final harness = _Harness();
      addTearDown(harness.coordinator.dispose);
      final first = harness.schedule(
        'key',
        'cancelled',
        urgent: true,
        isCurrent: () {
          harness.coordinator.cancel('key');
          return true;
        },
      );
      expect(await first, isNull);
      expect(harness.assembled, isEmpty);
      expect(harness.started, isEmpty);
    });

    test('rejects invalid scheduler limits', () {
      Future<CookingResult> cook(CookingRequest _) =>
          Future.value(CookingResult(html: ''));
      expect(
        () => ChatCookingCoordinator(cook: cook, maxQueuedJobs: 0),
        throwsArgumentError,
      );
      expect(
        () => ChatCookingCoordinator(
          cook: cook,
          draftDebounce: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    testWidgets('synchronous teardown leaves no widget debounce timers', (
      tester,
    ) async {
      final coordinator = ChatCookingCoordinator(
        cook: (_) => Future.value(CookingResult(html: 'unused')),
      );
      final pending = coordinator.schedule(
        key: 'draft',
        siteUrl: _site,
        buildRequest: () => _request('draft'),
        isCurrent: () => true,
      );
      coordinator.dispose();
      await tester.pump();
      expect(await pending, isNull);
      // Widget binding checks pending timers; do not advance the debounce time.
    });
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

CookingRequest _request(String raw) => CookingRequest(
  raw: raw,
  profile: CookingProfile.chat,
  snapshot: CookingSnapshot(siteId: _site, accountId: '1'),
);

final class _Harness {
  _Harness({int maxQueuedJobs = 16}) {
    coordinator = ChatCookingCoordinator(
      maxQueuedJobs: maxQueuedJobs,
      timerFactory: clock.createTimer,
      cook: (request) {
        final job = _Cook(request.raw);
        started.add(job);
        return job.completion.future;
      },
    );
  }

  final clock = ManualScheduler();
  final assembled = <String>[];
  final started = <_Cook>[];
  late final ChatCookingCoordinator coordinator;

  Future<CookingResult?> schedule(
    Object key,
    String raw, {
    String siteUrl = _site,
    bool urgent = false,
    bool Function()? isCurrent,
  }) => coordinator.schedule(
    key: key,
    siteUrl: siteUrl,
    urgent: urgent,
    isCurrent: isCurrent ?? () => true,
    buildRequest: () {
      assembled.add(raw);
      return _request(raw);
    },
  );

  void finishNext({String? html}) {
    final next = started.firstWhere((job) => !job.completion.isCompleted);
    next.completion.complete(CookingResult(html: html ?? next.raw));
  }
}

final class _Cook {
  _Cook(this.raw);
  final String raw;
  final completion = Completer<CookingResult>();
}
