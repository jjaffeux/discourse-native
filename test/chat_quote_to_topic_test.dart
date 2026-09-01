import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ShellController> shell({bool openChannel = true}) async {
    const channel = ChatChannel(
      id: 9,
      title: 'Support chat',
      kind: ChatChannelKind.category,
      chatableId: 5,
      membership: ChatMembership(following: true),
    );
    final controller = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
      ]),
      api: FakeDiscourseApi(
        totals: chatNotificationTotals(),
        user: _user,
        feeds: const {'/latest.json': <Topic>[]},
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
            minimumRequiredTags: 1,
          ),
        ],
        chatChannelsBySite: const {
          _siteUrl: ChatChannels(public: [channel], direct: []),
        },
      ),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await controller.load();
    await pumpEventQueue();
    if (openChannel) expect(controller.openChatChannel(9), isTrue);
    return controller;
  }

  test(
    'opens a category-aware topic draft over chat and inserts transcript',
    () async {
      final controller = await shell();
      addTearDown(controller.dispose);
      const transcript = '[chat channel="Support chat"]\nHello\n[/chat]';

      expect(await controller.openChatQuote(_siteUrl, 9, transcript), isNull);

      final composer = controller.visibleComposer;
      expect(composer, isNotNull);
      expect(composer!.target.isNewTopic, isTrue);
      expect(composer.categoryId, 5);
      expect(composer.raw, transcript);
    },
  );

  test('reuses an unfinished chat-origin draft for another quote', () async {
    final controller = await shell();
    addTearDown(controller.dispose);

    await controller.openChatQuote(_siteUrl, 9, '[chat]first[/chat]');
    final composer = controller.visibleComposer!;
    composer.insertText('My response');
    await controller.openChatQuote(_siteUrl, 9, '[chat]second[/chat]');

    expect(controller.visibleComposer, same(composer));
    expect(composer.raw, contains('[chat]first[/chat]'));
    expect(composer.raw, contains('My response'));
    expect(composer.raw, contains('[chat]second[/chat]'));
  });

  test('opens a topic draft from a modeless drawer channel', () async {
    final controller = await shell(openChannel: false);
    addTearDown(controller.dispose);
    final chatShell = controller.pluginSession.require(chatShellService);

    await chatShell.openShortcut(drawerAvailable: true);
    expect(chatShell.openChannel(9), isTrue);
    expect(chatShell.drawerActive, isTrue);
    expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');
    expect(controller.currentContent?.id, 'latest');

    expect(
      await controller.openChatQuote(
        _siteUrl,
        9,
        '[chat channel="Support chat"]\nDrawer quote\n[/chat]',
      ),
      isNull,
    );
    expect(controller.visibleComposer?.raw, contains('Drawer quote'));
  });
}
