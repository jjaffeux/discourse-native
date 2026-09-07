import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_change_owner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteA = 'https://meta.discourse.org';
const _siteB = 'https://team.discourse.org';
const _guardian = DiscourseUser(
  id: 9,
  username: 'moderator',
  canChangePostOwner: true,
);
const _obsolete = 'Your connection changed. Reopen Change owner and try again.';
final _forbidden = const WriteException(WriteFailure.forbidden).message;
final _dialog = find.byKey(const ValueKey('topic-change-owner-dialog'));

void main() {
  testWidgets('single-post dialog keeps its target across colliding forums', (
    tester,
  ) async {
    final api = _OwnerApi();
    final controller = await _openDialog(tester, api);
    final otherPost = api.postFor(_siteB);
    controller.openTopicPost(siteUrl: _siteB, topicId: 7, postNumber: 1);
    await tester.pumpAndSettle();
    expect(controller.currentInstance?.url, _siteB);
    expect(controller.currentTopic?.id, 7);
    expect(controller.currentTopic?.stream, contains(1));
    expect(_dialog, findsOneWidget);

    await _submit(tester);

    expect(api.writes.where((write) => write.siteUrl == _siteB), isEmpty);
    expect(
      api.writes.map(
        (write) => (write.siteUrl, write.apiKey, write.topicId, write.username),
      ),
      [(_siteA, 'a-key', 7, 'recipient')],
    );
    expect(api.writes.single.postIds, [1]);
    _expectRefresh(api, [1]);
    expect(controller.store.read<Post>(_siteB, 1), same(otherPost));
    expect(controller.store.read<Post>(_siteA, 1)?.username, 'recipient');
    expect(_dialog, findsNothing);
  });

  testWidgets(
    'single-post dialog retains the topic after same-site navigation',
    (tester) async {
      final api = _OwnerApi();
      final controller = await _openDialog(tester, api);
      controller.openTopicPost(siteUrl: _siteA, topicId: 9, postNumber: 1);
      await tester.pumpAndSettle();
      expect(controller.currentTopic?.id, 9);

      await _submit(tester);

      expect(api.writes.single.topicId, 7);
      _expectRefresh(api, [1]);
      expect(_dialog, findsNothing);
    },
  );

  for (final afterCredentials in [false, true]) {
    final boundary = afterCredentials ? 'after credentials' : 'before submit';
    for (final change in [
      'permission',
      'topic membership',
      'stored post',
      'stored topic',
      'current owner',
    ]) {
      testWidgets('single-post rechecks original $change $boundary', (
        tester,
      ) async {
        final api = _OwnerApi();
        final auth = _GatedAuthenticator();
        final controller = await _openDialog(tester, api, authenticator: auth);
        controller.openTopicPost(siteUrl: _siteB, topicId: 7, postNumber: 1);
        await tester.pumpAndSettle();
        final credential = Completer<String?>();
        if (afterCredentials) {
          auth.nextRead = credential;
          await _pressSubmit(tester);
          expect(auth.nextRead, isNull);
        }
        switch (change) {
          case 'permission':
            _revokePermission(controller);
          case 'topic membership':
            controller.store.update<TopicDetail>(
              _siteA,
              7,
              (topic) => topic.withoutPostId(1),
            );
          case 'stored post':
            controller.store.remove<Post>(_siteA, 1);
          case 'stored topic':
            controller.store.remove<TopicDetail>(_siteA, 7);
          case 'current owner':
            controller.store.put(_siteA, _postWithOwner('recipient'));
        }
        expect(controller.currentInstance?.user?.canChangePostOwner, isTrue);
        expect(controller.currentTopic?.stream, contains(1));
        if (afterCredentials) {
          credential.complete('a-key');
          await tester.pumpAndSettle();
        } else {
          await _submit(tester);
        }

        expect(api.writes, isEmpty);
        expect(api.refreshes, isEmpty);
        expect(find.text(_forbidden), findsOneWidget);
        expect(_dialog, findsOneWidget);
        expect(controller.postWriteInFlight(1, siteUrl: _siteA), isFalse);
      });
    }
  }

  for (final selected in [false, true]) {
    final mode = selected ? 'selected-post' : 'single-post';
    testWidgets('$mode dialog rejects a replacement account', (tester) async {
      final api = _OwnerApi();
      final controller = await _openDialog(tester, api, selected: selected);
      await controller.disconnectCurrentInstance();
      await controller.connectCurrentInstance();
      controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
      await tester.pumpAndSettle();
      expect(controller.currentInstance?.user?.id, 10);
      expect(controller.currentInstance?.user?.canChangePostOwner, isTrue);
      if (selected) _selectPosts(controller);

      await _submit(tester);

      expect(api.writes, isEmpty);
      expect(api.refreshes, isEmpty);
      expect(find.text(_obsolete), findsOneWidget);
      expect(_dialog, findsOneWidget);
    });

    testWidgets('$mode rechecks account replacement after credentials', (
      tester,
    ) async {
      final api = _OwnerApi();
      final auth = _GatedAuthenticator();
      final controller = await _openDialog(
        tester,
        api,
        selected: selected,
        authenticator: auth,
      );
      final credential = Completer<String?>();
      auth.nextRead = credential;
      await _pressSubmit(tester);
      expect(auth.nextRead, isNull);
      await controller.disconnectCurrentInstance();
      await controller.connectCurrentInstance();
      controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
      await tester.pump();
      if (selected) _selectPosts(controller);
      credential.complete('api-key');
      await tester.pumpAndSettle();

      expect(api.writes, isEmpty);
      expect(api.refreshes, isEmpty);
      expect(find.text(_obsolete), findsOneWidget);
      expect(_dialog, findsOneWidget);
    });

    testWidgets('$mode search cannot adopt a replacement account', (
      tester,
    ) async {
      final api = _OwnerApi();
      final controller = await _openDialog(tester, api, selected: selected);
      expect(api.userSearchesRequested, hasLength(1));
      await tester.enterText(
        find.byKey(const ValueKey('topic-change-owner-search')),
        'another recipient',
      );
      await controller.disconnectCurrentInstance();
      await controller.connectCurrentInstance();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(api.userSearchesRequested, hasLength(1));
      expect(api.writes, isEmpty);
      expect(find.text('Recipient'), findsNothing);
    });

    for (final pending in ['write', 'refresh']) {
      testWidgets(
        '$mode $pending completion cannot update a replacement session',
        (tester) async {
          final api = _OwnerApi();
          final controller = await _openDialog(tester, api, selected: selected);
          final write = Completer<void>();
          final refresh = Completer<List<Post>>();
          if (pending == 'write') {
            api.ownerWriteGate = write;
          } else {
            api.ownerRefreshGate = refresh;
          }
          await _pressSubmit(tester);
          expect(api.writes, hasLength(1));
          expect(api.writes.single.apiKey, 'a-key');
          expect(api.refreshes, hasLength(pending == 'write' ? 0 : 1));

          await controller.disconnectCurrentInstance();
          await controller.connectCurrentInstance();
          controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
          await tester.pump();
          expect(controller.currentInstance?.user?.id, 10);
          final replacementPost = controller.store.read<Post>(_siteA, 1);
          expect(replacementPost, isNotNull);
          if (selected) _selectPosts(controller);
          if (pending == 'write') {
            write.complete();
          } else {
            refresh.complete([_postWithOwner('stale refresh')]);
          }
          await tester.pumpAndSettle();

          expect(api.writes, hasLength(1));
          expect(api.refreshes, hasLength(pending == 'write' ? 0 : 1));
          expect(controller.store.read<Post>(_siteA, 1), same(replacementPost));
          if (selected) {
            expect(controller.selectedTopicPostIds(_siteA, 7), {1, 2});
          }
          expect(find.text(_obsolete), findsOneWidget);
          expect(_dialog, findsOneWidget);
        },
      );
    }

    for (final afterCredentials in [false, true]) {
      testWidgets(
        '$mode rejects disposal ${afterCredentials ? 'after credentials' : 'before submit'}',
        (tester) async {
          final api = _OwnerApi();
          final auth = _GatedAuthenticator();
          final controller = await _openStandaloneDialog(
            tester,
            api,
            auth,
            selected: selected,
          );
          final credential = Completer<String?>();
          if (afterCredentials) {
            auth.nextRead = credential;
            await _pressSubmit(tester);
            expect(auth.nextRead, isNull);
          }
          controller.dispose();
          if (afterCredentials) {
            credential.complete('a-key');
            await tester.pumpAndSettle();
          } else {
            await _submit(tester);
          }

          expect(api.writes, isEmpty);
          expect(api.refreshes, isEmpty);
          expect(find.text(_obsolete), findsOneWidget);
          expect(_dialog, findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$mode preserves errors, retries and refreshes on success', (
      tester,
    ) async {
      final api = _OwnerApi()
        ..ownerFailure = const WriteException(
          WriteFailure.validation,
          errors: ['Owner changes are temporarily disabled.'],
        );
      final controller = await _openDialog(tester, api, selected: selected);
      final ids = selected ? [1, 2] : [1];

      await _submit(tester);

      expect(
        find.text('Owner changes are temporarily disabled.'),
        findsOneWidget,
      );
      expect(_dialog, findsOneWidget);
      expect(api.writes.single.postIds, ids);
      expect(api.refreshes, isEmpty);
      expect(controller.store.read<Post>(_siteA, 1)?.username, 'author');
      expect(controller.postWriteInFlight(1, siteUrl: _siteA), isFalse);
      expect(controller.topicPostSelectionWriteInFlight(_siteA, 7), isFalse);
      if (selected) {
        expect(controller.selectedTopicPostIds(_siteA, 7), {1, 2});
      }
      api.ownerFailure = null;

      await _submit(tester);

      expect(api.writes, hasLength(2));
      expect(api.writes.last.postIds, ids);
      expect(api.writes.last.apiKey, 'a-key');
      _expectRefresh(api, ids);
      for (final id in ids) {
        expect(controller.store.read<Post>(_siteA, id)?.username, 'recipient');
        expect(controller.postWriteInFlight(id, siteUrl: _siteA), isFalse);
      }
      expect(controller.topicPostSelectionEnabled(_siteA, 7), isFalse);
      expect(_dialog, findsNothing);
    });
  }

  for (final afterCredentials in [false, true]) {
    for (final change in [
      'permission',
      'selection permission',
      'mixed authors',
    ]) {
      testWidgets(
        'selected-post rechecks $change ${afterCredentials ? 'after credentials' : 'before submit'}',
        (tester) async {
          final api = _OwnerApi();
          final auth = _GatedAuthenticator();
          final controller = await _openDialog(
            tester,
            api,
            selected: true,
            authenticator: auth,
          );
          final credential = Completer<String?>();
          if (afterCredentials) {
            auth.nextRead = credential;
            await _pressSubmit(tester);
            expect(auth.nextRead, isNull);
          }
          switch (change) {
            case 'permission':
              _revokePermission(controller);
            case 'selection permission':
              controller.store.put(
                _siteA,
                topicPayload(
                  id: 7,
                  posts: [api.postFor(_siteA), api.postFor(_siteA, 2)],
                ).detail,
              );
            case 'mixed authors':
              controller.store.put(_siteA, _postWithOwner('different'));
          }
          if (afterCredentials) {
            credential.complete('a-key');
            await tester.pumpAndSettle();
          } else {
            await _submit(tester);
          }

          expect(api.writes, isEmpty);
          expect(api.refreshes, isEmpty);
          expect(find.text(_forbidden), findsOneWidget);
          expect(_dialog, findsOneWidget);
          expect(controller.selectedTopicPostIds(_siteA, 7), {1, 2});
          expect(
            controller.topicPostSelectionWriteInFlight(_siteA, 7),
            isFalse,
          );
        },
      );
    }
  }

  testWidgets('selected-post mode reads the current selection on submit', (
    tester,
  ) async {
    final api = _OwnerApi();
    final controller = await _openDialog(tester, api, selected: true);
    controller.toggleTopicPostSelected(_siteA, 7, 1);

    await _submit(tester);

    expect(api.writes.single.postIds, [2]);
    expect(controller.store.read<Post>(_siteA, 1)?.username, 'author');
    expect(controller.store.read<Post>(_siteA, 2)?.username, 'recipient');
    expect(controller.topicPostSelectionEnabled(_siteA, 7), isFalse);
  });

  testWidgets('selected-post mode still requires its forum to be active', (
    tester,
  ) async {
    final api = _OwnerApi();
    final controller = await _openDialog(tester, api, selected: true);
    controller.openTopicPost(siteUrl: _siteB, topicId: 7, postNumber: 1);
    await tester.pumpAndSettle();

    await _submit(tester);

    expect(api.writes, isEmpty);
    expect(find.text(_forbidden), findsOneWidget);
    expect(controller.selectedTopicPostIds(_siteA, 7), {1, 2});
  });
}

void _expectRefresh(_OwnerApi api, List<int> ids) {
  expect(api.refreshes.map((refresh) => (refresh.siteUrl, refresh.topicId)), [
    (_siteA, 7),
  ]);
  expect(api.refreshes.single.ids, ids);
}

Post _postWithOwner(String username) => Post(
  id: 1,
  postNumber: 1,
  userId: 12,
  username: username,
  cooked: '<p>Owned body 1</p>',
);

void _revokePermission(ShellController controller) {
  controller.applyAccountSessionInstance(
    controller
        .accountSessionInstance(_siteA)!
        .copyWith(user: const DiscourseUser(id: 9, username: 'moderator')),
    AccountSessionPhase.connecting,
  );
}

void _selectPosts(ShellController controller) {
  controller.setTopicPostSelectionEnabled(_siteA, 7, true);
  controller.selectAllLoadedTopicPosts(_siteA, 7);
}

Future<ShellController> _openDialog(
  WidgetTester tester,
  _OwnerApi api, {
  bool selected = false,
  FakeAuthenticator? authenticator,
}) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: _guardian),
      instance('team.discourse.org', title: 'Team').copyWith(user: _guardian),
    ],
    authenticator: (authenticator ?? FakeAuthenticator())
      ..keys[_siteA] = 'a-key'
      ..keys[_siteB] = 'b-key',
  );
  await tester.tap(find.text('A real topic'));
  await tester.pumpAndSettle();
  final controller = ShellScope.read(tester.element(find.byType(MainContent)));
  if (selected) {
    _selectPosts(controller);
    await tester.pumpAndSettle();
    final action = find.byKey(
      const ValueKey('topic-selected-posts-change-owner'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
  } else {
    await hoverPost(tester, body: 'Owned body 1');
    await tapPostAction(tester, 'Assign this post to another account');
  }
  await tester.pumpAndSettle();
  await _chooseRecipient(tester);
  return controller;
}

Future<ShellController> _openStandaloneDialog(
  WidgetTester tester,
  _OwnerApi api,
  FakeAuthenticator auth, {
  required bool selected,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _guardian),
    ]),
    api: api,
    authenticator: auth..keys[_siteA] = 'a-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    if (!controller.accountSessionDisposed) controller.dispose();
  });
  await controller.load();
  controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
  await tester.pumpAndSettle();
  if (selected) _selectPosts(controller);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            showTopicChangeOwner(
              context: context,
              controller: controller,
              siteUrl: _siteA,
              topicId: 7,
              selectedPosts: [
                api.postFor(_siteA),
                if (selected) api.postFor(_siteA, 2),
              ],
              usesTopicSelection: selected,
            ),
          ),
          child: const Text('Open owner dialog'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open owner dialog'));
  await tester.pumpAndSettle();
  await _chooseRecipient(tester);
  return controller;
}

Future<void> _chooseRecipient(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('topic-change-owner-search')),
    'recipient',
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  expect(find.text('Recipient'), findsOneWidget);
}

Future<void> _submit(WidgetTester tester) async {
  await _pressSubmit(tester);
  await tester.pumpAndSettle();
}

Future<void> _pressSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
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

class _OwnerApi extends FakeDiscourseApi {
  _OwnerApi()
    : super(
        user: _guardian,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
        userSearches: const {
          'recipient': [FoundUser(username: 'recipient', name: 'Recipient')],
        },
      );

  final _posts = <String, Map<int, Post>>{
    for (final site in [_siteA, _siteB])
      site: {
        for (final id in [1, 2])
          id: Post(
            id: id,
            postNumber: id,
            userId: 7,
            username: 'author',
            cooked: '<p>Owned body $id</p>',
          ),
      },
  };
  final writes =
      <
        ({
          String siteUrl,
          String apiKey,
          int topicId,
          List<int> postIds,
          String username,
        })
      >[];
  final refreshes = <({String siteUrl, int topicId, List<int> ids})>[];
  Object? ownerFailure;
  Completer<void>? ownerWriteGate;
  Completer<List<Post>>? ownerRefreshGate;

  Post postFor(String siteUrl, [int id = 1]) => _posts[siteUrl]![id]!;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'api-key'
      ? const DiscourseUser(
          id: 10,
          username: 'replacement',
          canChangePostOwner: true,
        )
      : _guardian;

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
    title: 'A real topic',
    posts: _posts[siteUrl]!.values.toList(),
    canSplitMergeTopic: true,
  );

  @override
  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      postIds: List.of(postIds),
      username: username,
    ));
    await ownerWriteGate?.future;
    final failure = ownerFailure;
    if (failure != null) throw failure;
    for (final id in postIds) {
      _posts[siteUrl]![id] = Post(
        id: id,
        postNumber: id,
        userId: 12,
        username: username,
        cooked: postFor(siteUrl, id).cooked,
      );
    }
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
    refreshes.add((siteUrl: siteUrl, topicId: topicId, ids: List.of(ids)));
    if (ownerRefreshGate case final gate?) return gate.future;
    return [for (final id in ids) postFor(siteUrl, id)];
  }
}
