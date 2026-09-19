import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_cooking_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_prepared_cooking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/manual_scheduler.dart';

const _site = 'https://chat.example';
const _otherSite = 'https://other.example';

void main() {
  group('ChatPreparedCooking', () {
    test(
      'suspended drafts cancel timers and resume after unchanged preparation',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'source');
        harness.prepared.suspend('draft');
        expect(harness.clock.activeTimerCount, 0);
        expect(harness.activeWatches, 1);
        harness.notify(_site);
        harness.prepared.refreshSite(_site);
        await harness.debounce();
        expect(harness.contextCalls, 0);
        harness.prepare('draft', 'source');
        expect(harness.clock.activeTimerCount, 1);
        await harness.debounce();
        harness.finish('resumed');
        await _flush();
        expect(harness.ready('draft', 'source'), 'resumed');
      },
    );

    test(
      'suspension retains ready HTML and invalidates it without hidden work',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'source');
        await harness.debounce();
        harness.finish('ready');
        await _flush();
        harness.prepared.suspend('draft');
        expect(harness.ready('draft', 'source'), 'ready');
        harness.prepare('draft', 'source');
        expect(harness.clock.activeTimerCount, 0);
        expect(harness.ready('draft', 'source'), 'ready');
        harness.prepared.suspend('draft');
        harness.notify(_site);
        expect(harness.ready('draft', 'source'), isNull);
        expect(harness.clock.activeTimerCount, 0);
        await harness.debounce();
        expect(harness.requests.length, 1);
        harness.prepare('draft', 'source');
        await harness.debounce();
        harness.finish('refreshed');
        await _flush();
        expect(harness.ready('draft', 'source'), 'refreshed');
      },
    );

    test(
      'suspended active completion cannot satisfy resumed identical raw',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'source');
        await harness.debounce();
        harness.prepared.suspend('draft');
        harness.prepare('draft', 'source');
        await harness.debounce();
        expect(harness.requests.length, 1);
        harness.finish('old');
        await _flush();
        expect(harness.ready('draft', 'source'), isNull);
        expect(harness.requests.length, 2);
        harness.finish('resumed');
        await _flush();
        expect(harness.ready('draft', 'source'), 'resumed');
      },
    );

    testWidgets('suspend removes widget-zone timers before owner disposal', (
      tester,
    ) async {
      final prepared = ChatPreparedCooking(
        host: PluginCookingHost(
          request:
              ({
                required String siteUrl,
                required String raw,
                CookingProfile profile = CookingProfile.post,
                CookingContext context = const CookingContext(),
                CookingCachedMetadata? cachedMetadata,
              }) => CookingRequest(
                raw: raw,
                snapshot: CookingSnapshot(siteId: siteUrl, accountId: '1'),
              ),
          cook: (_) => Future.value(CookingResult(html: 'unused')),
        ),
        contextFor: (_) => const CookingContext(),
      );
      addTearDown(prepared.dispose);
      prepared.prepare(key: 'draft', siteUrl: _site, raw: 'source');
      prepared.suspend('draft');
      await tester.pump();
      // The owner outlives the widget invariant; no advancing the 40ms timer.
      expect(prepared.takeReady(key: 'draft', raw: 'source'), isNull);
    });

    test(
      'coalesces repeated raw before context and request assembly',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'first');
        harness.clock.advance(const Duration(milliseconds: 30));
        harness.prepare('draft', 'first');
        expect(harness.contextCalls, 0);
        expect(harness.requests, isEmpty);
        expect(harness.activeWatches, 1);
        expect(harness.clock.activeTimerCount, 1);
        harness.clock.advance(const Duration(milliseconds: 10));
        await _flush();
        expect(harness.contextCalls, 1);
        expect(harness.requests.single.profile, CookingProfile.chat);
        expect(harness.cooks.single.request, same(harness.requests.single));
        harness.finish('cooked');
        await _flush();
        expect(harness.ready('draft', 'first'), 'cooked');
        expect(harness.ready('draft', 'first'), 'cooked');
        expect(harness.ready('draft', 'different'), isNull);
        expect(harness.contextCalls, 1);
        expect(harness.requests.length, 1);
      },
    );

    test('rapid source revisions assemble only the last snapshot', () async {
      final harness = _Harness();
      addTearDown(harness.prepared.dispose);
      for (var index = 0; index < 100; index++) {
        harness.prepare('draft', 'source-$index');
      }
      expect(harness.activeWatches, 1);
      expect(harness.clock.activeTimerCount, 1);
      expect(harness.contextCalls, 0);
      await harness.debounce();
      expect(harness.requests.map((request) => request.raw), ['source-99']);
      harness.finish('last');
      await _flush();
      expect(harness.ready('draft', 'source-99'), 'last');
    });

    test(
      'A/B/A cannot accept old results or old subscription callbacks',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'A');
        final oldNotification = harness.watches.single.onChanged;
        await harness.debounce();
        harness.prepare('draft', 'B');
        harness.prepare('draft', 'A');
        oldNotification();
        await harness.debounce();
        expect(harness.requests.length, 1);
        harness.finish('old A');
        await _flush();
        expect(harness.ready('draft', 'A'), isNull);
        expect(harness.requests.map((request) => request.raw), ['A', 'A']);
        harness.finish('new A');
        await _flush();
        expect(harness.ready('draft', 'A'), 'new A');
      },
    );

    test(
      'watched changes clear ready HTML and debounce a fresh context',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'same raw');
        await harness.debounce();
        harness.finish('old');
        await _flush();
        harness.locale = 'fr';
        harness.notify(_site);
        harness.notify(_site);
        expect(harness.ready('draft', 'same raw'), isNull);
        expect(harness.contextCalls, 1);
        expect(harness.clock.activeTimerCount, 1);
        await harness.debounce();
        expect(harness.requests.last.snapshot.context.locale, 'fr');
        harness.finish('new');
        await _flush();
        expect(harness.ready('draft', 'same raw'), 'new');
      },
    );

    test(
      'takeReady rejects stale host requests without rebuilding them',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'source');
        await harness.debounce();
        harness.finish('old');
        await _flush();
        harness.generations[_site] = 1;
        expect(harness.ready('draft', 'source'), isNull);
        expect(harness.requests.length, 1);
        expect(harness.contextCalls, 1);
        await harness.debounce();
        harness.finish('new');
        await _flush();
        expect(harness.ready('draft', 'source'), 'new');
      },
    );

    test('same raw explicit contexts compare by value', () async {
      final harness = _Harness();
      addTearDown(harness.prepared.dispose);
      void prepare(int authorId) => harness.prepared.prepare(
        key: 'edit',
        siteUrl: _site,
        raw: 'source',
        context: CookingContext(authorId: authorId),
      );
      prepare(1);
      harness.clock.advance(const Duration(milliseconds: 30));
      prepare(1);
      harness.clock.advance(const Duration(milliseconds: 10));
      await _flush();
      expect(harness.requests.single.snapshot.context.authorId, 1);
      expect(harness.contextCalls, 0);
      harness.finish('one');
      await _flush();
      prepare(2);
      expect(harness.ready('edit', 'source'), isNull);
      await harness.debounce();
      expect(harness.requests.last.snapshot.context.authorId, 2);
      harness.finish('two');
      await _flush();
      expect(harness.ready('edit', 'source'), 'two');
    });

    test(
      'refresh captures latest edit context lazily without closure churn',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        var builderCalls = 0;
        var locale = 'en';
        var editorId = 1;
        void prepare() => harness.prepared.prepare(
          key: 'edit',
          siteUrl: _site,
          raw: 'source',
          contextBuilder: () {
            builderCalls++;
            return CookingContext(
              authorId: 42,
              editorId: editorId,
              locale: locale,
            );
          },
        );
        prepare();
        harness.clock.advance(const Duration(milliseconds: 30));
        prepare();
        harness.clock.advance(const Duration(milliseconds: 10));
        await _flush();
        expect(builderCalls, 1);
        harness.finish('first');
        await _flush();
        locale = 'fr';
        editorId = 2;
        harness.prepared.refreshSite(_site);
        expect(builderCalls, 1);
        expect(harness.ready('edit', 'source'), isNull);
        await harness.debounce();
        final context = harness.requests.last.snapshot.context;
        expect(context.authorId, 42);
        expect(context.editorId, 2);
        expect(context.locale, 'fr');
        harness.finish('refreshed');
        await _flush();
        expect(harness.ready('edit', 'source'), 'refreshed');
      },
    );

    test('LRU draft eviction unsubscribes and cancels queued work', () async {
      final harness = _Harness(maxDrafts: 2);
      addTearDown(harness.prepared.dispose);
      harness.prepare('first', 'first');
      harness.prepare('second', 'second');
      harness.prepare('first', 'first');
      harness.prepare('third', 'third');
      expect(harness.activeWatches, 2);
      expect(
        harness.watches
            .where((watch) => watch.active)
            .map((watch) => watch.raw),
        ['first', 'third'],
      );
      await harness.debounce();
      harness.finish('first');
      await _flush();
      harness.finish('third');
      await _flush();
      expect(harness.requests.map((request) => request.raw), [
        'first',
        'third',
      ]);
      expect(harness.ready('second', 'second'), isNull);
    });

    test(
      'ready HTML budget counts UTF-8 across drafts and declines oversize',
      () async {
        final harness = _Harness(maxReadyBytes: 8);
        addTearDown(harness.prepared.dispose);
        harness.prepare('first', 'first');
        await harness.debounce();
        harness.finish('😀😀');
        await _flush();
        expect(harness.ready('first', 'first'), '😀😀');
        harness.prepare('second', 'second');
        await harness.debounce();
        harness.finish('x');
        await _flush();
        expect(harness.ready('first', 'first'), isNull);
        expect(harness.ready('second', 'second'), 'x');
        harness.prepare('third', 'third');
        await harness.debounce();
        harness.finish('😀😀😀');
        await _flush();
        expect(harness.ready('third', 'third'), isNull);
        expect(harness.ready('second', 'second'), 'x');
      },
    );

    test(
      'urgent submission uses the original request and defers all assembly',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        var builderCalls = 0;
        final future = harness.prepared.cook(
          key: 'send',
          siteUrl: _site,
          raw: 'source',
          contextBuilder: () {
            builderCalls++;
            return const CookingContext(authorId: 42);
          },
          isCurrent: () => true,
        );
        expect(builderCalls, 0);
        expect(harness.requests, isEmpty);
        expect(harness.clock.activeTimerCount, 0);
        await _flush();
        expect(builderCalls, 1);
        expect(harness.requests.single.snapshot.context.authorId, 42);
        expect(harness.cooks.single.request, same(harness.requests.single));
        harness.finish('sent');
        expect(await future, 'sent');
        expect(harness.requests.length, 1);
      },
    );

    for (final invalidation in [
      'caller',
      'host',
      'cancel',
      'forget',
      'dispose',
    ]) {
      test('submission drops results after $invalidation', () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        var current = true;
        final future = harness.cook('send', 'source', isCurrent: () => current);
        await _flush();
        switch (invalidation) {
          case 'caller':
            current = false;
          case 'host':
            harness.generations[_site] = 1;
          case 'cancel':
            harness.prepared.cancel('send');
          case 'forget':
            harness.prepared.forget(_site);
          case 'dispose':
            harness.prepared.dispose();
        }
        harness.finish('stale');
        expect(await future, isNull);
      });
    }

    test(
      'one-shot replacement and matching draft keys have separate ownership',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('shared', 'draft');
        final first = harness.cook('shared', 'A');
        await _flush();
        final second = harness.cook('shared', 'B');
        final last = harness.cook('shared', 'A');
        expect(await first, isNull);
        expect(await second, isNull);
        harness.finish('old A');
        await _flush();
        harness.finish('new A');
        expect(await last, 'new A');
        await harness.debounce();
        harness.finish('draft HTML');
        await _flush();
        expect(harness.ready('shared', 'draft'), 'draft HTML');
      },
    );

    test(
      'bounds urgent admission before constructing excess requests',
      () async {
        final harness = _Harness(maxSubmissions: 2);
        addTearDown(harness.prepared.dispose);
        final first = harness.cook('first', 'first');
        final second = harness.cook('second', 'second');
        final rejected = harness.cook('third', 'third');
        expect(await rejected, isNull);
        expect(harness.requests.map((request) => request.raw), ['first']);
        harness.finish('one');
        expect(await first, 'one');
        await _flush();
        harness.finish('two');
        expect(await second, 'two');
        final next = harness.cook('third', 'third');
        await _flush();
        harness.finish('three');
        expect(await next, 'three');
      },
    );

    test(
      'forget and cancel unsubscribe drafts without touching other sites',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('a', 'a');
        harness.prepare('b', 'b', siteUrl: _otherSite);
        harness.prepared.forget(_site);
        expect(harness.activeWatches, 1);
        expect(harness.clock.activeTimerCount, 1);
        await harness.debounce();
        expect(harness.requests.single.snapshot.siteId, _otherSite);
        harness.finish('other');
        await _flush();
        harness.prepared.refreshSite(_site);
        expect(harness.ready('b', 'b'), 'other');
        harness.prepared.cancel('b');
        expect(harness.activeWatches, 0);
        expect(harness.ready('b', 'b'), isNull);
      },
    );

    test(
      'service fallback stays readable at the caller without caching HTML',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', 'source');
        await harness.debounce();
        harness.finish('fallback', failure: CookingFailure.busy);
        await _flush();
        expect(harness.ready('draft', 'source'), isNull);
        final future = harness.cook('send', 'source');
        await _flush();
        harness.finish('fallback', failure: CookingFailure.timeout);
        expect(await future, isNull);
      },
    );

    for (final failure in [
      'context',
      'request',
      'cook',
      'current',
      'watch',
      'stop',
    ]) {
      test(
        '$failure exceptions never escape preparation or teardown',
        () async {
          final harness = _Harness(failure: failure);
          harness.prepare('draft', 'source');
          await harness.debounce();
          if (harness.cooks.isNotEmpty) harness.finish('unusable');
          await _flush();
          if (failure != 'stop') {
            expect(harness.ready('draft', 'source'), isNull);
          }
          harness.prepared.dispose();
          expect(harness.clock.activeTimerCount, 0);
        },
      );
    }

    test(
      'disposal cancels all observers and timers and observes late worker errors',
      () async {
        final harness = _Harness();
        harness.prepare('active', 'active');
        await harness.debounce();
        harness.prepare('queued', 'queued');
        harness.prepared.dispose();
        harness.prepared.dispose();
        expect(harness.activeWatches, 0);
        expect(harness.clock.activeTimerCount, 0);
        harness.cooks.single.completion.completeError(StateError('late'));
        await _flush();
        harness.prepare('later', 'later');
        expect(await harness.cook('later', 'later'), isNull);
        expect(harness.ready('active', 'active'), isNull);
        expect(harness.requests.length, 1);
      },
    );

    test(
      'empty successful HTML is ready and remains distinct from no result',
      () async {
        final harness = _Harness();
        addTearDown(harness.prepared.dispose);
        harness.prepare('draft', '/ignored');
        await harness.debounce();
        harness.finish('');
        await _flush();
        expect(harness.ready('draft', '/ignored'), '');
      },
    );
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Harness {
  _Harness({
    int maxDrafts = 32,
    int maxReadyBytes = 2 * 1024 * 1024,
    int maxSubmissions = 32,
    String? failure,
  }) {
    final host = PluginCookingHost(
      request:
          ({
            required String siteUrl,
            required String raw,
            CookingProfile profile = CookingProfile.post,
            CookingContext context = const CookingContext(),
            CookingCachedMetadata? cachedMetadata,
          }) {
            if (failure == 'request') throw StateError('request');
            final request = CookingRequest(
              raw: raw,
              profile: profile,
              snapshot: CookingSnapshot(
                siteId: siteUrl,
                accountId: '1',
                accountGeneration: generations[siteUrl] ?? 0,
                context: context,
              ),
            );
            requests.add(request);
            return request;
          },
      cook: (request) {
        if (failure == 'cook') return Future.error(StateError('cook'));
        final pending = _Cook(request);
        cooks.add(pending);
        return pending.completion.future;
      },
      isCurrent: (request) {
        if (failure == 'current') throw StateError('current');
        return request.snapshot.accountGeneration ==
            (generations[request.snapshot.siteId] ?? 0);
      },
      watch: ({required siteUrl, required raw, required onChanged}) {
        if (failure == 'watch') throw StateError('watch');
        final watch = _Watch(siteUrl, raw, onChanged);
        watches.add(watch);
        return () {
          watch.active = false;
          if (failure == 'stop') throw StateError('stop');
        };
      },
    );
    prepared = ChatPreparedCooking(
      host: host,
      scheduler: ChatCookingCoordinator(
        cook: host.cook,
        timerFactory: clock.createTimer,
      ),
      contextFor: (_) {
        if (failure == 'context') throw StateError('context');
        contextCalls++;
        return CookingContext(
          locale: locale,
          asOfEpochMilliseconds: contextCalls,
        );
      },
      maxDrafts: maxDrafts,
      maxReadyBytes: maxReadyBytes,
      maxSubmissions: maxSubmissions,
    );
  }

  final clock = ManualScheduler();
  final requests = <CookingRequest>[];
  final cooks = <_Cook>[];
  final watches = <_Watch>[];
  final generations = <String, int>{};
  late final ChatPreparedCooking prepared;
  var locale = 'en';
  var contextCalls = 0;

  int get activeWatches => watches.where((watch) => watch.active).length;

  void prepare(Object key, String raw, {String siteUrl = _site}) =>
      prepared.prepare(key: key, siteUrl: siteUrl, raw: raw);

  String? ready(Object key, String raw) =>
      prepared.takeReady(key: key, raw: raw);

  Future<String?> cook(Object key, String raw, {bool Function()? isCurrent}) =>
      prepared.cook(
        key: key,
        siteUrl: _site,
        raw: raw,
        isCurrent: isCurrent ?? () => true,
      );

  Future<void> debounce() {
    clock.advance(const Duration(milliseconds: 40));
    return _flush();
  }

  void finish(String html, {CookingFailure? failure}) {
    final pending = cooks.firstWhere((job) => !job.completion.isCompleted);
    pending.completion.complete(CookingResult(html: html, failure: failure));
  }

  void notify(String siteUrl) {
    generations.update(siteUrl, (value) => value + 1, ifAbsent: () => 1);
    for (final watch in watches.toList(growable: false)) {
      if (watch.active && watch.siteUrl == siteUrl) watch.onChanged();
    }
  }
}

final class _Watch {
  _Watch(this.siteUrl, this.raw, this.onChanged);
  final String siteUrl, raw;
  final void Function() onChanged;
  bool active = true;
}

final class _Cook {
  _Cook(this.request);
  final CookingRequest request;
  final completion = Completer<CookingResult>();
}
