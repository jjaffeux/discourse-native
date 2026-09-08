import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://team.discourse.org';
const _reader = DiscourseUser(id: 9, username: 'author');
const _staff = DiscourseUser(id: 9, username: 'moderator', staff: true);
const _replacement = DiscourseUser(id: 10, username: 'replacement');
final _confirm = find.byKey(const ValueKey('topic-delete-confirm'));

void main() {
  for (final sameUser in [false, true]) {
    testWidgets(
      'delete confirmation rejects ${sameUser ? 'reconnected' : 'replacement'} credentials',
      (tester) async {
        final api = _DeletionApi()
          ..replacementUser = sameUser ? _reader : _replacement;
        final shell = await _fixture(tester, api);
        await _choose(tester, 'Delete topic');
        final button = tester.element(find.byType(TopicStatusButton));

        await _reconnect(tester, shell);
        expect(shell.currentInstance?.user, api.replacementUser);
        expect(shell.currentTopic?.canDeleteTopic, isTrue);
        expect(tester.element(find.byType(TopicStatusButton)), same(button));
        expect(_confirm, findsOneWidget);
        final route = shell.currentContent;
        final topic = shell.currentTopic;

        await tester.tap(_confirm);
        await tester.pumpAndSettle();

        expect(api.writes, isEmpty);
        expect(shell.currentContent, same(route));
        expect(shell.currentTopic, same(topic));
        expect(_confirm, findsNothing);
      },
    );
  }

  for (final pending in ['credentials', 'write', 'write error']) {
    testWidgets(
      'retired delete $pending cannot navigate a replacement account',
      (tester) async {
        final api = _DeletionApi();
        final auth = _GatedAuthenticator();
        final shell = await _fixture(tester, api, authenticator: auth);
        await _choose(tester, 'Delete topic');
        final credential = Completer<String?>();
        final write = Completer<void>();
        if (pending == 'credentials') {
          auth.nextRead = credential;
        } else {
          api.writeGate = write;
        }
        await tester.tap(_confirm);
        await tester.pump();
        expect(auth.nextRead, isNull);
        expect(api.writes, hasLength(pending == 'credentials' ? 0 : 1));

        await _reconnect(tester, shell);
        final route = shell.currentContent;
        final topic = shell.currentTopic;
        if (pending == 'credentials') {
          credential.complete('original-key');
        } else if (pending == 'write error') {
          write.completeError(
            const WriteException(
              WriteFailure.validation,
              errors: ['Old failure'],
            ),
          );
        } else {
          write.complete();
        }
        await tester.pumpAndSettle();

        expect(shell.currentInstance?.user, _replacement);
        expect(shell.currentContent, same(route));
        expect(shell.currentTopic, same(topic));
        expect(shell.currentTopic?.deletedAt, isNull);
        expect(api.writes, hasLength(pending == 'credentials' ? 0 : 1));
        expect(
          api.writes.every((write) => write.apiKey == 'original-key'),
          isTrue,
        );
        expect(find.text('Old failure'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final beforeSubmit in [false, true]) {
    for (final destination in [
      'topic',
      'forum',
      'tab',
      'reopened topic',
      'aggregate',
    ]) {
      testWidgets(
        'delete keeps its target without popping $destination ${beforeSubmit ? 'during confirmation' : 'during the request'}',
        (tester) async {
          final api = _DeletionApi();
          final shell = await _fixture(tester, api);
          final openingRoute = shell.currentContent;
          final openingTab = shell.activeTabId;
          await _choose(tester, 'Delete topic');
          final write = Completer<void>();
          api.writeGate = write;
          if (!beforeSubmit) {
            await tester.tap(_confirm);
            await tester.pump();
            expect(api.writes, hasLength(1));
          }

          switch (destination) {
            case 'topic':
              shell.openTopicPost(siteUrl: _site, topicId: 8, postNumber: 1);
            case 'forum':
              shell.openTopicPost(
                siteUrl: _otherSite,
                topicId: 7,
                postNumber: 1,
              );
            case 'tab':
              shell.createTab();
              expect(shell.activeTabId, isNot(openingTab));
              shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
            case 'reopened topic':
              expect(shell.handleBack(canReturnToSidebar: false), isTrue);
              shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
              expect(shell.currentContent, openingRoute);
              expect(shell.currentContent, isNot(same(openingRoute)));
            case 'aggregate':
              shell.selectAggregate();
          }
          await tester.pump();
          final route = shell.currentContent;
          final tab = shell.activeTabId;
          final site = shell.currentInstance?.url;
          final root = shell.rootMode;
          if (beforeSubmit) {
            await tester.tap(_confirm);
            await tester.pump();
          }
          write.complete();
          await tester.pumpAndSettle();

          expect(api.writes, [
            (siteUrl: _site, apiKey: 'original-key', topicId: 7, deleted: true),
          ]);
          expect(shell.store.read<TopicDetail>(_site, 7)?.deletedAt, isNotNull);
          expect(
            shell.store.read<TopicDetail>(_otherSite, 7)?.deletedAt,
            isNull,
          );
          expect(shell.currentContent, same(route));
          expect(shell.activeTabId, tab);
          expect(shell.currentInstance?.url, site);
          expect(shell.rootMode, root);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'cancel and server refusal leave the topic open, then retry goes back',
    (tester) async {
      final api = _DeletionApi();
      final shell = await _fixture(tester, api);
      final route = shell.currentContent;
      await _choose(tester, 'Delete topic');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      expect(shell.currentContent, same(route));

      api.deletionFailure = const WriteException(
        WriteFailure.validation,
        errors: ['Deletion is temporarily disabled.'],
      );
      await _choose(tester, 'Delete topic');
      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(find.text('Deletion is temporarily disabled.'), findsOneWidget);
      expect(shell.currentContent, same(route));
      expect(shell.currentTopic?.deletedAt, isNull);

      api.deletionFailure = null;
      await _choose(tester, 'Delete topic');
      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(2));
      expect(shell.currentContent?.topicId, isNull);
      expect(shell.store.read<TopicDetail>(_site, 7)?.deletedAt, isNotNull);
    },
  );

  for (final replacement in ['topic', 'account']) {
    testWidgets(
      'shell delete completion before rebuild cannot pop a replacement $replacement',
      (tester) async {
        final api = _DeletionApi();
        final shell = await _openShell(tester, api);
        await _choose(tester, 'Delete topic');
        final write = Completer<void>();
        api.writeGate = write;
        await tester.tap(_confirm);
        await tester.pump();
        expect(api.writes, hasLength(1));
        final button = tester.element(find.byType(TopicStatusButton));

        if (replacement == 'account') {
          await shell.disconnectCurrentInstance();
          await shell.connectCurrentInstance();
          expect(shell.currentInstance?.user, _replacement);
        }
        final topicId = replacement == 'account' ? 7 : 8;
        shell.openTopicPost(siteUrl: _site, topicId: topicId, postNumber: 1);
        expect(button.mounted, isTrue);
        // Complete before the next frame can dispose the original button.
        write.complete();
        await tester.pumpAndSettle();

        expect(shell.currentContent?.topicId, topicId);
        expect(shell.currentTopic?.deletedAt, isNull);
        expect(api.writes.single.apiKey, 'original-key');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final staff in [false, true]) {
    testWidgets(
      'shell preserves successful ${staff ? 'staff delete and recovery' : 'nonstaff delete and back'}',
      (tester) async {
        final api = _DeletionApi(reader: staff ? _staff : _reader);
        final shell = await _openShell(tester, api);
        final route = shell.currentContent;
        await _choose(tester, 'Delete topic');
        await tester.tap(_confirm);
        await tester.pumpAndSettle();
        expect(api.writes.single.deleted, isTrue);
        expect(shell.store.read<TopicDetail>(_site, 7)?.deletedAt, isNotNull);
        if (staff) {
          expect(shell.currentContent, same(route));
          expect(shell.currentTopic?.canRecoverTopic, isTrue);
          await _choose(tester, 'Recover topic');
          expect(api.writes.last.deleted, isFalse);
          expect(shell.currentContent, same(route));
          expect(shell.currentTopic?.deletedAt, isNull);
          expect(shell.currentTopic?.canDeleteTopic, isTrue);
        } else {
          expect(shell.currentContent?.topicId, isNull);
        }
      },
    );
  }
}

Future<ShellController> _openShell(
  WidgetTester tester,
  _DeletionApi api,
) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [instance('meta.discourse.org').copyWith(user: api.reader)],
    authenticator: FakeAuthenticator()..keys[_site] = 'original-key',
  );
  await tester.tap(contentText('A real topic'));
  await tester.pumpAndSettle();
  return ShellScope.read(tester.element(find.byType(MainContent)));
}

Future<ShellController> _fixture(
  WidgetTester tester,
  _DeletionApi api, {
  FakeAuthenticator? authenticator,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: api.reader),
      instance('team.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: (authenticator ?? FakeAuthenticator())
      ..keys[_site] = 'original-key'
      ..keys[_otherSite] = 'other-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: true,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    initialRootMode: ShellRootMode.forum,
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  await tester.pumpAndSettle();
  final topic = shell.currentTopic!;
  // Keep the production button mounted so context.mounted alone cannot mask
  // an account or route change while its confirmation/request is pending.
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: shell,
            builder: (context, _) => TopicStatusButton(
              siteUrl: _site,
              topic: shell.store.read<TopicDetail>(_site, 7) ?? topic,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('topic-status-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _reconnect(WidgetTester tester, ShellController shell) async {
  await shell.disconnectCurrentInstance();
  await shell.connectCurrentInstance();
  shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
  await tester.pump();
  expect(shell.currentTopic?.canDeleteTopic, isTrue);
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

class _DeletionApi extends FakeDiscourseApi {
  _DeletionApi({this.reader = _reader})
    : super(
        user: reader,
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A real topic', slug: 'topic')],
        },
      );

  final DiscourseUser reader;
  DiscourseUser replacementUser = _replacement;
  Completer<void>? writeGate;
  WriteException? deletionFailure;
  final writes =
      <({String siteUrl, String apiKey, int topicId, bool deleted})>[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'api-key' ? replacementUser : reader;

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
    canDeleteTopic: true,
    posts: const [
      Post(id: 1, postNumber: 1, username: 'author', cooked: '<p>Body</p>'),
    ],
  );

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      deleted: true,
    ));
    await writeGate?.future;
    if (deletionFailure case final failure?) throw failure;
  }

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      deleted: false,
    ));
    if (deletionFailure case final failure?) throw failure;
  }
}
