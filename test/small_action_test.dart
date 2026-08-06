import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/small_action.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

Post smallAction(
  String actionCode, {
  String? who,
  String cooked = '',
  String username = 'martin',
}) => Post(
  id: 1,
  postNumber: 2,
  username: username,
  cooked: cooked,
  postType: Post.smallActionPostType,
  actionCode: actionCode,
  actionCodeWho: who,
);

/// HtmlWidget renders into a bare RichText, which find.text ignores.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

Future<void> pumpAction(WidgetTester tester, Post post) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SmallActionTile(post: post)),
    ),
  );
}

void main() {
  group('parsing', () {
    test('a small action carries its action code', () {
      final post = Post.fromJson({
        'id': 5,
        'post_number': 3,
        'username': 'martin',
        'cooked': '',
        'post_type': 3,
        'action_code': 'closed.enabled',
      }, 'https://meta.discourse.org');

      expect(post.isSmallAction, isTrue);
      expect(post.actionCode, 'closed.enabled');
    });

    test('a regular post is not a small action', () {
      final post = Post.fromJson({
        'id': 5,
        'post_number': 3,
        'username': 'martin',
        'cooked': '<p>hi</p>',
        'post_type': 1,
      }, 'https://meta.discourse.org');

      expect(post.isSmallAction, isFalse);
      expect(post.actionCode, isNull);
    });

    test('a blank action_code_who is dropped', () {
      final post = Post.fromJson({
        'id': 5,
        'post_number': 3,
        'username': 'martin',
        'cooked': '',
        'post_type': 3,
        'action_code': 'invited_user',
        'action_code_who': '  ',
      }, 'https://meta.discourse.org');

      expect(post.actionCodeWho, isNull);
    });
  });

  group('wording', () {
    String phraseFor(String code, {String? who}) =>
        SmallActionDescription.of(smallAction(code, who: who))!.phrase;

    test('reads like Discourse does', () {
      expect(phraseFor('closed.enabled'), 'closed this topic');
      expect(phraseFor('autoclosed.disabled'), 'opened this topic');
      expect(phraseFor('visible.disabled'), 'unlisted this topic');
      expect(phraseFor('user_left'), 'removed themselves from this message');
    });

    test('names who an action was taken on', () {
      expect(phraseFor('invited_user', who: '@jane'), 'invited @jane');
      expect(phraseFor('removed_group', who: 'staff'), 'removed staff');
    });

    test('an unknown action code still says something', () {
      expect(phraseFor('assigned.enabled'), 'assigned enabled');
    });

    test('a regular post has no description', () {
      final post = Post(
        id: 1,
        postNumber: 1,
        username: 'a',
        cooked: '<p>x</p>',
      );
      expect(SmallActionDescription.of(post), isNull);
    });
  });

  group('rendering', () {
    testWidgets('shows the actor and what they did', (tester) async {
      await pumpAction(tester, smallAction('closed.enabled'));

      expect(renderedText('martin closed this topic'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('draws a custom message underneath', (tester) async {
      await pumpAction(
        tester,
        smallAction('closed.enabled', cooked: '<p>Answered above.</p>'),
      );

      expect(renderedText('Answered above.'), findsOneWidget);
    });

    testWidgets('a bodyless action draws nothing but the notice', (
      tester,
    ) async {
      await pumpAction(tester, smallAction('pinned.enabled'));

      expect(renderedText('martin pinned this topic'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    });
  });
}
