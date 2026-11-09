import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/user_card_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('the application offers the user card to every route under it', (
    tester,
  ) async {
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore(const []),
        api: FakeDiscourseApi(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pump();

    final underNavigator = tester.element(find.byType(Navigator).first);
    expect(UserCardOpenerScope.maybeOf(underNavigator), isNotNull);
  });
}
