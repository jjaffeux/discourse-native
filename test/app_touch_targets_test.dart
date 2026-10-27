import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('routes and toasts take presses through the touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([instance('forum.example')]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pumpAndSettle();

    for (final inside in [Navigator, DToaster, AdaptiveShell]) {
      expect(
        find.ancestor(
          of: find.byType(inside).first,
          matching: find.byType(DTouchTargets),
        ),
        findsOneWidget,
        reason: '$inside',
      );
    }
  });
}
