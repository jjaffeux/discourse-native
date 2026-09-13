import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_move_posts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteA = 'https://meta.discourse.org';
const _siteB = 'https://team.discourse.org';
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);
const _obsolete = 'Your connection changed. Reopen Move posts and try again.';
const _dialog = ValueKey('topic-move-posts-dialog');
const _submit = ValueKey('topic-move-posts-submit');
const _search = ValueKey('topic-move-posts-search');
const _title = ValueKey('topic-move-posts-title');
const _posts = [
  Post(id: 1, postNumber: 1, username: 'author', cooked: '<p>First</p>'),
  Post(id: 2, postNumber: 2, username: 'author', cooked: '<p>Second</p>'),
  Post(id: 3, postNumber: 3, username: 'author', cooked: '<p>Third</p>'),
];
const _nonregularPost = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>Moderator post</p>',
  postType: 2,
);

void main() {
  for (final newTopic in [true, false]) {
    final mode = newTopic ? 'new topic' : 'existing topic';

    testWidgets('$mode keeps the opening site and selection at submit', (
      tester,
    ) async {
      final api = _MoveApi();
      final shell = await _openDialog(tester, api);
      // The count and modes describe the opening selection, while the write
      // deliberately reads the selection of that same topic when submitted.
      shell.toggleTopicPostSelected(_siteA, 7, 1);
      shell.toggleTopicPostSelected(_siteA, 7, 2);
      shell.openTopicPost(siteUrl: _siteB, topicId: 8, postNumber: 1);
      await tester.pumpAndSettle();
      _select(shell, _siteB, 8, [3]);
      final otherPost = shell.store.read<Post>(_siteB, 2);
      expect(find.text('Move 1 selected post.'), findsOneWidget);
      await _prepare(tester, newTopic: newTopic);
      if (!newTopic) {
        expect(api.searches.single, (
          siteUrl: _siteA,
          apiKey: 'a-key',
          term: 'Destination',
          typeFilter: 'topic',
          searchForId: true,
          restrictToArchetype: 'regular',
        ));
        await tester.tap(
          find.byKey(const ValueKey('topic-move-posts-chronological')),
        );
      }
      await _pressSubmit(tester);
      await tester.pumpAndSettle();

      expect(api.writes.single.siteUrl, _siteA);
      expect(api.writes.single.apiKey, 'a-key');
      expect(api.movedTopicPosts.single.topicId, 7);
      expect(api.movedTopicPosts.single.postIds, [2]);
      expect(api.movedTopicPosts.single.title, newTopic ? 'A new topic' : null);
      expect(
        api.movedTopicPosts.single.destinationTopicId,
        newTopic ? null : 99,
      );
      expect(api.movedTopicPosts.single.chronologicalOrder, !newTopic);
      expect(shell.store.read<Post>(_siteB, 2), same(otherPost));
      expect(shell.selectedTopicPostIds(_siteB, 8), {3});
      expect(shell.topicPostSelectionEnabled(_siteA, 7), isFalse);
      expect(shell.currentInstance?.url, _siteA);
      expect(shell.currentTopic?.id, 99);
      expect(find.byKey(_dialog), findsNothing);
    });

    for (final boundary in [
      'before submit',
      'credentials',
      'response',
      'refresh',
    ]) {
      testWidgets('$mode rejects account replacement at $boundary', (
        tester,
      ) async {
        final api = _MoveApi();
        final auth = _GatedAuthenticator();
        final shell = await _openDialog(tester, api, auth: auth);
        await _prepare(tester, newTopic: newTopic);
        final credential = Completer<String?>();
        final response = Completer<String>();
        final refresh = Completer<List<Post>>();
        if (boundary == 'credentials') auth.nextRead = credential;
        if (boundary == 'response') api.moveResponse = response;
        if (boundary == 'refresh') api.refreshResponse = refresh;
        if (boundary != 'before submit') {
          await _pressSubmit(tester);
          expect(shell.topicPostSelectionWriteInFlight(_siteA, 7), isTrue);
          if (boundary == 'credentials') expect(auth.nextRead, isNull);
          if (boundary == 'refresh') expect(api.refreshes, hasLength(1));
        }

        await _replaceAccount(tester, shell);
        final replacementPost = shell.store.read<Post>(_siteA, 1);
        final refreshCount = api.refreshes.length;
        switch (boundary) {
          case 'before submit':
            await _pressSubmit(tester);
          case 'credentials':
            credential.complete('api-key');
          case 'response':
            response.complete('/t/destination/99');
          case 'refresh':
            refresh.complete([]);
        }
        await tester.pumpAndSettle();

        expect(
          api.writes,
          hasLength(boundary == 'response' || boundary == 'refresh' ? 1 : 0),
        );
        expect(api.refreshes, hasLength(refreshCount));
        expect(shell.currentTopic?.id, 7);
        expect(api.topicsOpened, isNot(contains(99)));
        expect(shell.store.read<Post>(_siteA, 1), same(replacementPost));
        expect(shell.selectedTopicPostIds(_siteA, 7), {2});
        expect(shell.topicPostSelectionWriteInFlight(_siteA, 7), isFalse);
        expect(find.byKey(_dialog), findsOneWidget);
        expect(find.text(_obsolete), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byKey(_dialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_dialog), findsNothing);
      });
    }

    for (final change in [
      'permission',
      'topic membership',
      'stored post',
      if (newTopic) 'all posts',
      if (newTopic) 'post type',
    ]) {
      testWidgets('$mode rechecks $change after credentials and allows retry', (
        tester,
      ) async {
        final api = _MoveApi();
        final auth = _GatedAuthenticator();
        final shell = await _openDialog(tester, api, auth: auth);
        await _prepare(tester, newTopic: newTopic);
        final credential = Completer<String?>();
        auth.nextRead = credential;
        await _pressSubmit(tester);
        expect(auth.nextRead, isNull);
        switch (change) {
          case 'permission':
            shell.store.put(_siteA, topicPayload(id: 7, posts: _posts).detail);
          case 'topic membership':
            shell.store.update<TopicDetail>(
              _siteA,
              7,
              (t) => t.withoutPostId(1),
            );
          case 'stored post':
            shell.store.remove<Post>(_siteA, 1);
          case 'all posts':
            shell.store.update<TopicDetail>(
              _siteA,
              7,
              (topic) => topic.withoutPostId(2).withoutPostId(3),
            );
          case 'post type':
            shell.store.put(_siteA, _nonregularPost);
        }
        credential.complete('a-key');
        await tester.pumpAndSettle();

        expect(api.writes, isEmpty);
        if (change != 'stored post') expect(api.refreshes, isEmpty);
        expect(find.byKey(_dialog), findsOneWidget);
        expect(
          find.byKey(const ValueKey('topic-move-posts-error')),
          findsOneWidget,
        );
        expect(shell.selectedTopicPostIds(_siteA, 7), {1});
        expect(shell.topicPostSelectionWriteInFlight(_siteA, 7), isFalse);

        shell.store.put(
          _siteA,
          topicPayload(id: 7, posts: _posts, canMovePosts: true).detail,
        );
        shell.store.put(_siteA, _posts.first);
        await _pressSubmit(tester);
        await tester.pumpAndSettle();
        expect(api.writes, hasLength(1));
        expect(shell.currentTopic?.id, 99);
      });
    }

    testWidgets('$mode retries a server failure with the same form', (
      tester,
    ) async {
      final api = _MoveApi()
        ..moveFailure = const WriteException(
          WriteFailure.validation,
          errors: ['Try this move again.'],
        );
      final shell = await _openDialog(tester, api);
      await _prepare(tester, newTopic: newTopic);
      await _pressSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Try this move again.'), findsOneWidget);
      expect(shell.selectedTopicPostIds(_siteA, 7), {1});
      expect(api.refreshes, isEmpty);
      api.moveFailure = null;
      await _pressSubmit(tester);
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(2));
      expect(shell.currentTopic?.id, 99);
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('$mode controller never returns a retired destination', (
      tester,
    ) async {
      final api = _MoveApi();
      final shell = await _openDialog(tester, api);
      final response = Completer<String>();
      api.moveResponse = response;
      final target = shell.captureTopicPostMoveTarget(_siteA, 7);
      final pending = newTopic
          ? shell.moveSelectedTopicPostsToNew(target, title: 'New')
          : shell.moveSelectedTopicPostsToExisting(target, 99);
      await tester.pump();
      expect(api.writes, hasLength(1));
      await _replaceAccount(tester, shell);
      response.complete('/t/destination/99');
      final result = await pending;
      expect(result.destinationUrl, isNull);
      expect(result.error, _obsolete);
      expect(api.refreshes, isEmpty);
    });
  }

  for (final boundary in ['debounce', 'credentials', 'response', 'error']) {
    testWidgets('search retains its opening account across $boundary', (
      tester,
    ) async {
      final api = _MoveApi();
      final auth = _GatedAuthenticator();
      final shell = await _openDialog(tester, api, auth: auth);
      await tester.tap(find.text('Existing topic'));
      await tester.pumpAndSettle();
      final credential = Completer<String?>();
      final response = Completer<SearchResults>();
      if (boundary == 'credentials') auth.nextRead = credential;
      if (boundary == 'response' || boundary == 'error') {
        api.searchResponse = response;
      }
      await tester.enterText(find.byKey(_search), 'Destination');
      if (boundary != 'debounce') {
        await tester.pump(const Duration(milliseconds: 350));
        if (boundary == 'credentials') expect(auth.nextRead, isNull);
      }
      await _replaceAccount(tester, shell);
      if (boundary == 'credentials') credential.complete('api-key');
      if (boundary == 'response') response.complete(_searchResults());
      if (boundary == 'error') {
        response.completeError(
          const WriteException(
            WriteFailure.validation,
            errors: ['Old search failure'],
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        api.searches,
        hasLength(boundary == 'response' || boundary == 'error' ? 1 : 0),
      );
      expect(find.text('Destination topic'), findsNothing);
      expect(find.text('Old search failure'), findsNothing);
      expect(find.text(_obsolete), findsOneWidget);
      expect(tester.widget<DButton>(find.byKey(_submit)).onPressed, isNull);
      // A second query still belongs to the opening session.
      final searches = api.searches.length;
      await tester.enterText(find.byKey(_search), 'Another destination');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.searches, hasLength(searches));
      expect(api.writes, isEmpty);
    });
  }

  testWidgets('search rechecks move permission after credentials', (
    tester,
  ) async {
    final api = _MoveApi();
    final auth = _GatedAuthenticator();
    final shell = await _openDialog(tester, api, auth: auth);
    await tester.tap(find.text('Existing topic'));
    await tester.pumpAndSettle();
    final credential = Completer<String?>();
    auth.nextRead = credential;
    await tester.enterText(find.byKey(_search), 'Destination');
    await tester.pump(const Duration(milliseconds: 350));
    expect(auth.nextRead, isNull);
    shell.store.put(_siteA, topicPayload(id: 7, posts: _posts).detail);
    credential.complete('a-key');
    await tester.pumpAndSettle();
    expect(api.searches, isEmpty);
    expect(find.text('Destination topic'), findsNothing);
  });

  testWidgets('new topic keeps default and creatable categories', (
    tester,
  ) async {
    final api = _MoveApi();
    await _openDialog(tester, api);
    await tester.tap(find.byKey(const ValueKey('topic-move-posts-category')));
    await tester.pumpAndSettle();
    expect(find.text('Default category'), findsWidgets);
    final menu = find.byType(DPopoverContent);
    expect(
      find.descendant(of: menu, matching: find.text('Creatable')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Unspecified permission')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Reply only')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: menu, matching: find.text('Creatable')),
    );
    await tester.pumpAndSettle();
    await _prepare(tester, newTopic: true);
    await _pressSubmit(tester);
    await tester.pumpAndSettle();
    expect(api.movedTopicPosts.single.categoryId, 10);
  });

  for (final restriction in ['all posts', 'nonregular first post']) {
    testWidgets('$restriction still allows only existing-topic moves', (
      tester,
    ) async {
      final api = _MoveApi(nonregular: restriction == 'nonregular first post');
      final shell = await _openDialog(
        tester,
        api,
        selected: restriction == 'all posts' ? [1, 2, 3] : [1],
      );
      expect(find.text('New topic'), findsNothing);
      expect(find.byKey(_search), findsOneWidget);
      await _searchDestination(tester);
      await _pressSubmit(tester);
      await tester.pumpAndSettle();
      expect(api.movedTopicPosts.single.destinationTopicId, 99);
      expect(shell.currentTopic?.id, 99);
    });
  }
}

Future<ShellController> _openDialog(
  WidgetTester tester,
  _MoveApi api, {
  _GatedAuthenticator? auth,
  List<int> selected = const [1],
}) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: _staff),
      instance('team.discourse.org', title: 'Team').copyWith(user: _staff),
    ],
    authenticator: (auth ?? _GatedAuthenticator())
      ..keys[_siteA] = 'a-key'
      ..keys[_siteB] = 'b-key',
  );
  await tester.tap(find.text('Source topic'));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(MainContent));
  final shell = ShellScope.read(context);
  _select(shell, _siteA, 7, selected);
  // Keep the caller mounted across account replacement so unmounting cannot
  // accidentally hide obsolete destination navigation from this regression.
  unawaited(
    showTopicMovePosts(
      context: context,
      controller: shell,
      siteUrl: _siteA,
      topic: shell.currentTopic!,
      selectedPosts: shell.selectedTopicPosts(_siteA, 7),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(_dialog), findsOneWidget);
  return shell;
}

void _select(ShellController shell, String site, int topicId, List<int> ids) {
  shell.setTopicPostSelectionEnabled(site, topicId, true);
  shell.clearSelectedTopicPosts(site, topicId);
  for (final id in ids) {
    shell.toggleTopicPostSelected(site, topicId, id);
  }
}

Future<void> _replaceAccount(WidgetTester tester, ShellController shell) async {
  await shell.disconnectCurrentInstance();
  await shell.connectCurrentInstance();
  shell.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
  // A pending operation keeps the dialog's spinner animating.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(shell.currentInstance?.isConnected, isTrue);
  expect(shell.currentInstance?.user?.id, 10);
  expect(shell.currentTopic?.canMovePosts, isTrue);
  _select(shell, _siteA, 7, [2]);
  expect(find.byKey(_dialog), findsOneWidget);
}

Future<void> _prepare(WidgetTester tester, {required bool newTopic}) async {
  if (newTopic) {
    await tester.enterText(find.byKey(_title), 'A new topic');
    await tester.pump();
  } else {
    await tester.tap(find.text('Existing topic'));
    await tester.pumpAndSettle();
    await _searchDestination(tester);
  }
}

Future<void> _searchDestination(WidgetTester tester) async {
  await tester.enterText(find.byKey(_search), 'Destination');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  expect(find.text('Destination topic'), findsOneWidget);
  expect(find.text('Source search hit'), findsNothing);
  expect(find.text('Private destination'), findsNothing);
  expect(find.text('Duplicate destination'), findsNothing);
}

Future<void> _pressSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(_submit));
  await tester.pump();
}

class _GatedAuthenticator extends FakeAuthenticator {
  Completer<String?>? nextRead;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final held = nextRead;
    if (held == null) return super.apiKeyFor(siteUrl);
    nextRead = null;
    return held.future;
  }
}

class _MoveApi extends FakeDiscourseApi {
  _MoveApi({this.nonregular = false})
    : super(
        user: _staff,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Source topic', slug: 'source')],
        },
        categoryList: const [
          TopicCategory(
            id: 10,
            name: 'Creatable',
            color: '008800',
            permission: 1,
          ),
          TopicCategory(
            id: 11,
            name: 'Unspecified permission',
            color: '888888',
          ),
          TopicCategory(
            id: 12,
            name: 'Reply only',
            color: '880000',
            permission: 2,
          ),
        ],
      );

  final bool nonregular;
  WriteException? moveFailure;
  Completer<String>? moveResponse;
  Completer<SearchResults>? searchResponse;
  Completer<List<Post>>? refreshResponse;
  final writes = <({String siteUrl, String apiKey})>[];
  final refreshes = <({String siteUrl, int topicId, String? apiKey})>[];
  final searches =
      <
        ({
          String siteUrl,
          String? apiKey,
          String term,
          String? typeFilter,
          bool searchForId,
          String? restrictToArchetype,
        })
      >[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'api-key'
      ? const DiscourseUser(id: 10, username: 'replacement', staff: true)
      : _staff;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    topicsOpened.add(id);
    return topicPayload(
      id: id,
      title: id == 99 ? 'Destination' : 'Source topic',
      posts: [
        if (id == 99)
          const Post(
            id: 99,
            postNumber: 1,
            username: 'destination',
            cooked: '<p>Arrived</p>',
          )
        else ...[
          if (nonregular) _nonregularPost else _posts.first,
          ..._posts.skip(1),
        ],
      ],
      canMovePosts: true,
    );
  }

  @override
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  }) async {
    searches.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      term: term,
      typeFilter: typeFilter,
      searchForId: searchForId,
      restrictToArchetype: restrictToArchetype,
    ));
    return searchResponse == null
        ? _searchResults()
        : await searchResponse!.future;
  }

  @override
  Future<String> movePosts({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    int? destinationTopicId,
    String? title,
    int? categoryId,
    List<int> tagIds = const [],
    bool chronologicalOrder = false,
    String? clientId,
  }) async {
    writes.add((siteUrl: siteUrl, apiKey: apiKey));
    if (moveFailure case final failure?) throw failure;
    await super.movePosts(
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      postIds: postIds,
      destinationTopicId: destinationTopicId,
      title: title,
      categoryId: categoryId,
      tagIds: tagIds,
      chronologicalOrder: chronologicalOrder,
    );
    return moveResponse == null
        ? '/t/destination/99'
        : await moveResponse!.future;
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
    refreshes.add((siteUrl: siteUrl, topicId: topicId, apiKey: apiKey));
    return refreshResponse == null ? [] : await refreshResponse!.future;
  }
}

SearchResults _searchResults() => SearchResults(
  hits: [
    for (final hit in [
      (id: 7, title: 'Source search hit', private: false),
      (id: 98, title: 'Private destination', private: true),
      (id: 99, title: 'Destination topic', private: false),
      (id: 99, title: 'Duplicate destination', private: false),
    ])
      SearchPostHit(
        postId: hit.id,
        topicId: hit.id,
        postNumber: 1,
        topicTitle: hit.title,
        topicSlug: 'destination',
        username: 'author',
        excerpt: const SearchExcerpt([]),
        privateMessage: hit.private,
      ),
  ],
);
