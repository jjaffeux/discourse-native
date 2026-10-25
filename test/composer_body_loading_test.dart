import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _target = PostEditComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicTitle: 'An existing topic',
  topicId: 7,
  slug: 'an-existing-topic',
  privateMessageTopic: false,
  editingPostId: 9,
  editingPostNumber: 2,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mobile in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets('post body loading uses a skeleton before editing '
          '${mobile ? 'mobile' : 'desktop'} dark=$dark flat', (tester) async {
        final composer = ComposerController(_target)..beginLoadingBody();
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await _pumpPanel(tester, shell, composer, mobile: mobile, dark: dark);

          final loading = find.bySemanticsLabel('Loading that post…');
          expect(loading, findsOneWidget);
          expect(find.text('Loading that post…'), findsNothing);
          expect(find.byType(ComposerEditor), findsNothing);
          expect(find.byType(DSkeletonRegion), findsOneWidget);
          expect(find.byType(DSkeleton), findsWidgets);
          expect(
            tester.getSize(find.byType(DSkeletonRegion)).height,
            greaterThan(0),
          );
          expect(tester.takeException(), isNull);

          composer.loadedBody('The original post body has arrived.');
          await tester.pumpAndSettle();

          expect(loading, findsNothing);
          expect(find.byType(DSkeletonRegion), findsNothing);
          expect(find.byType(ComposerEditor), findsOneWidget);
          expect(
            find.text('The original post body has arrived.'),
            findsOneWidget,
          );
          expect(composer.isEditing, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'a failed body load removes its skeleton and keeps saving disabled',
    (tester) async {
      final composer = ComposerController(_target)..beginLoadingBody();
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);
      expect(find.byType(DSkeletonRegion), findsOneWidget);

      composer.bodyLoadFailed();
      await tester.pumpAndSettle();

      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.byType(ComposerEditor), findsOneWidget);
      expect(composer.error, isNotNull);
      expect(composer.canSubmit, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  bool mobile = false,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(Size(mobile ? 340 : 1000, 650));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark
          ? AppTheme.dark
          : AppTheme.light.copyWith(
              platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
            ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposerPanel(composer: composer, height: 500),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
