import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final mobile =
      Platform.environment['COMPOSER_MOBILE'] == '1' ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  final diagnostic = Platform.environment['PROFILE_COMPOSER_WIDGETS'] == '1';
  final iterations = int.parse(
    Platform.environment['COMPOSER_ITERATIONS'] ?? '6',
  );
  final retainedDrafts = int.parse(
    Platform.environment['COMPOSER_RETAINED_DRAFTS'] ?? '0',
  );
  final closeInactive = Platform.environment['COMPOSER_CLOSE_INACTIVE'] == '1';

  testWidgets('profiles topic composer opening scrolling and closing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    if (closeInactive) expect(retainedDrafts, greaterThan(0));
    debugProfileBuildsEnabled = diagnostic;
    debugProfileLayoutsEnabled = diagnostic;
    debugProfilePaintsEnabled = diagnostic;
    addTearDown(() {
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      debugProfilePaintsEnabled = false;
    });
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final shell = ShellController(
      mobileNavigationEnabled: mobile,
      forumTabsEnabled: false,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        categoryList: List.generate(
          250,
          (i) => TopicCategory(
            id: i + 1,
            name: 'Category $i',
            slug: 'cat-$i',
            color: '3188CC',
          ),
        ),
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    final size = mobile ? const Size(390, 844) : const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await binding.setSurfaceSize(size);
    addTearDown(() => binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(
            platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
          ),
          home: const AdaptiveShell(),
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
      final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
      final activation = await Process.run('/usr/bin/open', ['-a', app]);
      expect(activation.exitCode, 0);
    }
    await tester.pumpAndSettle();
    final source = List.generate(
      120,
      (i) =>
          'Paragraph $i with **emphasis** and enough text to wrap across '
          'the composer viewport while scrolling a long topic draft.',
    ).join('\n\n');
    for (var draft = 0; draft < retainedDrafts; draft++) {
      await shell.openNewTopicFromSidebar();
      shell.visibleComposer!.text.text = source;
      await tester.pumpAndSettle();
    }
    final reports = <Map<String, Object?>>[];

    Future<void> measure(
      String phase,
      int iteration,
      Future<void> Function() action,
    ) async {
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      final start = developer.Timeline.now;
      final task = developer.TimelineTask()..start('composer_$phase');
      late final int end;
      try {
        await action();
        end = developer.Timeline.now;
        task.finish();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      } finally {
        binding.removeTimingsCallback(collect);
      }
      frames.removeWhere((frame) {
        final timestamp = frame.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        );
        return timestamp < start || timestamp > end;
      });
      expect(frames, isNotEmpty, reason: phase);
      expect(tester.takeException(), isNull);
      final report = <String, Object?>{
        'phase': phase,
        'iteration': iteration,
        'elapsedMs': (end - start) / 1000,
        'frames': [
          for (final frame in frames)
            {
              'buildMs': frame.buildDuration.inMicroseconds / 1000,
              'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
            },
        ],
      };
      reports.add(report);
      debugPrint('COMPOSER_LIFECYCLE_PROFILE ${jsonEncode(report)}');
    }

    Future<void> run() async {
      for (var iteration = 0; iteration < iterations; iteration++) {
        await measure('opening', iteration, () async {
          await shell.openNewTopicFromSidebar();
          await tester.pumpAndSettle();
          expect(find.byType(ComposerPanel), findsOneWidget);
        });
        final composer = shell.visibleComposer!;
        composer.title.text = 'Composer performance fixture';
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        composer.focus.unfocus();
        await tester.pumpAndSettle();
        final scroll = mobile
            ? tester
                  .widget<CustomScrollView>(
                    find.byKey(const ValueKey('composer-mobile-scroll')),
                  )
                  .controller!
            : composer.text.imageScrollController!;
        expect(scroll.position.maxScrollExtent, greaterThan(1800));
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        await measure('scrolling', iteration, () async {
          await scroll.animateTo(
            1900,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
          await scroll.animateTo(
            100,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
          expect(scroll.offset, closeTo(100, .1));
          expect(composer.raw, source);
        });
        await measure('closing', iteration, () async {
          final closingComposer = closeInactive
              ? shell.liveComposers.first
              : composer;
          final closing = shell.saveComposerAndClose(
            closingComposer,
            afterHide: () => binding.endOfFrame,
          );
          await tester.pumpAndSettle();
          expect(await closing, isA<ComposerClosed>());
          await tester.pumpAndSettle();
          expect(shell.liveComposers, isNot(contains(closingComposer)));
          if (closeInactive) expect(shell.visibleComposer, same(composer));
          if (retainedDrafts == 0) {
            expect(shell.visibleComposer, isNull);
            expect(find.byType(ComposerPanel), findsNothing);
          }
        });
      }
    }

    if (diagnostic) {
      await binding.traceAction(run, reportKey: 'composerTimeline');
    } else {
      await run();
    }
    binding.reportData ??= {};
    binding.reportData!['composerLifecycle'] = {
      'label': Platform.environment['PROFILE_LABEL'] ?? 'current',
      'mobile': mobile,
      'debug': kDebugMode,
      'instrumented': diagnostic,
      'retainedDrafts': retainedDrafts,
      'closeInactive': closeInactive,
      'hostPlatform': defaultTargetPlatform.name,
      'width': size.width,
      'height': size.height,
      'reports': reports,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
