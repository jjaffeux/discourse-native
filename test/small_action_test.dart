import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/small_action.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

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
      final post = Post.fromJson(const {
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
      final post = Post.fromJson(const {
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
      final post = Post.fromJson(const {
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

    for (final (:code, :phrase) in [
      (code: 'closed.enabled', phrase: 'closed this topic'),
      (code: 'autoclosed.disabled', phrase: 'opened this topic'),
      (code: 'visible.disabled', phrase: 'unlisted this topic'),
      (code: 'user_left', phrase: 'removed themselves from this message'),
    ]) {
      test('$code reads as "$phrase"', () {
        expect(phraseFor(code), phrase);
      });
    }

    test('names who an action was taken on', () {
      expect(phraseFor('invited_user', who: '@jane'), 'invited @jane');
      expect(phraseFor('removed_group', who: 'staff'), 'removed staff');
    });

    test('an unknown action code still says something', () {
      expect(phraseFor('assigned.enabled'), 'assigned enabled');
    });

    test('a regular post has no description', () {
      const post = Post(
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
      expect(find.dIcon(DIcons.lock), findsOneWidget);
    });

    testWidgets('is a mark and one quiet line, with the time after a dot, '
        'keeping a post card\'s room', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SmallActionTile(
                post: Post(
                  id: 1,
                  postNumber: 2,
                  username: 'martin',
                  cooked: '',
                  postType: Post.smallActionPostType,
                  actionCode: 'closed.enabled',
                  createdAt: DateTime.now().subtract(const Duration(days: 3)),
                ),
              ),
            ),
          ),
        ),
      );
      TextStyle styleOf(Finder text) => DefaultTextStyle.of(
        tester.element(text),
      ).style.merge(tester.widget<Text>(text).style);

      expect(find.byType(DAvatar), findsNothing);
      final line = find.text('martin closed this topic');
      final style = styleOf(line);
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w400);
      final tokens = DTokens.of(tester.element(line));
      expect(
        style.color,
        Color.lerp(tokens.background, tokens.foreground, .62),
      );
      final dot = find.text(' · ');
      expect(styleOf(dot).color, tokens.mutedForeground);
      final time = find.text('3d');
      expect(styleOf(time).color, tokens.mutedForeground);
      expect(tester.getTopLeft(time).dx, tester.getTopRight(dot).dx);

      final mark = find.dIcon(DIcons.lock);
      expect(tester.getSize(mark), const Size.square(15));
      expect(tester.getRect(line).left - tester.getCenter(mark).dx, 15 + 9);
      final tile = tester.getRect(find.byType(SmallActionTile));
      expect(tester.getCenter(mark).dy - tile.top, 32 + 15);
      expect(tile.bottom - tester.getCenter(mark).dy, 15 + 10);
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
      expect(find.dIcon(DIcons.thumbtack), findsOneWidget);
    });
  });
}
