import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profiles mobile composer scrolling with and without keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final shell = ShellController(
      mobileNavigationEnabled: true,
      forumTabsEnabled: false,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    final keyboard = ValueNotifier(0.0);
    addTearDown(shell.dispose);
    addTearDown(keyboard.dispose);
    await shell.load();
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: keyboard,
            builder: (context, inset, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: child!,
            ),
          ),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await shell.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    final composer = shell.visibleComposer!;
    composer.title.text = 'Composer scrolling benchmark';
    composer.text.value = TextEditingValue(
      text: List.generate(
        120,
        (i) =>
            'Paragraph $i: A draft with enough text to scroll behind both '
            'floating controls and the keyboard.',
      ).join('\n\n'),
      selection: const TextSelection.collapsed(offset: 0),
    );
    composer.focus.unfocus();
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(seconds: 3));
    final scroll = tester
        .widget<CustomScrollView>(
          find.byKey(const ValueKey('composer-mobile-scroll')),
        )
        .controller!;

    Future<void> sweep() async {
      await scroll.animateTo(
        1900,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
      await scroll.animateTo(
        100,
        duration: const Duration(seconds: 2),
        curve: Curves.linear,
      );
    }

    for (final inset in [0.0, 336.0]) {
      keyboard.value = inset;
      await tester.pumpAndSettle();
      scroll.jumpTo(100);
      // Warm font, layout, and rendering caches before recording.
      await sweep();
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      final startUs = Timeline.now;
      final elapsed = Stopwatch()..start();
      binding.addTimingsCallback(collect);
      late final int endUs;
      try {
        for (var repeat = 0; repeat < 3; repeat++) {
          await sweep();
        }
        endUs = Timeline.now;
        elapsed.stop();
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        binding.removeTimingsCallback(collect);
      }
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 18)),
        reason: 'Discard captures interrupted by sleep or a paused simulator.',
      );
      frames.removeWhere((frame) {
        final start = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
        return start < startUs || start > endUs;
      });
      expect(frames.length, greaterThan(100));
      Map<String, Object> summary(Duration Function(ui.FrameTiming) duration) {
        final values =
            frames.map((f) => duration(f).inMicroseconds / 1000).toList()
              ..sort();
        return {
          'meanMs': values.reduce((a, b) => a + b) / values.length,
          'p50Ms': values[(values.length * .5).floor()],
          'p95Ms': values[(values.length * .95).floor()],
          'p99Ms': values[(values.length * .99).floor()],
          'over16ms': values.where((value) => value > 16.667).length,
          'over8ms': values.where((value) => value > 8.333).length,
        };
      }

      final report = {
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'keyboardInset': inset,
        'debug': kDebugMode,
        'impeller': ui.ImageFilter.isShaderFilterSupported,
        'pixelRatio': tester.view.devicePixelRatio,
        if (kDebugMode)
          'backdropLayers': tester.layers
              .whereType<BackdropFilterLayer>()
              .length,
        'frames': frames.length,
        'build': summary((frame) => frame.buildDuration),
        'raster': summary((frame) => frame.rasterDuration),
        'total': summary((frame) => frame.totalSpan),
      };
      debugPrint(
        'COMPOSER_SCROLL_PROFILE ${jsonEncode(report)}',
        wrapWidth: 2048,
      );
      binding.reportData ??= {};
      binding.reportData!['keyboard_$inset'] = report;
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
