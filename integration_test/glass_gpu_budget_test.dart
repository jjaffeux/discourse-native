import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' as fixture;
import '../test/support/chat_shell.dart';
import '../test/support/fakes.dart';
import '../test/support/topic_post_list.dart';

// Each scenario holds one screen for a fixed wall-clock window. Requested
// frames per second separate work that should not exist from work that is
// merely expensive; raster time is the GPU share of each drawn frame. Glass
// off is the same shell under high contrast, which resolves every Native
// surface to its opaque fill.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile glass GPU budget', (tester) async {
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
    final nativeSize = tester.view.physicalSize;
    final nativePixelRatio = tester.view.devicePixelRatio;
    final shell = await fixture.pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 100; id++)
          Topic(
            id: id,
            title: 'Topic $id with a longer title that wraps on mobile',
            slug: 'topic-$id',
          ),
      ],
      topic: topicPayload(
        id: 7,
        title: 'A long discussion',
        canCreatePost: true,
        posts: [
          for (var id = 1; id <= 80; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'reader',
              cooked:
                  '<p>Post $id discusses reading and navigation with a '
                  'paragraph long enough to wrap across the phone.</p>',
            ),
        ],
      ),
      conversations: const ChatChannels(
        public: [
          ChatChannel(
            id: 10,
            title: 'General',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
          ),
        ],
        direct: [],
      ),
      chatMessages: [
        for (var id = 1; id <= 120; id++)
          ChatMessage(
            id: id,
            channelId: 10,
            cooked:
                '<p>Message $id with <strong>formatted text</strong> and a '
                'longer paragraph that wraps across the phone.</p>',
            author: ChatMessageAuthor(id: id % 2 + 1, username: 'reader'),
            createdAt: DateTime(2026, 10, 1).add(Duration(hours: id * 3)),
          ),
      ],
    );
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativePixelRatio;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();

    Future<void> sweep(Finder list, double distance) async {
      final scrollable = find
          .descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (final delta in [-distance, distance]) {
        final origin = tester.getCenter(scrollable);
        final drag = position.drag(
          DragStartDetails(globalPosition: origin),
          () {},
        );
        final elapsed = Stopwatch()..start();
        var travelled = 0.0;
        while (elapsed.elapsed < const Duration(milliseconds: 1500)) {
          final next =
              delta * (elapsed.elapsedMicroseconds / 1500000).clamp(0.0, 1.0);
          final movement = next - travelled;
          travelled = next;
          drag.update(
            DragUpdateDetails(
              globalPosition: origin + Offset(0, travelled),
              delta: Offset(0, movement),
              primaryDelta: movement,
            ),
          );
          await binding.endOfFrame;
        }
        drag.end(DragEndDetails(primaryVelocity: 0));
      }
    }

    Future<void> hold() =>
        Future<void>.delayed(const Duration(milliseconds: 3000));

    // The live test binding schedules another engine frame after every frame
    // it did not pump, so one caret blink keeps an idle screen drawing until
    // the next pump. A frame the app requested starts with hasScheduledFrame
    // set; those are the frames WidgetsFlutterBinding would draw.
    var requests = 0;
    final dispatcher = binding.platformDispatcher;
    final beginFrame = dispatcher.onBeginFrame;
    dispatcher.onBeginFrame = (timeStamp) {
      if (binding.hasScheduledFrame) requests++;
      beginFrame?.call(timeStamp);
    };
    addTearDown(() => dispatcher.onBeginFrame = beginFrame);

    final reports = <Map<String, Object>>[];
    Future<void> record(String scenario, Future<void> Function() work) async {
      final glass = DMaterialTheme.glassOf(
        tester.element(find.byType(DMobileDock)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      final requestsBefore = requests;
      final wallStart = DateTime.now();
      final startUs = Timeline.now;
      final elapsed = Stopwatch()..start();
      late final int endUs;
      late final int requested;
      late final DateTime wallEnd;
      try {
        await work();
        endUs = Timeline.now;
        requested = requests - requestsBefore;
        wallEnd = DateTime.now();
        elapsed.stop();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } finally {
        binding.removeTimingsCallback(collect);
      }
      frames.removeWhere((f) {
        final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
        return t < startUs || t > endUs;
      });
      Map<String, Object> summary(Duration Function(ui.FrameTiming) duration) {
        if (frames.isEmpty) return const {};
        final values =
            frames.map((f) => duration(f).inMicroseconds / 1000).toList()
              ..sort();
        return {
          'meanMs': values.reduce((a, b) => a + b) / values.length,
          'p50Ms': values[(values.length * .5).floor()],
          'p95Ms': values[(values.length * .95).floor()],
          'over8ms': values.where((v) => v > 8.333).length,
        };
      }

      final seconds = elapsed.elapsedMicroseconds / 1e6;
      final raster = frames.fold<int>(
        0,
        (sum, f) => sum + f.rasterDuration.inMicroseconds,
      );
      final report = <String, Object>{
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'scenario': scenario,
        'glass': glass,
        'debug': kDebugMode,
        'refreshRate': tester.view.display.refreshRate,
        'seconds': seconds,
        // Device wall clock, to align the window with an Instruments trace.
        'wallStartUs': wallStart.microsecondsSinceEpoch,
        'wallEndUs': wallEnd.microsecondsSinceEpoch,
        'requestedFps': requested / seconds,
        'frames': frames.length,
        'fps': frames.length / seconds,
        // Raster milliseconds spent per wall-clock second: the sustained GPU
        // thread load, which is what heats the device.
        'rasterMsPerSecond': raster / 1000 / seconds,
        'build': summary((f) => f.buildDuration),
        'raster': summary((f) => f.rasterDuration),
      };
      debugPrint('GLASS_GPU_PROFILE ${jsonEncode(report)}', wrapWidth: 4096);
      reports.add(report);
    }

    for (final glass in [true, false]) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(highContrast: !glass);
      shell.selectMobilePanel('topics');
      await tester.pumpAndSettle();
      final topics = find.byType(TopicListView);
      expect(topics, findsOneWidget);
      await record('topics-idle', hold);
      await record('topics-scroll', () => sweep(topics, 2400));

      shell.openTopic(
        const Topic(id: 7, title: 'A long discussion', slug: 'topic-7'),
      );
      await tester.pumpAndSettle();
      await record('reader-scroll', () => sweep(topicPostListFinder(), 2400));
      shell.selectMobilePanel('topics');
      await tester.pumpAndSettle();

      await shell.openChat();
      shell.openChatChannel(10);
      await tester.pumpAndSettle();
      final stream = find.byType(ChatMessageStream);
      expect(stream, findsOneWidget);
      final editable = find.byType(EditableText);
      await tester.showKeyboard(editable.first);
      await tester.pump();
      await record('chat-focused-idle', hold);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await record('chat-unfocused-idle', hold);
      await record('chat-scroll', () => sweep(stream, 2400));
      shell.selectMobilePanel('topics');
      await tester.pumpAndSettle();
    }
    binding.reportData = {'profiles': reports};
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
