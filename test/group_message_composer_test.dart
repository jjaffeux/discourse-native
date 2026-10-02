import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/group_pages_shell_port.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message group opens and submits a native private-message composer',
    () async {
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(
              id: 1,
              username: 'reader',
              canSendPrivateMessages: true,
            ),
          ),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.group(GroupRoute.detail('tech-leads')));

      shell.openPrivateMessage(
        siteUrl: _siteUrl,
        targetRecipients: 'tech-leads',
      );

      final composer = shell.visibleComposer;
      expect(composer, isNotNull);
      expect(composer!.target.mode, ComposerMode.privateMessage);
      expect(composer.target.targetRecipients, 'tech-leads');
      expect(composer.target.draftKey, 'new_private_message');

      composer.title.text = 'A private subject';
      composer.text.text = 'Hello team';
      await shell.submitComposer();

      expect(api.topicsCreated, hasLength(1));
      expect(api.topicsCreated.single['title'], 'A private subject');
      expect(api.topicsCreated.single['raw'], 'Hello team');
      expect(api.topicsCreated.single['targetRecipients'], 'tech-leads');
      expect(api.topicsCreated.single['draftKey'], 'new_private_message');
      expect(shell.visibleComposer, isNull);
      expect(shell.currentContent?.topicId, 901);
    },
  );

  test('a message sent to a group re-reads its page Messages tab', () async {
    const inbox = '/topics/private-messages-group/reader/tech-leads.json';
    const held = Topic(
      id: 5,
      title: 'Held',
      slug: 'held',
      privateMessage: true,
    );
    const user = DiscourseUser(
      id: 1,
      username: 'reader',
      canSendPrivateMessages: true,
      groups: ['tech-leads'],
      messageGroupNames: ['tech-leads'],
    );
    final api = FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': const [],
        inbox: const [held],
      },
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    final tab = GroupRoute.detail(
      'tech-leads',
      section: GroupRoute.messages,
      subsection: GroupRoute.inbox,
    );
    shell.pushContent(
      ContentRoute.group(tab, feedPath: tab.topicFeedPath('reader')),
    );
    await shell.loadFeed(tab.id);

    shell.openPrivateMessage(siteUrl: _siteUrl, targetRecipients: 'tech-leads');
    final composer = shell.visibleComposer!;
    composer.title.text = 'A private subject';
    composer.text.text = 'Hello team';
    api.feeds[inbox] = const [
      Topic(
        id: 901,
        title: 'A private subject',
        slug: 'created-topic',
        privateMessage: true,
      ),
      held,
    ];
    final reads = api.feedPaths.length;
    await shell.submitComposer();
    await pumpEventQueue();

    expect(shell.topicFeeds.feedFor(_siteUrl, tab.id)?.topicIds, [901, 5]);
    expect(api.feedPaths.sublist(reads), [inbox]);
  });

  group('without general private-message permission', () {
    Future<ShellController> loadShell() async {
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.group(GroupRoute.detail('moderators')));
      return shell;
    }

    void messageGroup(ShellController shell, Group group) =>
        ShellGroupPagesPort(shell).messageGroup((
          siteUrl: _siteUrl,
          accountIdentity: shell.currentAccountIdentity!,
          sessionIdentity: shell.lifecycle.capture(_siteUrl).session,
          tabId: shell.activeTabId,
        ), group);

    test('a new message to users remains unavailable', () async {
      final shell = await loadShell();

      shell.openPrivateMessage(siteUrl: _siteUrl, targetRecipients: 'sam');

      expect(shell.visibleComposer, isNull);
    });

    test(
      'a group the server marks messageable can still be messaged',
      () async {
        final shell = await loadShell();

        messageGroup(
          shell,
          const Group(id: 2, name: 'moderators', messageable: true),
        );

        final composer = shell.visibleComposer;
        expect(composer, isNotNull);
        expect(composer!.target.mode, ComposerMode.privateMessage);
        expect(composer.target.targetRecipients, 'moderators');
      },
    );

    test('a group the server does not mark messageable cannot', () async {
      final shell = await loadShell();

      messageGroup(shell, const Group(id: 2, name: 'moderators'));

      expect(shell.visibleComposer, isNull);
    });
  });
}
