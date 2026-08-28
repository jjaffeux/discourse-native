import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/shell/post_revision_history.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post reads the public edit count and history permission', () {
    final post = Post.fromJson(const {
      'id': 42,
      'post_number': 1,
      'username': 'sam',
      'cooked': '<p>Edited</p>',
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-02T10:00:00Z',
      'version': 4,
      'can_view_edit_history': true,
    }, 'https://example.com');

    expect(post.editCount, 3);
    expect(post.canViewEditHistory, isTrue);
    expect(post.updatedAt, DateTime.utc(2026, 8, 2, 10));
    expect(post.copyWith(hidden: true).editCount, 3);
    expect(post.copyWith(hidden: true).canViewEditHistory, isTrue);
  });

  test('revision reads navigation and topic metadata changes', () {
    final revision = PostRevision.fromJson(const {
      'post_id': 42,
      'current_revision': 3,
      'first_revision': 2,
      'previous_revision': 2,
      'next_revision': 4,
      'last_revision': 4,
      'current_version': 3,
      'version_count': 4,
      'username': 'sam',
      'acting_user_name': 'Sam Example',
      'body_changes': {'inline': '<p>Body diff</p>'},
      'title_changes': {'inline': '<div>Title diff</div>'},
      'tags_changes': {
        'previous': ['old'],
        'current': ['new'],
      },
      'category_id_changes': {'previous': 2, 'current': 3},
      'wiki_changes': {'previous': false, 'current': true},
      'reply_to_post_number_changes': {
        'previous': null,
        'current': {'post_number': 7, 'username': 'lee'},
      },
    }, 'https://example.com');

    expect(revision.previousRevision, 2);
    expect(revision.nextRevision, 4);
    expect(revision.editorDisplayName, 'Sam Example');
    expect(revision.bodyChanges?.inline, '<p>Body diff</p>');
    expect(revision.tagsChanges?.previous, ['old']);
    expect(revision.categoryIdChanges?.current, 3);
    expect(revision.wikiChanges?.current, isTrue);
    expect(revision.replyToPostNumberChanges?.current?.postNumber, 7);
    expect(revision.comparisonLabel, 'Comparing version 2 to 3 of 4');
  });

  testWidgets('edit indicator shows the count and permission gate', (
    tester,
  ) async {
    var pressed = false;
    const post = Post(
      id: 42,
      postNumber: 1,
      username: 'sam',
      cooked: '',
      version: 3,
      canViewEditHistory: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PostRevisionIndicator(
            post: post,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PostRevisionIndicator)),
      matchesSemantics(
        label: '2 edits. View edit history',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('post-revision-indicator-42')));
    expect(pressed, isTrue);
  });

  testWidgets('history renders the latest diff and follows server navigation', (
    tester,
  ) async {
    final requested = <int?>[];
    PostRevision revision({required int currentRevision}) => PostRevision(
      postId: 42,
      currentRevision: currentRevision,
      firstRevision: 2,
      previousRevision: currentRevision == 3 ? 2 : null,
      nextRevision: currentRevision == 2 ? 3 : null,
      lastRevision: 3,
      currentVersion: currentRevision,
      versionCount: 3,
      username: currentRevision == 3 ? 'latest-editor' : 'first-editor',
      editReason: currentRevision == 3 ? 'Clarified the report' : null,
      bodyChanges: PostRevisionDiff(
        inline: '<div><p>Body at revision $currentRevision</p></div>',
      ),
      tagsChanges: currentRevision == 3
          ? const PostRevisionChange(
              previous: ['old-tag'],
              current: ['new-tag'],
            )
          : null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPostRevisionHistory(
                context: context,
                siteUrl: 'https://example.com',
                post: const Post(
                  id: 42,
                  postNumber: 1,
                  username: 'sam',
                  cooked: '',
                  version: 3,
                ),
                loadRevision: (number) async {
                  requested.add(number);
                  return revision(currentRevision: number ?? 3);
                },
              ),
              child: const Text('History'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(requested, [null]);
    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('latest-editor'), findsOneWidget);
    expect(find.text('Clarified the report'), findsOneWidget);
    expect(find.text('old-tag'), findsOneWidget);
    expect(find.text('new-tag'), findsOneWidget);
    expect(find.text('Comparing version 2 to 3 of 3'), findsOneWidget);
    expect(_richTextContaining('Body at revision 3'), findsOneWidget);

    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();

    expect(requested, [null, 2]);
    expect(find.text('first-editor'), findsOneWidget);
    expect(find.text('Comparing version 1 to 2 of 3'), findsOneWidget);
    expect(_richTextContaining('Body at revision 2'), findsOneWidget);
  });
}

Finder _richTextContaining(String value) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(value),
);
