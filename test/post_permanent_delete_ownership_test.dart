import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_permanent_delete.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteA = 'https://meta.discourse.org';
const _siteB = 'https://team.discourse.org';
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);
const _obsolete = 'Your connection changed. Reopen the action and try again.';
const _forbidden = 'This post cannot be permanently deleted.';
const _dialogKey = ValueKey('post-permanent-delete-dialog');
const _confirmationKey = ValueKey('post-permanent-delete-confirmation');
const _submitKey = ValueKey('post-permanent-delete-submit');
typedef _CheckResult = ({bool allowed, String? reason});

void main() {
  for (final postId in [1, 2]) {
    final targetName = postId == 1 ? 'topic' : 'reply';

    testWidgets(
      '$targetName deletion requires the existing phrase and succeeds',
      (tester) async {
        final api = _DeletionApi();
        final controller = await _openTopic(tester, api);
        await tapPostAction(
          tester,
          'Permanently delete this post',
          postNumber: postId,
        );
        await tester.pumpAndSettle();
        expect(api.checks, [
          (siteUrl: _siteA, apiKey: 'a-key', postId: postId),
        ]);
        expect(
          find.text('Permanently delete ${postId == 1 ? 'topic' : 'post'}?'),
          findsOneWidget,
        );
        expect(
          tester.widget<DButton>(find.byKey(_submitKey)).onPressed,
          isNull,
        );
        await tester.enterText(find.byKey(_confirmationKey), 'delete');
        await tester.pump();
        expect(
          tester.widget<DButton>(find.byKey(_submitKey)).onPressed,
          isNull,
        );

        await _submit(tester);
        await tester.pumpAndSettle();

        _expectOriginalWrite(api, postId);
        expect(find.byKey(_dialogKey), findsNothing);
        expect(controller.store.read<Post>(_siteA, postId), isNull);
        expect(_writeInFlight(controller, postId), isFalse);
        if (postId == 1) {
          expect(controller.store.read<Post>(_siteA, 2), isNull);
          expect(controller.store.read<TopicDetail>(_siteA, 7), isNull);
          expect(controller.currentContent?.topicId, isNull);
        } else {
          expect(controller.store.read<Post>(_siteA, 1), isNotNull);
          expect(controller.currentTopic?.stream, [1]);
          expect(controller.currentContent?.topicId, 7);
        }
      },
    );

    for (final stage in ['check', 'confirmation', 'write']) {
      testWidgets('$targetName stays on the opening forum during $stage', (
        tester,
      ) async {
        final api = _DeletionApi();
        final controller = await _openTopic(tester, api);
        final check = Completer<_CheckResult>();
        final write = Completer<void>();
        if (stage == 'check') api.nextCheck = check;
        if (stage == 'write') api.nextWrite = write;
        _showConfirmation(tester, controller, api, postId);
        await tester.pumpAndSettle();
        if (stage == 'write') await _submit(tester);

        controller.openTopicPost(
          siteUrl: _siteB,
          topicId: 7,
          postNumber: postId,
        );
        if (stage == 'write') {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
        expect(controller.currentInstance?.url, _siteB);
        expect(controller.currentTopic?.stream, contains(postId));
        final otherTopic = controller.currentTopic;
        final otherPost = controller.store.read<Post>(_siteB, postId);

        if (stage == 'check') {
          check.complete((allowed: true, reason: null));
          await tester.pumpAndSettle();
        }
        if (stage == 'write') {
          write.complete();
        } else {
          expect(find.byKey(_dialogKey), findsOneWidget);
          await _submit(tester);
        }
        await tester.pumpAndSettle();

        _expectOriginalWrite(api, postId);
        expect(api.checks, [
          (siteUrl: _siteA, apiKey: 'a-key', postId: postId),
        ]);
        expect(controller.currentInstance?.url, _siteB);
        expect(controller.currentContent?.topicId, 7);
        expect(controller.currentTopic, same(otherTopic));
        expect(controller.store.read<Post>(_siteB, postId), same(otherPost));
        expect(find.byKey(_dialogKey), findsNothing);
      });
    }

    for (final stage in ['check', 'confirmation', 'credential']) {
      testWidgets('$targetName refuses a replacement account during $stage', (
        tester,
      ) async {
        final api = _DeletionApi();
        final auth = _GatedAuthenticator();
        final controller = await _openTopic(tester, api, authenticator: auth);
        final check = Completer<_CheckResult>();
        final credential = Completer<String?>();
        if (stage == 'check') api.nextCheck = check;
        _showConfirmation(tester, controller, api, postId);
        await tester.pumpAndSettle();
        if (stage == 'credential') {
          auth.nextRead = credential;
          await _submit(tester);
          expect(auth.nextRead, isNull);
        }

        await _replaceAccount(controller);
        if (stage == 'check') {
          check.complete((allowed: true, reason: null));
        } else if (stage == 'credential') {
          credential.complete('api-key');
        } else {
          await tester.pumpAndSettle();
          auth.reads.clear();
          await _submit(tester);
          expect(auth.reads, isEmpty);
        }
        await tester.pumpAndSettle();

        expect(api.topicDeletes, isEmpty);
        expect(api.postDeletes, isEmpty);
        expect(api.refreshes, isEmpty);
        expect(find.text(_obsolete), findsOneWidget);
        expect(
          find.byKey(_dialogKey),
          stage == 'check' ? findsNothing : findsOneWidget,
        );
      });
    }

    for (final stage in ['check', 'confirmation', 'credential']) {
      for (final change in ['permission', 'membership', 'post']) {
        testWidgets('$targetName rechecks original $change after $stage', (
          tester,
        ) async {
          final api = _DeletionApi();
          final auth = _GatedAuthenticator();
          final controller = await _openTopic(tester, api, authenticator: auth);
          final check = Completer<_CheckResult>();
          final credential = Completer<String?>();
          if (stage == 'check') api.nextCheck = check;
          _showConfirmation(tester, controller, api, postId);
          await tester.pumpAndSettle();
          controller.openTopicPost(
            siteUrl: _siteB,
            topicId: 7,
            postNumber: postId,
          );
          await tester.pumpAndSettle();
          if (stage == 'credential') {
            auth.nextRead = credential;
            await _submit(tester);
            expect(auth.nextRead, isNull);
          }
          switch (change) {
            case 'permission':
              if (postId == 1) {
                controller.store.put(
                  _siteA,
                  api.payload(_siteA, canDelete: false).detail,
                );
              } else {
                controller.store.put(
                  _siteA,
                  api.post(_siteA, 2, canDelete: false),
                );
              }
            case 'membership':
              controller.store.update<TopicDetail>(
                _siteA,
                7,
                (topic) => topic.withoutPostId(postId),
              );
            case 'post':
              controller.store.remove<Post>(_siteA, postId);
          }
          expect(
            controller.canPermanentlyDeletePost(api.post(_siteB, postId)),
            isTrue,
          );

          if (stage == 'check') {
            check.complete((allowed: true, reason: null));
          } else if (stage == 'credential') {
            credential.complete('a-key');
          } else {
            await _submit(tester);
          }
          await tester.pumpAndSettle();

          expect(api.topicDeletes, isEmpty);
          expect(api.postDeletes, isEmpty);
          expect(api.refreshes, isEmpty);
          expect(find.text(_forbidden), findsOneWidget);
          expect(
            find.byKey(_dialogKey),
            stage == 'check' ? findsNothing : findsOneWidget,
          );
          expect(_writeInFlight(controller, postId), isFalse);
        });
      }
    }

    testWidgets('$targetName surfaces the server check refusal', (
      tester,
    ) async {
      final api = _DeletionApi()
        ..checkResult = (allowed: false, reason: 'Wait five minutes.');
      final controller = await _openTopic(tester, api);
      _showConfirmation(tester, controller, api, postId);
      await tester.pumpAndSettle();

      expect(find.text('Wait five minutes.'), findsOneWidget);
      expect(find.byKey(_dialogKey), findsNothing);
      expect(api.topicDeletes, isEmpty);
      expect(api.postDeletes, isEmpty);
    });

    testWidgets('$targetName surfaces a failed deletion and permits retry', (
      tester,
    ) async {
      final api = _DeletionApi();
      final controller = await _openTopic(tester, api);
      _showConfirmation(tester, controller, api, postId);
      await tester.pumpAndSettle();
      api.deletionFailure = const WriteException(WriteFailure.forbidden);

      await _submit(tester);
      await tester.pumpAndSettle();

      expect(find.text(api.deletionFailure!.message), findsOneWidget);
      expect(find.byKey(_dialogKey), findsOneWidget);
      expect(controller.store.read<Post>(_siteA, postId), isNotNull);
      expect(api.refreshes, isEmpty);
      expect(_writeInFlight(controller, postId), isFalse);
      api.deletionFailure = null;
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(_dialogKey), findsNothing);
      expect(controller.store.read<Post>(_siteA, postId), isNull);
    });

    testWidgets(
      '$targetName obsolete completion preserves a replacement write',
      (tester) async {
        final api = _DeletionApi();
        final controller = await _openTopic(tester, api);
        _showConfirmation(tester, controller, api, postId);
        await tester.pumpAndSettle();
        final oldWrite = Completer<void>();
        api.nextWrite = oldWrite;
        await _submit(tester);
        expect(_writeInFlight(controller, postId), isTrue);

        await _replaceAccount(controller);
        await tester.pump();
        final replacementPost = controller.store.read<Post>(_siteA, postId);
        _showConfirmation(tester, controller, api, postId);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final newWrite = Completer<void>();
        api.nextWrite = newWrite;
        await _submit(tester);
        expect(_writeInFlight(controller, postId), isTrue);

        oldWrite.complete();
        await tester.pump();
        expect(_writeInFlight(controller, postId), isTrue);
        expect(
          controller.store.read<Post>(_siteA, postId),
          same(replacementPost),
        );
        expect(controller.currentContent?.topicId, 7);
        expect(api.refreshes, isEmpty);

        newWrite.complete();
        await tester.pumpAndSettle();
        expect(_writeInFlight(controller, postId), isFalse);
        expect(find.text(_obsolete), findsOneWidget);
        expect(api.topicDeletes.length + api.postDeletes.length, 2);
      },
    );
  }

  for (final change in ['account', 'permission']) {
    testWidgets('topic deletion rechecks $change after reading the client ID', (
      tester,
    ) async {
      final api = _DeletionApi();
      final auth = _GatedAuthenticator();
      final controller = await _openTopic(tester, api, authenticator: auth);
      _showConfirmation(tester, controller, api, 1);
      await tester.pumpAndSettle();
      final clientId = Completer<String>();
      auth.nextClientId = clientId;
      await _submit(tester);
      expect(auth.nextClientId, isNull);
      if (change == 'account') {
        await _replaceAccount(controller);
      } else {
        controller.store.put(
          _siteA,
          api.payload(_siteA, canDelete: false).detail,
        );
      }
      clientId.complete('test-client');
      await tester.pumpAndSettle();

      expect(api.topicDeletes, isEmpty);
      expect(
        find.text(change == 'account' ? _obsolete : _forbidden),
        findsOneWidget,
      );
    });
  }

  testWidgets('reply refresh cannot remove a replacement account post', (
    tester,
  ) async {
    final api = _DeletionApi();
    final controller = await _openTopic(tester, api);
    _showConfirmation(tester, controller, api, 2);
    await tester.pumpAndSettle();
    final refresh = Completer<List<Post>>();
    api.nextRefresh = refresh;
    await _submit(tester);
    expect(api.refreshes, hasLength(1));

    await _replaceAccount(controller);
    await tester.pump();
    final replacementPost = controller.store.read<Post>(_siteA, 2);
    refresh.complete([]);
    await tester.pumpAndSettle();

    expect(controller.store.read<Post>(_siteA, 2), same(replacementPost));
    expect(controller.currentTopic?.stream, contains(2));
    expect(find.text(_obsolete), findsOneWidget);
    expect(find.byKey(_dialogKey), findsOneWidget);
  });
}

Future<ShellController> _openTopic(
  WidgetTester tester,
  _DeletionApi api, {
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
  return ShellScope.read(tester.element(find.byType(MainContent)));
}

void _showConfirmation(
  WidgetTester tester,
  ShellController controller,
  _DeletionApi api,
  int postId,
) {
  // Keep the caller mounted while navigation overlaps the initial check.
  unawaited(
    showPostPermanentDelete(
      context: tester.element(find.byType(MainContent)),
      controller: controller,
      siteUrl: _siteA,
      topicId: 7,
      post: api.post(_siteA, postId),
    ),
  );
}

Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(_confirmationKey).last,
    '  PERMANENTLY DELETE  ',
  );
  await tester.pump();
  await tester.tap(find.byKey(_submitKey).last);
  await tester.pump();
}

Future<void> _replaceAccount(ShellController controller) async {
  await controller.disconnectCurrentInstance();
  await controller.connectCurrentInstance();
  controller.openTopicPost(siteUrl: _siteA, topicId: 7, postNumber: 1);
  expect(controller.currentInstance?.user?.id, 10);
}

bool _writeInFlight(ShellController controller, int postId) => postId == 1
    ? controller.topicDeletionWriteInFlight(_siteA, 7)
    : controller.postWriteInFlight(postId, siteUrl: _siteA);

void _expectOriginalWrite(_DeletionApi api, int postId) {
  if (postId == 1) {
    expect(api.topicDeletes, [(siteUrl: _siteA, apiKey: 'a-key', topicId: 7)]);
    expect(api.postDeletes, isEmpty);
    expect(api.refreshes, isEmpty);
  } else {
    expect(api.postDeletes, [
      (siteUrl: _siteA, apiKey: 'a-key', topicId: 7, postId: postId),
    ]);
    expect(api.topicDeletes, isEmpty);
    expect(api.refreshes, [(siteUrl: _siteA, apiKey: 'a-key', topicId: 7)]);
  }
}

class _GatedAuthenticator extends FakeAuthenticator {
  Completer<String?>? nextRead;
  Completer<String>? nextClientId;
  final reads = <String>[];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads.add(siteUrl);
    final held = nextRead;
    if (held == null) return super.apiKeyFor(siteUrl);
    nextRead = null;
    return held.future;
  }

  @override
  Future<String> clientId() {
    final held = nextClientId;
    if (held == null) return super.clientId();
    nextClientId = null;
    return held.future;
  }
}

class _DeletionApi extends FakeDiscourseApi {
  _DeletionApi()
    : super(
        user: _staff,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
      );

  Completer<_CheckResult>? nextCheck;
  Completer<void>? nextWrite;
  Completer<List<Post>>? nextRefresh;
  _CheckResult checkResult = (allowed: true, reason: null);
  WriteException? deletionFailure;
  final checks = <({String siteUrl, String apiKey, int postId})>[];
  final topicDeletes = <({String siteUrl, String apiKey, int topicId})>[];
  final postDeletes =
      <({String siteUrl, String apiKey, int topicId, int postId})>[];
  final refreshes = <({String siteUrl, String? apiKey, int topicId})>[];
  final _deleted = <(String, int)>{};

  Post post(String siteUrl, int id, {bool canDelete = true}) => Post(
    id: id,
    postNumber: id,
    username: 'author',
    cooked: '<p>Deleted post $id on $siteUrl</p>',
    deletedAt: DateTime.utc(2026, 8, 25),
    canPermanentlyDelete: id != 1 && canDelete,
  );

  TopicPayload payload(String siteUrl, {bool canDelete = true}) => topicPayload(
    id: 7,
    title: 'A real topic',
    posts: [post(siteUrl, 1), post(siteUrl, 2)],
    deletedAt: DateTime.utc(2026, 8, 25),
    canPermanentlyDelete: canDelete,
  );

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
  }) async => payload(siteUrl);

  @override
  Future<_CheckResult> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    checks.add((siteUrl: siteUrl, apiKey: apiKey, postId: postId));
    final held = nextCheck;
    nextCheck = null;
    return held == null ? checkResult : await held.future;
  }

  Future<void> _write() async {
    final held = nextWrite;
    nextWrite = null;
    if (held != null) await held.future;
    if (deletionFailure case final failure?) throw failure;
  }

  @override
  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    topicDeletes.add((siteUrl: siteUrl, apiKey: apiKey, topicId: topicId));
    await _write();
  }

  @override
  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  }) async {
    postDeletes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      postId: postId,
    ));
    await _write();
    _deleted.add((siteUrl, postId));
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
    refreshes.add((siteUrl: siteUrl, apiKey: apiKey, topicId: topicId));
    final held = nextRefresh;
    nextRefresh = null;
    if (held != null) return held.future;
    return [
      for (final id in ids)
        if (!_deleted.contains((siteUrl, id))) post(siteUrl, id),
    ];
  }
}
