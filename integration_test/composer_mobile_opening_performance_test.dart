import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
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
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('profiles mobile topic composer opening and keyboard layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profileWidgets = bool.fromEnvironment('PROFILE_COMPOSER_WIDGETS');
    debugProfileBuildsEnabled = profileWidgets;
    debugProfileLayoutsEnabled = profileWidgets;
    addTearDown(() {
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      SurfaceOpeningTrace.observer = null;
      tester.view.resetViewInsets();
    });
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    const notifications = MethodChannel(
      'org.discourse.native/notification_opens',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      notifications,
      (_) async => null,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        notifications,
        null,
      ),
    );
    const site = 'https://meta.discourse.org';
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final categories = List.generate(
      250,
      (index) => TopicCategory(
        id: index + 1,
        name: 'Category $index',
        slug: 'category-$index',
        color: '3188CC',
      ),
    );
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: user),
        ]),
        api: FakeDiscourseApi(
          user: user,
          categoryList: categories,
          composerCapabilities: const TopicComposerCapabilities(
            canTagTopics: true,
          ),
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
        ),
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(find.byType(AdaptiveShell)));
    final reports = <Map<String, Object?>>[];
    for (var iteration = 0; iteration < 6; iteration++) {
      final frames = <ui.FrameTiming>[];
      final marks = <String, double>{};
      final start = Timeline.now;
      var builds = 0;
      SurfaceOpeningTrace.observer = (name, timestamp) {
        if (name == 'composer.build') builds++;
        marks.putIfAbsent(name, () => (timestamp - start) / 1000);
      };
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      final pixelRatio = tester.view.devicePixelRatio;
      late final int opened;
      late final int end;
      try {
        final opening = shell.openNewTopicFromSidebar();
        await tester.pump();
        await tester.pump();
        await opening;
        await tester.pumpAndSettle();
        expect(find.byType(ComposerPanel), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-category')), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-tags')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('composer-toolbar-scroll')),
          findsOneWidget,
        );
        opened = Timeline.now;
        for (final inset in [80.0, 160.0, 240.0, 320.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset * pixelRatio);
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        end = Timeline.now;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      } finally {
        binding.removeTimingsCallback(collect);
        SurfaceOpeningTrace.observer = null;
      }
      frames.removeWhere((frame) {
        final timestamp = frame.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        );
        return timestamp < start || timestamp > end;
      });
      expect(frames, isNotEmpty);
      expect(builds, 1);
      final report = <String, Object?>{
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'iteration': iteration,
        'debug': kDebugMode,
        'instrumented': profileWidgets,
        'platform': defaultTargetPlatform.name,
        'material': DMaterialTheme.of(
          tester.element(find.byType(ComposerPanel)),
        )?.material.name,
        'width': tester.view.physicalSize.width / pixelRatio,
        'height': tester.view.physicalSize.height / pixelRatio,
        'pixelRatio': pixelRatio,
        'startUs': start,
        'openedUs': opened,
        'endUs': end,
        'openingMs': (opened - start) / 1000,
        'composerBuilds': builds,
        'marksMs': marks,
        'frames': [
          for (final frame in frames)
            {
              'phase':
                  frame.timestampInMicroseconds(ui.FramePhase.buildStart) <
                      opened
                  ? 'opening'
                  : 'keyboard',
              'buildMs': frame.buildDuration.inMicroseconds / 1000,
              'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
            },
        ],
      };
      reports.add(report);
      debugPrint('COMPOSER_MOBILE_PROFILE ${jsonEncode(report)}');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      shell.closeComposer();
      await tester.pumpAndSettle();
    }
    binding.reportData = {'composerMobileOpening': reports};
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
