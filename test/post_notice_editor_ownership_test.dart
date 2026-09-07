import 'dart:async';

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

const _siteA = 'https://meta.discourse.org';
const _siteB = 'https://team.discourse.org';
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);

void main() {
  for (final delete in [false, true]) {
    final action = delete ? 'delete' : 'save';

    testWidgets('$action stays on the opening forum after navigation', (
      tester,
    ) async {
      final api = _NoticeApi();
      final controller = await _openEditor(tester, api);
      final otherPost = api.postFor(_siteB);
      controller.openTopicPost(siteUrl: _siteB, topicId: 9, postNumber: 1);
      await tester.pumpAndSettle();
      expect(controller.currentInstance?.url, _siteB);
      expect(controller.currentTopic?.stream, contains(1));
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsOneWidget);

      await _submit(tester, delete: delete);

      expect(api.writes, [
        (
          siteUrl: _siteA,
          apiKey: 'a-key',
          postId: 1,
          notice: delete ? null : 'Updated notice',
        ),
      ]);
      expect(api.refreshes, [(siteUrl: _siteA, topicId: 7)]);
      expect(controller.store.read<Post>(_siteB, 1), same(otherPost));
      expect(
        controller.store.read<Post>(_siteA, 1)?.notice?.raw,
        delete ? isNull : 'Updated notice',
      );
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
    });

    testWidgets('$action rejects an editor opened before reconnecting', (
      tester,
    ) async {
      final api = _NoticeApi();
      final controller = await _openEditor(tester, api);
      await controller.disconnectCurrentInstance();
      await controller.connectCurrentInstance();
      controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
      await tester.pumpAndSettle();
      expect(controller.currentInstance?.isConnected, isTrue);
      expect(controller.currentInstance?.user?.id, 10);
      expect(controller.currentTopic?.canEditStaffNotes, isTrue);
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsOneWidget);

      await _submit(tester, delete: delete);

      expect(api.writes, isEmpty);
      expect(api.refreshes, isEmpty);
      expect(
        find.text(
          'Your connection changed. Reopen the post notice and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsOneWidget);
    });

    for (final change in ['permission', 'topic membership', 'stored post']) {
      testWidgets('$action rechecks the original $change after navigation', (
        tester,
      ) async {
        final api = _NoticeApi();
        final controller = await _openEditor(tester, api);
        controller.openTopicPost(siteUrl: _siteB, topicId: 9, postNumber: 1);
        await tester.pumpAndSettle();
        switch (change) {
          case 'permission':
            controller.store.put(
              _siteA,
              topicPayload(id: 7, posts: [api.postFor(_siteA)]).detail,
            );
          case 'topic membership':
            controller.store.update<TopicDetail>(
              _siteA,
              7,
              (topic) => topic.withoutPostId(1),
            );
          case 'stored post':
            controller.store.remove<Post>(_siteA, 1);
        }
        expect(controller.currentTopic?.canEditStaffNotes, isTrue);
        expect(controller.currentTopic?.stream, contains(1));

        await _submit(tester, delete: delete);

        expect(api.writes, isEmpty);
        expect(api.refreshes, isEmpty);
        expect(
          find.text('This post notice can no longer be edited.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('post-notice-dialog')),
          findsOneWidget,
        );
      });
    }

    testWidgets('$action compares the current stored notice', (tester) async {
      final api = _NoticeApi();
      final controller = await _openEditor(tester, api);
      controller.store.put(
        _siteA,
        api
            .postFor(_siteA)
            .copyWith(
              notice: delete
                  ? null
                  : const PostNotice(type: 'custom', raw: 'Updated notice'),
              clearNotice: delete,
            ),
      );

      await _submit(tester, delete: delete);

      expect(api.writes, isEmpty);
      expect(api.refreshes, isEmpty);
      expect(find.byKey(const ValueKey('post-notice-dialog')), findsNothing);
    });
  }

  for (final reconnect in [false, true]) {
    testWidgets(
      'save rechecks ${reconnect ? 'the account' : 'permission'} after credentials',
      (tester) async {
        final api = _NoticeApi();
        final auth = _GatedAuthenticator();
        final controller = await _openEditor(tester, api, authenticator: auth);
        final credential = Completer<String?>();
        auth.nextRead = credential;
        await _pressSubmit(tester, delete: false);
        expect(auth.nextRead, isNull);

        if (reconnect) {
          await controller.disconnectCurrentInstance();
          await controller.connectCurrentInstance();
          controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
          expect(controller.currentInstance?.user?.id, 10);
        } else {
          controller.store.put(
            _siteA,
            topicPayload(id: 7, posts: [api.postFor(_siteA)]).detail,
          );
        }
        credential.complete(reconnect ? 'api-key' : 'a-key');
        await tester.pumpAndSettle();

        expect(api.writes, isEmpty);
        expect(api.refreshes, isEmpty);
        expect(
          find.text(
            reconnect
                ? 'Your connection changed. Reopen the post notice and try again.'
                : 'This post notice can no longer be edited.',
          ),
          findsOneWidget,
        );
      },
    );
  }
}

Future<ShellController> _openEditor(
  WidgetTester tester,
  _NoticeApi api, {
  FakeAuthenticator? authenticator,
}) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: _staff),
      instance('team.discourse.org', title: 'Team').copyWith(user: _staff),
    ],
    authenticator: (authenticator ?? FakeAuthenticator())
      ..keys[_siteA] = 'a-key'
      ..keys[_siteB] = 'b-key',
  );
  await tester.tap(find.text('A real topic'));
  await tester.pumpAndSettle();
  final controller = ShellScope.read(tester.element(find.byType(MainContent)));
  await hoverPost(tester, body: 'Noticeable body');
  await tapPostAction(tester, 'Change or remove the staff notice');
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _submit(WidgetTester tester, {required bool delete}) async {
  await _pressSubmit(tester, delete: delete);
  await tester.pumpAndSettle();
}

Future<void> _pressSubmit(WidgetTester tester, {required bool delete}) async {
  if (!delete) {
    await tester.enterText(
      find.byKey(const ValueKey('post-notice-text')),
      'Updated notice',
    );
    await tester.pump();
  }
  await tester.tap(
    find.byKey(ValueKey('post-notice-${delete ? 'delete' : 'save'}')),
  );
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

class _NoticeApi extends FakeDiscourseApi {
  _NoticeApi()
    : super(
        user: _staff,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
      );

  final _posts = <String, Post>{
    for (final site in [_siteA, _siteB])
      site: Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'author',
        cooked: '<p>Noticeable body</p>',
        notice: PostNotice(type: 'custom', raw: 'Original notice on $site'),
      ),
  };
  final writes =
      <({String siteUrl, String apiKey, int postId, String? notice})>[];
  final refreshes = <({String siteUrl, int topicId})>[];

  Post postFor(String siteUrl) => _posts[siteUrl]!;

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
  }) async => topicPayload(
    id: id,
    title: 'A real topic',
    posts: [postFor(siteUrl)],
    canEditStaffNotes: true,
  );

  @override
  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      postId: postId,
      notice: notice,
    ));
    _posts[siteUrl] = postFor(siteUrl).copyWith(
      notice: notice == null ? null : PostNotice(type: 'custom', raw: notice),
      clearNotice: notice == null,
    );
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
    refreshes.add((siteUrl: siteUrl, topicId: topicId));
    return [postFor(siteUrl)];
  }
}
