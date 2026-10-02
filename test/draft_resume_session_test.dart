import 'dart:async';

import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart' show Offset, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://meta.discourse.org';
const _oldUser = DiscourseUser(id: 7, username: 'reader', draftCount: 1);
const _newUser = DiscourseUser(id: 22, username: 'replacement');
const _topic = Topic(id: 7, title: 'A shared topic', slug: 'shared-topic');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final newTopic in [true, false]) {
    for (final reconnect in [true, false]) {
      testWidgets(
        '${newTopic ? 'new-topic' : 'reply'} draft row ${reconnect ? 'does not restore across an account reconnect' : 'restores after its current navigation completes'}',
        (tester) async {
          final draft = UserDraft(
            key: newTopic ? 'new_topic' : 'topic_7',
            sequence: 4,
            topicId: newTopic ? null : 7,
            title: newTopic ? null : _topic.title,
            slug: newTopic ? null : _topic.slug,
            data: ComposerDraft(
              reply: 'Private draft from the first account',
              action: newTopic
                  ? ComposerDraft.createTopicAction
                  : ComposerDraft.replyAction,
              title: newTopic ? 'Private unfinished topic' : null,
            ),
          );
          final api = _HeldNavigationApi(draft);
          final drafts = FakeDraftStore();
          final authenticator = FakeAuthenticator(
            credentials: const UserApiCredentials(
              key: 'new-key',
              apiVersion: 4,
              push: false,
            ),
          )..keys[_siteUrl] = 'old-key';
          api.accounts['old-key'] = _oldUser;
          api.accounts['new-key'] = _newUser;
          await pumpShell(
            tester,
            desktop,
            api: api,
            drafts: drafts,
            authenticator: authenticator,
            instances: [
              instance('meta.discourse.org').copyWith(user: _oldUser),
            ],
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          final lease = shell.lifecycle.capture(_siteUrl);
          final gate = Completer<void>();
          if (newTopic) {
            // Refresh the default list through its sidebar action, then visit
            // Drafts while that request is still out. Resuming shares it.
            api.feedGate = gate;
            await tester.tap(sidebarDestination('Topics'));
            await tester.pump();
            expect(api.heldFeedRequests, 1);
          } else {
            api.topicGateForResume = gate;
          }
          await tester.tap(sidebarDestination('Drafts'));
          await tester.pumpAndSettle();
          expect(find.byType(DraftListView), findsOneWidget);
          final row = find.byKey(ValueKey(draft.key));
          await tester.tapAt(
            tester.getTopLeft(
                  find.descendant(
                    of: row,
                    matching: find.byTooltip('Remove draft'),
                  ),
                ) -
                const Offset(100, 0),
          );
          await tester.pump();
          if (!newTopic) expect(api.heldTopicRequests, 1);
          expect(shell.visibleComposer, isNull);

          if (reconnect) {
            // Later requests belong to the replacement account; only the
            // navigation initiated by the old row remains held.
            api.feedGate = null;
            api.topicGateForResume = null;
            api.userDraftList = const [];
            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            await tester.pumpAndSettle();
            expect(lease.isCurrent, isFalse);
            expect(shell.currentInstance?.user?.id, _newUser.id);
            if (!newTopic) {
              // The new account can legitimately return to the same topic.
              await tester.tap(contentText(_topic.title));
              await tester.pumpAndSettle();
              expect(shell.currentContent?.topicId, _topic.id);
              expect(shell.canReplyHere, isTrue);
            } else {
              expect(shell.destinationId, 'latest');
              expect(shell.canCreateTopicHere, isTrue);
            }
          }

          gate.complete();
          await tester.pumpAndSettle();
          if (reconnect) {
            expect(shell.visibleComposer, isNull);
            expect(find.byType(ComposerPanel), findsNothing);
            expect(await drafts.read(_siteUrl, draft.key), isNull);
            expect(api.draftsSaved, isEmpty);
          } else {
            expect(shell.visibleComposer?.raw, draft.data!.reply);
            expect(shell.visibleComposer?.target.draftKey, draft.key);
            expect(shell.visibleComposer?.draftSequence, draft.sequence);
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }
}

class _HeldNavigationApi extends FakeDiscourseApi {
  _HeldNavigationApi(UserDraft draft)
    : super(
        user: _oldUser,
        userDraftList: [draft],
        feeds: const {
          '/latest.json': [_topic],
        },
        creatableFeedPaths: const {'/latest.json'},
        topics: {
          7: topicPayload(
            id: 7,
            title: _topic.title,
            canCreatePost: true,
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'reader',
                cooked: '<p>Post</p>',
              ),
            ],
          ),
        },
      );

  Completer<void>? feedGate;
  Completer<void>? topicGateForResume;
  int heldFeedRequests = 0;
  int heldTopicRequests = 0;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (feedGate case final gate?) {
      heldFeedRequests++;
      await gate.future;
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    if (topicGateForResume case final gate?) {
      heldTopicRequests++;
      await gate.future;
    }
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
  }
}
