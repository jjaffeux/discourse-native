import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _draft = UserDraft(
  key: 'new_topic',
  sequence: 1,
  data: ComposerDraft(reply: 'Draft body', title: 'Draft topic'),
);

void main() {
  testWidgets('compact New topic controls are 44 pixel keyboard buttons', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final semantics = tester.ensureSemantics();
    try {
      final create = find.byKey(TopicCreateButton.buttonKey);
      final drafts = find.byKey(TopicCreateButton.draftsButtonKey);

      _expectAccessibleTarget(tester, create);
      _expectAccessibleTarget(tester, drafts);
      expect(find.byTooltip('New topic'), findsOneWidget);
      expect(find.byTooltip('Open the latest drafts menu'), findsOneWidget);
      expect(
        tester.getSemantics(create),
        isSemantics(
          label: 'New topic',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(drafts),
        isSemantics(
          label: 'Open the latest drafts menu',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(tester.getSemantics(create).tooltip, isEmpty);
      expect(tester.getSemantics(drafts).tooltip, isEmpty);

      final createFocus = _focusButton(tester, create);
      await tester.pumpAndSettle();
      expect(createFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fixture.createCalls(), 1);

      final draftsFocus = _focusButton(tester, drafts);
      await tester.pumpAndSettle();
      expect(draftsFocus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('recent-draft-new_topic')),
        findsOneWidget,
      );
      expect(fixture.api.userDraftRequests, [
        (siteUrl: _siteUrl, offset: 0, limit: 30),
      ]);
    } finally {
      semantics.dispose();
    }
  });
}

void _expectAccessibleTarget(WidgetTester tester, Finder target) {
  final size = tester.getSize(target);
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
  expect(
    tester
        .widget<FilledButton>(target)
        .style
        ?.minimumSize
        ?.resolve(<WidgetState>{}),
    const Size.square(44),
  );
}

typedef _Fixture = ({FakeDiscourseApi api, int Function() createCalls});

Future<_Fixture> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = DiscourseUser(
    id: 7,
    username: 'reader',
    name: 'Reader',
    draftCount: 1,
  );
  final site = instance('meta.example').copyWith(user: user);
  final api = FakeDiscourseApi(
    user: user,
    totals: const NotificationTotals(),
    userDraftList: const [_draft],
    feeds: const {'/latest.json': []},
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();

  var createCalls = 0;
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TopicCreateButton(
              showLabel: false,
              onPressed: () => createCalls++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, createCalls: () => createCalls);
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
