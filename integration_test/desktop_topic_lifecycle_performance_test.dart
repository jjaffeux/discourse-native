import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/shell_test_harness.dart';
import '../test/support/tab_switch_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile desktop topic opening and closing', (tester) async {
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
    final shell = await pumpTabSwitchFixture(tester);
    shell.closeTab('reader-a');
    shell.closeTab('list-b');
    shell.selectTab('list-a');
    await tester.pumpAndSettle();
    final reader = find.byWidgetPredicate(
      (widget) => widget is TopicView && widget.route?.topicId == 1,
    );
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(collect);
    final windows = <({String action, int start, int end})>[];
    for (var round = 0; round < 8; round++) {
      var start = Timeline.now;
      await tester.tap(
        topicListTitle('Discussion 1 about fast navigation and reading'),
      );
      await tester.pumpAndSettle();
      var end = Timeline.now;
      expect(reader, findsOneWidget);
      expect(shell.currentPostIds, hasLength(60));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('Reply 1 with'),
        ),
        findsWidgets,
      );
      if (round > 0) windows.add((action: 'open', start: start, end: end));
      start = Timeline.now;
      await tester.tap(
        find.descendant(
          of: reader,
          matching: find.byKey(const ValueKey('topic-close-reader')),
        ),
      );
      await tester.pumpAndSettle();
      end = Timeline.now;
      expect(shell.currentContent?.isTopicList, isTrue);
      expect(reader, findsNothing);
      expect(tester.takeException(), isNull);
      if (round > 0) windows.add((action: 'close', start: start, end: end));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    binding.removeTimingsCallback(collect);
    final reports = [
      for (final window in windows)
        {
          'action': window.action,
          'frames': [
            for (final frame in frames)
              if (frame.timestampInMicroseconds(ui.FramePhase.buildStart) >=
                      window.start &&
                  frame.timestampInMicroseconds(ui.FramePhase.buildStart) <=
                      window.end)
                {
                  'buildUs': frame.buildDuration.inMicroseconds,
                  'rasterUs': frame.rasterDuration.inMicroseconds,
                },
          ],
        },
    ];
    expect(
      reports.every((report) => (report['frames']! as List).isNotEmpty),
      isTrue,
    );
    final report = {
      'label': const String.fromEnvironment(
        'PROFILE_LABEL',
        defaultValue: 'current',
      ),
      'cycles': reports,
      'errors': 0,
    };
    binding.reportData = report;
    debugPrint('DESKTOP_TOPIC_FRAMES ${jsonEncode(report)}');
  });
}
