import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/user_card_activity_fixture.dart';

const _cycles = 8;
const _pageLatency = Duration(milliseconds: 250);
const _scrollFrames = 90;
const _scrollStep = 20.0;

class _Phase {
  _Phase(this.name, this.startUs, this.endUs);
  final String name;
  final int startUs;
  final int endUs;
}

Map<String, num> _summary(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return {'count': 0};
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'count': sorted.length,
    'median': at(.5),
    'p90': at(.9),
    'max': sorted.last,
    'sum': sorted.fold<double>(0, (sum, value) => sum + value),
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profile the phone user card and its activity', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }

    int? pageLandedAt;
    final people = [for (var i = 0; i < _cycles; i++) 'person$i'];
    final fixture = await pumpUserCardActivityFixture(
      tester,
      people: people,
      beforePage: () async {
        await Future<void>.delayed(_pageLatency);
        pageLandedAt = Timeline.now;
      },
    );
    final frames = <ui.FrameTiming>[];
    final phases = <_Phase>[];
    final work = <Map<String, Object>>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);

    Future<void> hold(Duration duration) async {
      final clock = Stopwatch()..start();
      while (clock.elapsed < duration) {
        await binding.endOfFrame;
      }
    }

    Future<void> waitForPage(int? previous) async {
      final timeout = Stopwatch()..start();
      while (pageLandedAt == previous && timeout.elapsed.inSeconds < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      expect(pageLandedAt, isNot(previous));
    }

    try {
      final context = tester.element(find.text('Open card'));
      for (final person in people) {
        final openedAt = Timeline.now;
        final beforeOpen = pageLandedAt;
        unawaited(
          showUserCard(
            context: context,
            username: person,
            siteUrl: userCardActivitySite,
          ),
        );
        await waitForPage(beforeOpen);
        final feedAt = pageLandedAt!;
        phases.add(_Phase('open', openedAt, feedAt));
        await hold(const Duration(milliseconds: 250));
        phases.add(_Phase('feed', feedAt, Timeline.now));
        await hold(const Duration(milliseconds: 1400));

        final risingAt = Timeline.now;
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(0, -24));
        await binding.endOfFrame;
        final clock = Stopwatch()..start();
        var travelled = 0.0;
        while (clock.elapsedMilliseconds < 500) {
          final next =
              700.0 * (clock.elapsedMicroseconds / 500000).clamp(0.0, 1.0);
          await gesture.moveBy(
            Offset(0, travelled - next),
            timeStamp: clock.elapsed,
          );
          travelled = next;
          await binding.endOfFrame;
        }
        await gesture.up(timeStamp: clock.elapsed);
        await hold(const Duration(milliseconds: 500));
        phases.add(_Phase('rise', risingAt, Timeline.now));

        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('user-card-surface')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        expect(position.extentAfter, greaterThan(0));

        Future<int> scroll(String name) async {
          final startedAt = Timeline.now;
          final from = position.pixels;
          var moved = 0;
          for (var frame = 0; frame < _scrollFrames; frame++) {
            position.jumpTo(position.pixels + _scrollStep);
            await binding.endOfFrame;
            moved++;
          }
          phases.add(_Phase(name, startedAt, Timeline.now));
          expect(position.pixels, greaterThan(from));
          return moved;
        }

        final shallow = await scroll('scroll');
        final beforePage = pageLandedAt;
        while (pageLandedAt == beforePage) {
          position.jumpTo(position.maxScrollExtent);
          await binding.endOfFrame;
        }
        final pageAt = pageLandedAt!;
        await hold(const Duration(milliseconds: 250));
        phases.add(_Phase('page', pageAt, Timeline.now));
        await hold(const Duration(milliseconds: 200));
        final deep = await scroll('scroll-after-page');

        final beforeReadingPage = pageLandedAt;
        while (pageLandedAt == beforeReadingPage) {
          position.jumpTo(position.pixels + _scrollStep);
          await binding.endOfFrame;
        }
        final readingPageAt = pageLandedAt!;
        final landedClock = Stopwatch()..start();
        while (landedClock.elapsedMilliseconds < 250) {
          position.jumpTo(position.pixels + _scrollStep);
          await binding.endOfFrame;
        }
        phases.add(_Phase('page-while-scrolling', readingPageAt, Timeline.now));

        final loaded = fixture.shell.accountActivity
            .userActivityFor(userCardActivitySite, username: person)
            .items
            .length;
        expect(loaded, greaterThan(30));
        work.add({
          'person': person,
          'loadedRows': loaded,
          'mountedRows': find.byType(UserActivityRow).evaluate().length,
          'scrollFrames': shallow + deep,
          'finalOffset': position.pixels,
        });

        Navigator.of(
          tester.element(find.byKey(const ValueKey('user-card-surface'))),
          rootNavigator: true,
        ).pop();
        await hold(const Duration(milliseconds: 900));
        expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await hold(const Duration(seconds: 1));
    } finally {
      binding.removeTimingsCallback(collect);
    }

    final byPhase = <String, List<ui.FrameTiming>>{};
    final peaks = <String, List<double>>{};
    for (final phase in phases) {
      final timings = [
        for (final frame in frames)
          if (frame.timestampInMicroseconds(ui.FramePhase.buildStart)
              case final start
              when start >= phase.startUs && start < phase.endUs)
            frame,
      ];
      byPhase.putIfAbsent(phase.name, () => []).addAll(timings);
      peaks
          .putIfAbsent(phase.name, () => [])
          .add(
            timings.fold<double>(
              0,
              (peak, frame) =>
                  math.max(peak, frame.buildDuration.inMicroseconds / 1000),
            ),
          );
    }
    final budgetMs = 1000 / tester.view.display.refreshRate;
    final report = {
      'debug': kDebugMode,
      'profile': kProfileMode,
      'refreshRate': tester.view.display.refreshRate,
      'budgetMs': budgetMs,
      'cycles': _cycles,
      'work': work,
      'phases': {
        for (final MapEntry(key: name, value: timings) in byPhase.entries)
          name: {
            'peakBuildMsPerCycle': peaks[name],
            'buildMs': _summary(
              timings.map((f) => f.buildDuration.inMicroseconds / 1000),
            ),
            'rasterMs': _summary(
              timings.map((f) => f.rasterDuration.inMicroseconds / 1000),
            ),
            'overBudget': timings
                .where(
                  (f) =>
                      f.buildDuration.inMicroseconds / 1000 > budgetMs ||
                      f.rasterDuration.inMicroseconds / 1000 > budgetMs,
                )
                .length,
          },
      },
    };
    binding.reportData = {'userCardActivity': report};
    debugPrint('USER_CARD_ACTIVITY ${jsonEncode(report)}', wrapWidth: 4096);
    expect(work, hasLength(_cycles));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
