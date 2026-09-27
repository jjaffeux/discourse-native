import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _reader = DiscourseUser(username: 'reader', canSendPrivateMessages: true);
const _message = TopicDetail(
  id: 7,
  title: 'Question',
  stream: [],
  privateMessage: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an older topic read cannot undo a completed archive write', () async {
    final api = _ArchiveApi();
    final shell = await _shell(api);
    final staleRead = shell.loadTopic(7, 'question', force: true);
    await api.started.future;
    expect(await shell.updateMessageArchived(_site, 7, true), isNull);
    api.response.complete((detail: _message, posts: <Post>[]));
    await staleRead;
    expect(shell.store.read<TopicDetail>(_site, 7)!.messageArchived, isTrue);
    expect(shell.store.read<TopicDetail>(_site, 7)!.archived, isFalse);
  });

  test(
    'ordinary topics and accounts without PM permission cannot archive messages',
    () async {
      final api = FakeDiscourseApi();
      final shell = await _shell(api);
      shell.store.put(_site, _message.copyWith(privateMessage: false));
      expect(await shell.updateMessageArchived(_site, 7, true), isNotNull);
      final denied = await _shell(
        api,
        user: const DiscourseUser(username: 'reader'),
      );
      expect(await denied.updateMessageArchived(_site, 7, true), isNotNull);
      expect(api.messagesArchived, isEmpty);
    },
  );

  // The account's message groups can predate a group's first message, which
  // then only the topic names.
  for (final listed in [true, false]) {
    test(
      'archive and move to inbox re-read the group page message tabs'
      '${listed ? '' : ' of a group the account does not list yet'}',
      () async {
        const inbox = '/topics/private-messages-group/reader/team.json';
        const archive =
            '/topics/private-messages-group/reader/team/archive.json';
        const row = Topic(
          id: 7,
          title: 'Question',
          slug: 'question',
          privateMessage: true,
        );
        final user = DiscourseUser(
          username: 'reader',
          canSendPrivateMessages: true,
          groups: const ['team'],
          messageGroupNames: listed ? const ['team'] : const [],
        );
        final api = FakeDiscourseApi(
          user: user,
          feeds: {
            '/latest.json': const [],
            inbox: const [row],
            archive: const [],
          },
        );
        final shell = await _shell(api, user: user);
        shell.store.put(
          _site,
          const TopicDetail(
            id: 7,
            title: 'Question',
            stream: [],
            privateMessage: true,
            allowedMessageGroups: ['team'],
          ),
        );
        GroupRoute tab(String subsection) => GroupRoute.detail(
          'team',
          section: GroupRoute.messages,
          subsection: subsection,
        );
        final inboxTab = tab(GroupRoute.inbox);
        final archiveTab = tab(GroupRoute.archive);
        shell.pushContent(
          ContentRoute.group(
            inboxTab,
            feedPath: inboxTab.topicFeedPath('reader'),
          ),
        );
        await shell.loadFeed(inboxTab.id);
        shell.selectGroupRoute(archiveTab);
        await pumpEventQueue();
        List<int>? rows(GroupRoute tab) =>
            shell.topicFeeds.feedFor(_site, tab.id)?.topicIds;
        expect(rows(inboxTab), [7]);
        expect(rows(archiveTab), isEmpty);

        for (final archived in [true, false]) {
          api.feeds[inbox] = archived ? const [] : const [row];
          api.feeds[archive] = archived ? const [row] : const [];
          final reads = api.feedPaths.length;
          expect(await shell.updateMessageArchived(_site, 7, archived), isNull);
          await pumpEventQueue();
          expect(rows(inboxTab), archived ? isEmpty : [7]);
          expect(rows(archiveTab), archived ? [7] : isEmpty);
          // Only the loaded tabs are read; the rest load when opened.
          expect(
            api.feedPaths.sublist(reads),
            unorderedEquals([inbox, archive]),
          );
        }
      },
    );
  }
}

Future<ShellController> _shell(
  FakeDiscourseApi api, {
  DiscourseUser user = _reader,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.store.put(_site, _message);
  return shell;
}

class _ArchiveApi extends FakeDiscourseApi {
  final started = Completer<void>();
  final response = Completer<TopicPayload>();

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
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
