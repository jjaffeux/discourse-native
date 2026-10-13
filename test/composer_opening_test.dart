import 'dart:convert';

import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main({bool profile = false}) {
  testWidgets(
    'opening and closing the composer retains reader panels and builds the editor once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('org.discourse.native/notification_opens');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
      final shell = ShellController(
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
      addTearDown(shell.dispose);
      await shell.load();
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.topicPanelsVisible, isTrue);

      // The paint boundary must stay the panel's parent across the split
      // breakpoint. Moving its GlobalKey under a different parent would
      // deactivate the entire document and invalidate inherited dependencies.
      Element boundaryFor(String name) {
        final panel = tester.element(
          find.byKey(ValueKey('desktop-panel-$name'), skipOffstage: false),
        );
        Element? boundary;
        panel.visitAncestorElements((element) {
          if (element.widget is RepaintBoundary) {
            boundary = element;
            return false;
          }
          return true;
        });
        return boundary!;
      }

      final boundaries = {
        for (final name in ['main', 'secondary']) name: boundaryFor(name),
      };
      addTearDown(() => SurfaceOpeningTrace.observer = null);
      for (var iteration = 0; iteration < 3; iteration++) {
        final elapsed = Stopwatch()..start();
        final marks = <String, double>{};
        var builds = 0;
        SurfaceOpeningTrace.observer = (name, _) {
          if (name == 'composer.build') builds++;
          marks.putIfAbsent(name, () => elapsed.elapsedMicroseconds / 1000);
        };
        final opening = shell.openNewTopicFromSidebar();
        await tester.pump();
        await tester.pump();
        await opening;
        await tester.pumpAndSettle();
        expect(find.byType(ComposerPanel), findsOneWidget);
        expect(shell.topicPanelsVisible, isFalse);
        expect(shell.visibleComposer!.focus.hasPrimaryFocus, isTrue);
        expect(
          builds,
          1,
          reason: 'Initial focus must not rebuild the entire composer.',
        );
        for (final entry in boundaries.entries) {
          expect(boundaryFor(entry.key), same(entry.value));
        }
        if (profile) {
          debugPrint(
            'COMPOSER_OPENING_PROFILE ${jsonEncode({'label': const String.fromEnvironment('PROFILE_LABEL', defaultValue: 'current'), 'iteration': iteration, 'milestonesMs': marks, 'composerBuilds': builds, 'settledMs': elapsed.elapsedMicroseconds / 1000})}',
          );
        }
        SurfaceOpeningTrace.observer = null;
        shell.closeComposer();
        await tester.pumpAndSettle();
        expect(shell.topicPanelsVisible, isTrue);
        for (final entry in boundaries.entries) {
          expect(boundaryFor(entry.key), same(entry.value));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
