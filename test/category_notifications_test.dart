import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://meta.discourse.org';
const _category = TopicCategory(
  id: 5,
  name: 'Support',
  color: '0088CC',
  slug: 'support',
);
const _user = DiscourseUser(id: 7, username: 'reader');

Future<ShellController> _openCategory(
  WidgetTester tester,
  FakeDiscourseApi api, {
  bool signedIn = true,
}) async {
  final site = instance(
    'meta.discourse.org',
  ).copyWith(user: signedIn ? _user : null);
  final authenticator = FakeAuthenticator();
  if (signedIn) authenticator.keys[_siteUrl] = 'api-key';
  await pumpShell(
    tester,
    laptop,
    instances: [site],
    api: api,
    authenticator: authenticator,
  );
  final controller = ShellScope.read(tester.element(find.byType(MainContent)));
  expect(controller.openListUrl('/c/support/5'), isTrue);
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('shows all web category notification levels and saves a choice', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/c/support/5.json': []},
      categoryList: const [_category],
      categoryNotificationGate: gate,
    );
    final controller = await _openCategory(tester, api);
    final button = find.byKey(
      const ValueKey('category-notification-level-button'),
    );

    expect(button, findsOneWidget);
    expect(find.byTooltip('Category notifications: Normal'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Watching'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text('Watching First Post'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Muted'), findsOneWidget);

    await tester.tap(find.text('Watching First Post'));
    await tester.pumpAndSettle();

    expect(
      controller.categoryFor(5)?.notificationLevel,
      CategoryNotificationLevel.watchingFirstPost,
    );
    expect(
      find.byTooltip('Category notifications: Watching First Post'),
      findsOneWidget,
    );
    expect(api.categoryNotificationLevelsUpdated, [
      (
        siteUrl: _siteUrl,
        categoryId: 5,
        notificationLevel: CategoryNotificationLevel.watchingFirstPost,
      ),
    ]);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('rolls the selected level back when the server rejects it', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/c/support/5.json': []},
      categoryList: const [_category],
      categoryNotificationGate: gate,
      writeFailure: const WriteException(WriteFailure.forbidden),
    );
    final controller = await _openCategory(tester, api);
    final button = find.byKey(
      const ValueKey('category-notification-level-button'),
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muted'));
    await tester.pumpAndSettle();
    expect(
      controller.categoryFor(5)?.notificationLevel,
      CategoryNotificationLevel.muted,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      controller.categoryFor(5)?.notificationLevel,
      CategoryNotificationLevel.normal,
    );
    expect(find.byTooltip('Category notifications: Normal'), findsOneWidget);
  });

  testWidgets('does not show the category bell while signed out', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': [], '/c/support/5.json': []},
      categoryList: const [_category],
    );

    await _openCategory(tester, api, signedIn: false);

    expect(
      find.byKey(const ValueKey('category-notification-level-button')),
      findsNothing,
    );
  });
}
