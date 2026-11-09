import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/users_directory_fixture.dart';

const _latency = Duration(milliseconds: 120);
const _scrollFrames = 90;
const _scrollStep = 20.0;
const _keystrokes = ['m', 'me', 'mem', 'memb', 'membe', 'member'];

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
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profile the Users route', (tester) async {
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

    final desktop =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    final view = tester.view;
    final logical = view.physicalSize / view.devicePixelRatio;
    int? landedAt;
    final fixture = await pumpUsersDirectoryFixture(
      tester,
      size: logical,
      platform: defaultTargetPlatform,
      devicePixelRatio: view.devicePixelRatio,
      beforeRead: (path) async {
        await Future<void>.delayed(_latency);
        if (path.startsWith('/directory_items')) landedAt = Timeline.now;
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

    Future<void> waitForLanding(int? previous) async {
      final timeout = Stopwatch()..start();
      while (landedAt == previous && timeout.elapsed.inSeconds < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      expect(landedAt, isNot(previous));
    }

    Future<void> waitForTable() async {
      final timeout = Stopwatch()..start();
      while (find.byType(DDataTable<UserDirectoryItem>).evaluate().isEmpty &&
          timeout.elapsed.inSeconds < 5) {
        await binding.endOfFrame;
      }
    }

    ScrollPosition position(int axisIndex) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(DDataTable<UserDirectoryItem>),
                matching: find.byType(Scrollable),
              )
              .at(axisIndex),
        )
        .position;

    void type(String text) => tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byKey(const ValueKey('users-search')),
            matching: find.byType(EditableText),
          ),
        )
        .updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );

    Future<void> phase(String name, Future<void> Function() body) async {
      final startedAt = Timeline.now;
      await body();
      phases.add(_Phase(name, startedAt, Timeline.now));
    }

    try {
      final tab = fixture.shell.focusedTabContext;
      await hold(const Duration(milliseconds: 600));
      await waitForTable();
      final periods = [
        for (final period in UserDirectoryPeriod.values)
          if (period != const UserDirectoryQuery().period) period,
      ];
      for (final (cycle, period) in periods.indexed) {
        final before = landedAt;
        final startedAt = Timeline.now;
        tab.setUsersPeriod(period);
        await waitForLanding(before);
        await hold(const Duration(milliseconds: 300));
        phases.add(_Phase('arrive', startedAt, Timeline.now));
        await waitForTable();
        await hold(const Duration(milliseconds: 300));

        await phase('unrelated-notifications', () async {
          for (var i = 0; i < 6; i++) {
            fixture.shell.search.setPageWords(
              usersDirectorySite,
              tab.tabId,
              'other',
              'word$i',
            );
            await binding.endOfFrame;
            await hold(const Duration(milliseconds: 60));
          }
        });

        await phase('keystrokes', () async {
          for (final text in _keystrokes) {
            type(text);
            await binding.endOfFrame;
            await hold(const Duration(milliseconds: 90));
          }
        });
        final beforeSearch = landedAt;
        final searchedAt = Timeline.now;
        await waitForLanding(beforeSearch);
        await hold(const Duration(milliseconds: 300));
        phases.add(_Phase('search-lands', searchedAt, Timeline.now));
        await waitForTable();
        type('');
        await hold(const Duration(milliseconds: 500));
        await waitForTable();
        await hold(const Duration(milliseconds: 200));

        final vertical = position(1);
        await phase('scroll', () async {
          for (var frame = 0; frame < _scrollFrames; frame++) {
            vertical.jumpTo(
              math.min(vertical.pixels + _scrollStep, vertical.maxScrollExtent),
            );
            await binding.endOfFrame;
          }
        });
        final beforePage = landedAt;
        final pageStarted = Timeline.now;
        vertical.jumpTo(vertical.maxScrollExtent);
        await waitForLanding(beforePage);
        await hold(const Duration(milliseconds: 300));
        phases.add(_Phase('page-lands', pageStarted, Timeline.now));

        final horizontal = position(0);
        await phase('horizontal-scroll', () async {
          for (var frame = 0; frame < 40; frame++) {
            horizontal.jumpTo(
              math.min(horizontal.pixels + 16, horizontal.maxScrollExtent),
            );
            await binding.endOfFrame;
          }
        });
        horizontal.jumpTo(0);
        await hold(const Duration(milliseconds: 200));

        final state = tester.widget<UsersPage>(find.byType(UsersPage)).data;
        expect(state.items.length, greaterThan(usersDirectoryPageSize));
        work.add({
          'cycle': cycle,
          'period': period.name,
          'loadedRows': state.items.length,
        });
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
    binding.reportData = {
      'usersRoute': {
        'profile': kProfileMode,
        'desktop': desktop,
        'width': logical.width,
        'refreshRate': tester.view.display.refreshRate,
        'budgetMs': budgetMs,
        'work': work,
        'reads': fixture.api.reads.length,
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
                    (f) => f.buildDuration.inMicroseconds / 1000 > budgetMs,
                  )
                  .length,
            },
        },
      },
    };
  });
}
