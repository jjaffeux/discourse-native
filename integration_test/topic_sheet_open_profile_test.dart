import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' show pumpMobileShellFixture;
import '../test/support/fakes.dart';

const _topicIds = [2, 3, 4];

String _title(int id) => 'Discussion $id about scrolling';

TopicPayload _richTopic(int id) => topicPayload(
  id: id,
  title: _title(id),
  canCreatePost: true,
  posts: [
    for (var number = 1; number <= 40; number++)
      Post(
        id: id * 1000 + number,
        postNumber: number,
        username: number.isEven ? 'reader' : 'writer',
        createdAt: DateTime.utc(2026, 10, 1, 0, number),
        cooked:
            '<p>Reply $number: reading a rich discussion in a sheet.</p>'
            '<blockquote><p>A previous reply with <strong>formatted '
            'text</strong>.</p></blockquote>'
            '<p>The reader handles <code>input</code>, <em>emphasis</em>, '
            'and an <a href="https://example.com/">ordinary link</a>.</p>'
            '<ul><li>First point</li><li>Second point</li></ul>',
      ),
  ],
);

/// Opens topics from the phone list, puts them away again, and opens the
/// topic actions sheet, so the first of each can be compared with repeats.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile first and repeated topic sheet opening', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      debugProfilePaintsEnabled = false;
    });
    // Bundled fonts load on first use, as in the app, so the first open
    // keeps what it costs the first time.
    final nativeSize = tester.view.physicalSize;
    final nativeRatio = tester.view.devicePixelRatio;
    final shell = await pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(id: id, title: _title(id), slug: 'topic-$id', postsCount: 40),
      ],
      topic: _richTopic(7),
      onApi: (api) {
        for (final id in _topicIds) {
          api.topics[id] = _richTopic(id);
        }
      },
    );
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 1));

    final frames = <ui.FrameTiming>[];
    final samples = <Map<String, Object?>>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);

    Future<void> measure(
      String action,
      int repeat,
      Future<void> Function() act, {
      int? topicId,
    }) async {
      final task = TimelineTask()..start('$action-$repeat');
      final startUs = Timeline.now;
      await act();
      final actedUs = Timeline.now;
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final endUs = Timeline.now;
      task.finish();
      expect(tester.takeException(), isNull);
      samples.add({
        'action': action,
        'repeat': repeat,
        'topicId': ?topicId,
        'startUs': startUs,
        'actedUs': actedUs,
        'endUs': endUs,
        'elapsedMs': (endUs - startUs) / 1000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    final handle = find.byKey(const ValueKey('sheet-drag-handle'));

    final tapped = <bool>[];
    final swiped = <bool>[];
    Future<void> openTopic(int repeat, int id) => measure(
      'open',
      repeat,
      () async {
        final row = find.text(_title(id));
        final visible = row.evaluate().length == 1;
        tapped.add(visible);
        if (visible) {
          await tester.tap(row);
        } else {
          shell.openTopic(Topic(id: id, title: _title(id), slug: 'topic-$id'));
        }
        await binding.endOfFrame;
      },
      topicId: id,
    );

    Future<void> swipeDown() async {
      final origin = tester.getCenter(handle);
      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(const Offset(0, 24));
      await binding.endOfFrame;
      final clock = Stopwatch()..start();
      var travelled = 0.0;
      while (clock.elapsedMilliseconds < 240) {
        final next =
            320.0 * (clock.elapsedMicroseconds / 240000).clamp(0.0, 1.0);
        await gesture.moveBy(
          Offset(0, next - travelled),
          timeStamp: clock.elapsed,
        );
        travelled = next;
        await binding.endOfFrame;
      }
      await gesture.up(timeStamp: clock.elapsed);
    }

    Future<void> cycles() async {
      for (var repeat = 0; repeat < 6; repeat++) {
        final id = _topicIds[repeat % _topicIds.length];
        await openTopic(repeat, id);
        expect(handle, findsOneWidget);
        await measure('back', repeat, () async {
          shell.handleBack();
          await binding.endOfFrame;
        }, topicId: id);
        expect(handle, findsNothing);
      }
      await openTopic(6, 7);
      final more = find.byKey(const ValueKey('topic-more-actions'));
      for (var repeat = 0; repeat < 5; repeat++) {
        expect(more, findsOneWidget);
        await measure('menu-open', repeat, () async {
          await tester.tap(more);
          await binding.endOfFrame;
        });
        await measure('menu-close', repeat, () async {
          await tester.binding.handlePopRoute();
          await binding.endOfFrame;
        });
      }
      for (var repeat = 0; repeat < 4; repeat++) {
        final id = repeat == 0 ? 7 : _topicIds[repeat % _topicIds.length];
        if (repeat > 0) await openTopic(6 + repeat, id);
        await measure('swipe', repeat, swipeDown, topicId: id);
        swiped.add(handle.evaluate().isEmpty);
        if (handle.evaluate().isNotEmpty) {
          shell.handleBack();
          await tester.pumpAndSettle();
        }
        expect(handle, findsNothing);
      }
    }

    const trace = bool.fromEnvironment('PROFILE_TIMELINE');
    const widgets = bool.fromEnvironment('PROFILE_WIDGETS');
    debugProfileBuildsEnabled = widgets;
    debugProfileLayoutsEnabled = widgets;
    debugProfilePaintsEnabled = widgets;
    try {
      binding.reportData ??= {};
      if (trace) {
        await binding.traceAction(
          cycles,
          streams: const ['Dart', 'Embedder', 'GC'],
          reportKey: 'topic_sheet_timeline',
        );
      } else {
        await cycles();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    } finally {
      binding.removeTimingsCallback(collect);
    }
    binding.reportData!['topic_sheet_frames'] = {
      'debug': kDebugMode,
      'profile': kProfileMode,
      'trace': trace,
      'widgets': widgets,
      'physicalSize': [nativeSize.width, nativeSize.height],
      'pixelRatio': nativeRatio,
      'refreshRate': tester.view.display.refreshRate,
      'samples': samples,
      'tapped': tapped,
      'swiped': swiped,
      'frames': [
        for (final frame in frames)
          {
            'vsyncUs': frame.timestampInMicroseconds(ui.FramePhase.vsyncStart),
            'startUs': frame.timestampInMicroseconds(ui.FramePhase.buildStart),
            'rasterEndUs': frame.timestampInMicroseconds(
              ui.FramePhase.rasterFinish,
            ),
            'buildMs': frame.buildDuration.inMicroseconds / 1000,
            'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
            'totalMs': frame.totalSpan.inMicroseconds / 1000,
          },
      ],
    };
    debugPrint('TOPIC_SHEET_SAMPLES ${jsonEncode(samples)}', wrapWidth: 4096);
    expect(samples, hasLength(30));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
