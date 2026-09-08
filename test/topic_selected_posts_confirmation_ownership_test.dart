import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _topicId = 7;
const _originalKey = 'original-key';
const _moderator = DiscourseUser(id: 9, username: 'moderator', staff: true);
const _toolbarKey = ValueKey('topic-selected-posts-toolbar');

void main() {
  for (final action in ['delete', 'merge']) {
    testWidgets('$action rejects an old confirmation before credentials', (
      tester,
    ) async {
      final (:shell, :api, :auth) = await _openTopic(tester);
      final openingToolbar = tester.element(find.byKey(_toolbarKey));
      final openingLease = shell.lifecycle.capture(_site);
      final openingPost = shell.store.read<Post>(_site, 1);
      await _openConfirmation(tester, action);
      final openingDialog = tester.element(find.byType(AlertDialog));

      // Reconnect and repopulate between frames, keeping the actual toolbar's
      // caller mounted when its old dialog submits. An unmounted caller would
      // hide the ownership bug behind the existing context.mounted check.
      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await shell.loadTopic(_topicId, 'source');
      shell.openTopicPost(siteUrl: _site, topicId: _topicId, postNumber: 1);
      _select(shell, [1, 2, 3]);
      expect(shell.currentInstance?.user?.id, 10);
      expect(auth.keys[_site], 'api-key');
      expect(openingLease.isCurrent, isFalse);
      expect(openingToolbar.mounted, isTrue);
      expect(tester.element(find.byType(AlertDialog)), same(openingDialog));
      final replacementTopic = shell.store.read<TopicDetail>(_site, _topicId);
      final replacementPosts = [
        for (var id = 1; id <= 4; id++) shell.store.read<Post>(_site, id),
      ];
      expect(replacementPosts.first, isNot(same(openingPost)));
      expect(replacementTopic?.canSelectPosts, isTrue);
      expect(shell.selectedTopicPosts(_site, _topicId).map((post) => post.id), [
        1,
        2,
        3,
      ]);
      expect(
        shell
            .selectedTopicPosts(_site, _topicId)
            .every((post) => post.canDelete),
        isTrue,
      );
      expect(
        shell
            .selectedTopicPosts(_site, _topicId)
            .map((post) => post.username)
            .toSet(),
        {'author'},
      );
      final readsBeforeSubmit = auth.reads.length;
      final fetchesBeforeSubmit = api.postFetches.length;

      await tester.tap(find.byKey(ValueKey('topic-selected-$action-confirm')));
      await tester.idle();
      // Check before rebuilding the replacement account's UI, which can make
      // its own unrelated credential reads.
      expect(auth.reads, hasLength(readsBeforeSubmit));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      expect(api.postFetches, hasLength(fetchesBeforeSubmit));
      expect(
        shell.store.read<TopicDetail>(_site, _topicId),
        same(replacementTopic),
      );
      for (var id = 1; id <= 4; id++) {
        expect(
          shell.store.read<Post>(_site, id),
          same(replacementPosts[id - 1]),
        );
        expect(shell.postWriteInFlight(id, siteUrl: _site), isFalse);
      }
      expect(shell.selectedTopicPostIds(_site, _topicId), {1, 2, 3});
      expect(shell.topicPostSelectionWriteInFlight(_site, _topicId), isFalse);
      expect(find.byType(AlertDialog), findsNothing);

      // A new confirmation belongs to the replacement account and can act on
      // those same eligible IDs with its new credential.
      await _openConfirmation(tester, action);
      await _submit(tester, action);

      _expectWrite(api, action, 'api-key', [1, 2, 3]);
      expect(shell.topicPostSelectionEnabled(_site, _topicId), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('$action uses the same account selection at submit', (
      tester,
    ) async {
      final (:shell, :api, auth: _) = await _openTopic(tester);
      final openingLease = shell.lifecycle.capture(_site);
      await _openConfirmation(tester, action);
      _select(shell, [2, 3, 4]);
      await tester.pumpAndSettle();
      expect(openingLease.isCurrent, isTrue);
      expect(
        find.text(
          action == 'delete'
              ? 'Delete 2 selected posts?'
              : 'Merge 2 posts by the same author into one post?',
        ),
        findsOneWidget,
      );

      await _submit(tester, action);

      _expectWrite(api, action, _originalKey, [2, 3, 4]);
      expect(shell.topicPostSelectionEnabled(_site, _topicId), isFalse);
      expect(find.byKey(_toolbarKey), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
      '$action cancellation preserves selection without credentials',
      (tester) async {
        final (:shell, :api, :auth) = await _openTopic(tester);
        await _openConfirmation(tester, action);
        final readsBeforeCancel = auth.reads.length;
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();

        expect(auth.reads, hasLength(readsBeforeCancel));
        expect(api.writes, isEmpty);
        expect(api.postFetches, isEmpty);
        expect(shell.selectedTopicPostIds(_site, _topicId), {1, 2});
        expect(find.byKey(_toolbarKey), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    for (final change in [
      'post permission',
      'topic permission',
      'empty selection',
      if (action == 'merge') ...['author', 'single post'],
    ]) {
      testWidgets('$action rechecks $change at confirmation submit', (
        tester,
      ) async {
        final (:shell, :api, :auth) = await _openTopic(tester);
        final openingLease = shell.lifecycle.capture(_site);
        await _openConfirmation(tester, action);
        switch (change) {
          case 'post permission':
            shell.store.put(_site, _post(1, canDelete: false));
          case 'topic permission':
            shell.store.put(
              _site,
              const TopicDetail(
                id: _topicId,
                title: 'Source topic',
                stream: [1, 2, 3, 4],
                postsCount: 4,
              ),
            );
          case 'empty selection':
            shell.clearSelectedTopicPosts(_site, _topicId);
          case 'author':
            shell.store.put(_site, _post(2, username: 'another-author'));
          case 'single post':
            shell.toggleTopicPostSelected(_site, _topicId, 2);
        }
        final selected = shell.selectedTopicPostIds(_site, _topicId);
        final readsBeforeSubmit = auth.reads.length;
        expect(openingLease.isCurrent, isTrue);

        await _submit(tester, action);

        expect(auth.reads, hasLength(readsBeforeSubmit));
        expect(api.writes, isEmpty);
        expect(api.postFetches, isEmpty);
        expect(shell.selectedTopicPostIds(_site, _topicId), selected);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }
}

Future<
  ({ShellController shell, _SelectionApi api, _CountingAuthenticator auth})
>
_openTopic(WidgetTester tester) async {
  final api = _SelectionApi();
  final auth = _CountingAuthenticator()..keys[_site] = _originalKey;
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [instance('meta.discourse.org').copyWith(user: _moderator)],
    authenticator: auth,
  );
  await tester.tap(find.text('Source topic'));
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(MainContent)));
  await tester.tap(find.byKey(const ValueKey('topic-status-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
  await tester.tap(find.byKey(const ValueKey('topic-post-select-2')));
  await tester.pumpAndSettle();
  expect(shell.selectedTopicPostIds(_site, _topicId), {1, 2});
  expect(find.byKey(_toolbarKey), findsOneWidget);
  return (shell: shell, api: api, auth: auth);
}

void _select(ShellController shell, List<int> ids) {
  shell.setTopicPostSelectionEnabled(_site, _topicId, true);
  shell.clearSelectedTopicPosts(_site, _topicId);
  for (final id in ids) {
    shell.toggleTopicPostSelected(_site, _topicId, id);
  }
}

Future<void> _openConfirmation(WidgetTester tester, String action) async {
  final button = find.byKey(ValueKey('topic-selected-posts-$action'));
  await tester.ensureVisible(button);
  expect(tester.widget<TextButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _submit(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(ValueKey('topic-selected-$action-confirm')));
  await tester.pumpAndSettle();
}

void _expectWrite(_SelectionApi api, String action, String key, List<int> ids) {
  expect(api.writes, [(action: action, siteUrl: _site, apiKey: key)]);
  expect(action == 'delete' ? api.bulkDeleted : api.merged, [ids]);
  expect(action == 'delete' ? api.merged : api.bulkDeleted, isEmpty);
  expect(api.postFetches, [ids]);
}

Post _post(
  int id, {
  String label = 'original',
  String username = 'author',
  bool canDelete = true,
}) => Post(
  id: id,
  postNumber: id,
  username: username,
  cooked: '<p>$label post $id</p>',
  canDelete: canDelete,
);

class _CountingAuthenticator extends FakeAuthenticator {
  final reads = <String>[];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads.add(siteUrl);
    return super.apiKeyFor(siteUrl);
  }
}

class _SelectionApi extends FakeDiscourseApi {
  _SelectionApi()
    : super(
        user: _moderator,
        feeds: const {
          '/latest.json': [
            Topic(id: _topicId, title: 'Source topic', slug: 'source'),
          ],
        },
      );

  final writes = <({String action, String siteUrl, String apiKey})>[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == _originalKey
      ? _moderator
      : const DiscourseUser(id: 10, username: 'replacement', staff: true);

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async => topicPayload(
    id: id,
    title: 'Source topic',
    posts: [
      for (var id = 1; id <= 4; id++)
        _post(id, label: apiKey == _originalKey ? 'original' : 'replacement'),
    ],
    canSplitMergeTopic: true,
  );

  @override
  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) {
    writes.add((action: 'delete', siteUrl: siteUrl, apiKey: apiKey));
    return super.deletePosts(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postIds: postIds,
    );
  }

  @override
  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) {
    writes.add((action: 'merge', siteUrl: siteUrl, apiKey: apiKey));
    return super.mergePosts(siteUrl: siteUrl, apiKey: apiKey, postIds: postIds);
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(List.of(ids));
    return merged.isEmpty ? [] : [_post(ids.first, label: 'merged')];
  }
}
