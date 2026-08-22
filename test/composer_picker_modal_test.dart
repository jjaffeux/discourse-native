import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The category and tag pickers belong to the composer they were opened from,
/// so on a pointer platform they sit over it as dialogs rather than at the far
/// bottom edge of the window.
void main() {
  Future<ShellController> pumpComposer(
    WidgetTester tester, {
    required TargetPlatform platform,
  }) async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
        categoryList: const [
          TopicCategory(id: 5, name: 'Support', color: '0088CC', permission: 1),
        ],
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    // Real async: the composer opens off several awaited reads, which the
    // test's fake clock would never let finish.
    await tester.runAsync(() async {
      await shell.load();
      await pumpEventQueue();
      await shell.openNewTopic();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ComposerPanel(composer: shell.visibleComposer!),
          ),
        ),
      ),
    );
    // Never pumpAndSettle here: the composer's caret keeps blinking.
    await tester.pump();
    return shell;
  }

  Future<void> open(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the category picker is a dialog on desktop', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.macOS);

    await open(tester, 'Category');

    expect(find.text('Choose category'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the tag picker is a dialog on desktop', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.macOS);

    await open(tester, 'Tags');

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the category picker stays a sheet on touch', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.iOS);

    await open(tester, 'Category');

    expect(find.text('Choose category'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the tag picker stays a sheet on touch', (tester) async {
    await pumpComposer(tester, platform: TargetPlatform.iOS);

    await open(tester, 'Tags');

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
