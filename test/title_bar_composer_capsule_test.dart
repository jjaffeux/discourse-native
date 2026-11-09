import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _user = DiscourseUser(
  id: 3,
  username: 'reader',
  canCreateTopic: true,
  canSendPrivateMessages: true,
);
const _topic = Topic(id: 42, title: 'A topic', slug: 'a-topic');
const _closedTopic = Topic(id: 43, title: 'Closed topic', slug: 'closed');

TopicPayload _payload(Topic topic, {required bool canCreatePost}) => (
  detail: TopicDetail(
    id: topic.id,
    title: topic.title,
    stream: const [1],
    postsCount: 1,
    canCreatePost: canCreatePost,
  ),
  posts: const [
    Post(id: 1, postNumber: 1, username: 'sam', cooked: '<p>First post</p>'),
  ],
);

Future<ShellController> _pump(WidgetTester tester) async {
  await pumpShell(
    tester,
    desktop,
    instances: [instance('meta.discourse.org').copyWith(user: _user)],
    api: FakeDiscourseApi(
      user: _user,
      feeds: const {
        '/latest.json': [_topic],
      },
      creatableFeedPaths: const {'/latest.json'},
      topics: {
        _topic.id: _payload(_topic, canCreatePost: true),
        _closedTopic.id: _payload(_closedTopic, canCreatePost: false),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'key',
  );
  return ShellScope.read(tester.element(find.byType(MainContent).first));
}

Finder _inTitleBar(Key key) =>
    find.descendant(of: find.byType(ShellTitleBar), matching: find.byKey(key));

Finder get _toggle => _inTitleBar(ShellTitleBar.composerToggleKey);
Finder get _newTopic => _inTitleBar(TopicCreateButton.buttonKey);
Finder get _reply => _inTitleBar(const ValueKey('title-bar-reply'));
Finder get _drafts => _inTitleBar(TopicCreateButton.draftsButtonKey);

Finder get _composerHeaderMinimize =>
    find.byKey(const ValueKey('composer-minimize'));
Finder get _composerRestoreStrip =>
    find.byKey(const ValueKey('composer-restore'));

void _expectWriting(WidgetTester tester) {
  expect(tester.widget<DButton>(_toggle).semanticLabel, 'Minimize composer');
  expect(
    buttonSurface(tester, of: _toggle).color,
    DTokens.of(
      tester.element(_toggle),
    ).buttonTheme.primary.foreground.withValues(alpha: .18),
  );
  expect(_composerHeaderMinimize, findsOneWidget);
  expect(_composerRestoreStrip, findsNothing);
}

void _expectMinimized(WidgetTester tester) {
  expect(tester.widget<DButton>(_toggle).semanticLabel, 'Resume editing');
  expect(buttonSurface(tester, of: _toggle).color, Colors.transparent);
  expect(_composerHeaderMinimize, findsNothing);
  expect(_composerRestoreStrip, findsOneWidget);
}

Future<void> _tapAndSettle(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void _capsuleTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(description, body, semanticsEnabled: false, variant: _macOS);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the capsule tells assistive technology when it is held in', (
    tester,
  ) async {
    final shell = await _pump(tester);
    void expectHeldIn({required bool held}) => expect(
      tester.getSemantics(_toggle),
      isSemantics(
        label: held ? 'Minimize composer' : 'Resume editing',
        isButton: true,
        hasToggledState: true,
        isToggled: held,
      ),
    );

    await _tapAndSettle(tester, _newTopic);
    expectHeldIn(held: true);

    // Each trip swaps the dock's layout under a live semantics tree, and it is
    // the change after a restore that used to corrupt it.
    for (final held in [false, true, false, true]) {
      await _tapAndSettle(tester, _toggle);
      expectHeldIn(held: held);
    }

    shell.closeComposer();
    await tester.pumpAndSettle();
    expect(_toggle, findsNothing);
  }, variant: _macOS);

  _capsuleTest(
    'on a list the capsule goes from new topic to minimize to resume and back',
    (tester) async {
      final shell = await _pump(tester);

      expect(_toggle, findsNothing);
      expect(_newTopic, findsOneWidget);
      expect(_drafts, findsOneWidget);

      await _tapAndSettle(tester, _newTopic);
      final composer = shell.visibleComposer!;
      expect(_newTopic, findsNothing);
      expect(_drafts, findsOneWidget);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      expect(identical(shell.visibleComposer, composer), isTrue);
      expect(composer.focus.hasFocus, isFalse);
      expect(_drafts, findsOneWidget);
      _expectMinimized(tester);

      await _tapAndSettle(tester, _toggle);
      expect(identical(shell.visibleComposer, composer), isTrue);
      expect(composer.focus.hasFocus, isTrue);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      _expectMinimized(tester);
      shell.closeComposer(composer: composer);
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, isNull);
      expect(_toggle, findsNothing);
      expect(_newTopic, findsOneWidget);
    },
  );

  _capsuleTest(
    'in a topic the capsule keeps the reply glyph and offers no drafts',
    (tester) async {
      final shell = await _pump(tester);
      shell.openTopicFromList(_topic);
      await tester.pumpAndSettle();
      expect(_reply, findsOneWidget);
      expect(_toggle, findsNothing);

      await _tapAndSettle(tester, _reply);
      expect(_reply, findsNothing);
      expect(_drafts, findsNothing);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      expect(_reply, findsNothing);
      expect(_drafts, findsNothing);
      _expectMinimized(tester);
    },
  );

  _capsuleTest(
    "the composer's own minimize and restore controls move the capsule",
    (tester) async {
      await _pump(tester);
      await _tapAndSettle(tester, _newTopic);
      _expectWriting(tester);

      await _tapAndSettle(tester, _composerHeaderMinimize);
      _expectMinimized(tester);

      await _tapAndSettle(tester, _composerRestoreStrip);
      _expectWriting(tester);
    },
  );

  _capsuleTest(
    'an open composer keeps the capsule on a page with no action of its own',
    (tester) async {
      final shell = await _pump(tester);
      shell.openTopicFromList(_closedTopic);
      await tester.pumpAndSettle();
      expect(_reply, findsNothing);
      expect(_toggle, findsNothing);

      await shell.openNewTopicFromSidebar();
      await tester.pumpAndSettle();
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      _expectMinimized(tester);

      shell.closeComposer();
      await tester.pumpAndSettle();
      expect(_toggle, findsNothing);
      expect(_reply, findsNothing);
    },
  );

  _capsuleTest(
    'with several drafts open the capsule answers for the selected one',
    (tester) async {
      final shell = await _pump(tester);
      await shell.openNewTopicFromSidebar();
      final first = shell.visibleComposer!;
      first.title.text = 'First';
      await tester.pumpAndSettle();
      await shell.openNewTopicFromSidebar();
      final second = shell.visibleComposer!;
      second.title.text = 'Second';
      await tester.pumpAndSettle();
      expect(identical(first, second), isFalse);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      _expectMinimized(tester);

      shell.selectComposer(first);
      await tester.pumpAndSettle();
      expect(identical(shell.visibleComposer, first), isTrue);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      _expectMinimized(tester);
      await _tapAndSettle(tester, _toggle);
      expect(identical(shell.visibleComposer, first), isTrue);
      expect(first.focus.hasFocus, isTrue);
      expect(second.focus.hasFocus, isFalse);
      _expectWriting(tester);

      // Closing the selected draft reveals its neighbour, minimized or not.
      shell.closeComposer(composer: first);
      await tester.pumpAndSettle();
      expect(identical(shell.visibleComposer, second), isTrue);
      expect(second.focus.hasFocus, isTrue);
      _expectWriting(tester);

      await _tapAndSettle(tester, _toggle);
      expect(second.focus.hasFocus, isFalse);
      _expectMinimized(tester);
    },
  );
}
