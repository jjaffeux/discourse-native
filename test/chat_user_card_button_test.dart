import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const _site = 'https://chat.example';
const _otherSite = 'https://other.example';
const _me = DiscourseUser(id: 7, username: 'reader');
const _sites = [
  DiscourseInstance(url: _site, title: 'Chat forum', user: _me),
  DiscourseInstance(url: _otherSite, title: 'Other forum', user: _me),
];
const _created = ChatChannel(
  id: 9,
  title: 'Sam',
  kind: ChatChannelKind.directMessage,
);
const _otherChannel = ChatChannel(
  id: 9,
  title: 'Another person',
  kind: ChatChannelKind.directMessage,
  membership: ChatMembership(following: true),
);
final _profile = UserCard(
  username: 'sam',
  name: 'Sam Example',
  plugins: PluginData.none.withValue(
    chatUserCardKey,
    const ChatUserCardData(canChat: true),
  ),
);
final _surface = find.byKey(const ValueKey('user-card-surface'));
final _chatButton = find.byKey(const ValueKey('user-card-chat-sam'));

void main() {
  for (final delayFollow in [false, true]) {
    for (final switchForum in [false, true]) {
      testWidgets(
        'a delayed DM ${delayFollow ? 'follow' : 'creation'} '
        '${switchForum ? 'does not navigate after the forum changes' : 'opens on its unchanged forum'}',
        (tester) async {
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final api = _CardChatApi(completion: gate, delayFollow: delayFollow);
          final controller = await _pumpCard(tester, api);
          final state = tester.state(find.byType(ChatUserCardButton));
          await tester.tap(_chatButton);
          await tester.pump();
          expect(api.creationSites, [_site]);
          if (delayFollow) {
            expect(api.chatChannelFollowsUpdated, [
              (channelId: 9, following: true),
            ]);
          }

          if (switchForum) {
            controller.selectInstance(1);
            await controller.chat.loadChannels(_otherSite);
            await tester.pump();
            expect(_surface, findsOneWidget);
            expect(tester.state(find.byType(ChatUserCardButton)), same(state));
            expect(controller.currentInstance?.url, _otherSite);
          }

          gate.complete();
          await tester.pumpAndSettle();

          final shell = controller.pluginSession.require(chatShellService);
          expect(controller.chat.channel(_site, 9)?.title, 'Sam');
          if (switchForum) {
            expect(controller.currentInstance?.url, _otherSite);
            expect(shell.fullPageChatActive, isFalse);
            expect(_surface, findsOneWidget);
          } else {
            expect(controller.currentInstance?.url, _site);
            expect(shell.visibleChannelId, 9);
            expect(shell.fullPageChatActive, isTrue);
            expect(_surface, findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<ShellController> _pumpCard(WidgetTester tester, _CardChatApi api) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore(_sites),
    api: api,
    authenticator: FakeAuthenticator.signedIn(_sites, site: api),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: UserCardTarget(
                username: 'sam',
                siteUrl: _site,
                child: Text('Open Sam'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(UserCardTarget));
  await tester.pumpAndSettle();
  expect(_surface, findsOneWidget);
  expect(_chatButton, findsOneWidget);
  return controller;
}

final class _CardChatApi extends FakeDiscourseApi {
  _CardChatApi({required this.completion, required this.delayFollow})
    : super(
        user: _me,
        totals: chatNotificationTotals(),
        cards: {'sam': _profile},
        directMessageChannelsByUsername: const {'sam': _created},
        chatChannelsBySite: const {
          _site: ChatChannels(),
          _otherSite: ChatChannels(direct: [_otherChannel]),
        },
        chatChannelFollowGate: delayFollow ? completion : null,
      );

  final Completer<void> completion;
  final bool delayFollow;
  final List<String> creationSites = [];

  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) async {
    creationSites.add(siteUrl);
    final channel = await super.createChatDirectMessageChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      usernames: usernames,
      groups: groups,
      name: name,
      upsert: upsert,
      clientId: clientId,
    );
    if (!delayFollow) await completion.future;
    return channel;
  }
}
