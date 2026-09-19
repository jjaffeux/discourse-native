import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app_shortcuts.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_new_direct_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'bundled_plugins.dart';
import 'chat_shell.dart';
import 'fakes.dart';

const startChattingSite = 'https://chat-review.invalid';
final startChattingUser = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
const startChattingPeople = [
  ChatDirectMessageUser(
    identifier: 'u-2',
    matchQuality: 1,
    enabled: true,
    username: 'maya',
    name: 'Maya Chen',
  ),
  ChatDirectMessageUser(
    identifier: 'u-3',
    matchQuality: 1,
    enabled: true,
    username: 'theo',
    name: 'Theo Martin',
  ),
  ChatDirectMessageUser(
    identifier: 'u-4',
    matchQuality: 1,
    enabled: true,
    username: 'lena',
    name: 'Lena Fischer',
  ),
];
const startChattingGroup = ChatDirectMessageGroup(
  identifier: 'g-8',
  matchQuality: 1,
  enabled: true,
  name: 'design',
  fullName: 'Design team',
  memberCount: 3,
);
final startChattingChannels = [
  ChatChannel(
    id: 55,
    title: 'Maya Chen',
    kind: ChatChannelKind.directMessage,
    users: const [ChatUser(id: 2, username: 'maya', name: 'Maya Chen')],
    membership: const ChatMembership(following: true),
    tracking: const ChatTracking(),
    lastMessageAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
  ChatChannel(
    id: 56,
    title: 'Design catch-up',
    kind: ChatChannelKind.directMessage,
    isGroup: true,
    users: const [
      ChatUser(id: 2, username: 'maya', name: 'Maya'),
      ChatUser(id: 3, username: 'theo', name: 'Theo'),
    ],
    membership: const ChatMembership(following: true),
    tracking: const ChatTracking(),
    lastMessageAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  ChatChannel(
    id: 57,
    title: 'Theo Martin',
    kind: ChatChannelKind.directMessage,
    users: const [ChatUser(id: 3, username: 'theo', name: 'Theo Martin')],
    membership: const ChatMembership(following: true),
    tracking: const ChatTracking(),
    lastMessageAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  ChatChannel(
    id: 58,
    title: 'Lena Fischer',
    kind: ChatChannelKind.directMessage,
    users: const [ChatUser(id: 4, username: 'lena', name: 'Lena Fischer')],
    membership: const ChatMembership(following: true),
    tracking: const ChatTracking(),
    lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
];

class StartChattingApi extends FakeDiscourseApi {
  StartChattingApi()
    : super(
        user: startChattingUser,
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {
          startChattingSite: ChatChannels(
            public: const [],
            direct: startChattingChannels.reversed.toList(),
          ),
        },
        directMessageChannelsByUsername: {
          'maya': startChattingChannels[0],
          'theo': startChattingChannels[2],
          'lena': startChattingChannels[3],
        },
        directMessageGroupChannel: const ChatChannel(
          id: 59,
          title: 'New group',
          kind: ChatChannelKind.directMessage,
          isGroup: true,
          membership: ChatMembership(following: true),
          tracking: ChatTracking(),
        ),
      );

  final pendingSearches = <String, Completer<ChatDirectMessageSearchResults>>{};
  bool failSearch = false;
  Completer<void>? creationGate;
  bool failCreation = false;

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
    final channel = await super.createChatDirectMessageChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      usernames: usernames,
      groups: groups,
      name: name,
      upsert: upsert,
      clientId: clientId,
    );
    if (creationGate case final gate?) await gate.future;
    if (failCreation) throw StateError('Sample creation failure');
    return channel;
  }

  @override
  Future<ChatDirectMessageSearchResults> searchChatDirectMessages({
    required String siteUrl,
    required String apiKey,
    required String term,
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    String? clientId,
  }) async {
    await super.searchChatDirectMessages(
      siteUrl: siteUrl,
      apiKey: apiKey,
      term: term,
      includeGroups: includeGroups,
      includeDirectMessageChannels: includeDirectMessageChannels,
      clientId: clientId,
    );
    if (pendingSearches[term] case final pending?) return pending.future;
    if (failSearch) throw StateError('Sample search failure');
    final query = term.toLowerCase();
    return ChatDirectMessageSearchResults([
      for (final person in startChattingPeople)
        if ('${person.username} ${person.name}'.toLowerCase().contains(query))
          person,
      if (includeGroups && 'design team'.contains(query)) startChattingGroup,
    ]);
  }
}

Future<ShellController> startChattingShell(
  StartChattingApi api, {
  int maximumMembers = 10,
}) async {
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('chat-review.invalid').copyWith(
        user: startChattingUser,
        config: SiteConfig(
          plugins: PluginData.none.withValue(
            chatSettingsDataKey,
            ChatSettings(maximumDirectMessageUsers: maximumMembers),
          ),
        ),
      ),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[startChattingSite] = 'fixture-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  await shell.chat.loadChannels(startChattingSite);
  return shell;
}

class StartChattingFixture extends StatefulWidget {
  const StartChattingFixture({
    super.key,
    required this.shell,
    this.textScale = 1,
    this.rtl = false,
  });
  final ShellController shell;
  final double textScale;
  final bool rtl;
  @override
  State<StartChattingFixture> createState() => _StartChattingFixtureState();
}

class _StartChattingFixtureState extends State<StartChattingFixture> {
  bool dark = false;
  final triggerFocus = FocusNode(debugLabel: 'Open start chatting');
  @override
  void dispose() {
    triggerFocus.dispose();
    super.dispose();
  }

  void open(BuildContext context) => unawaited(
    showChatNewDirectMessageDialog(
      context: context,
      siteUrl: startChattingSite,
      chat: widget.shell.chat,
      shell: widget.shell.pluginSession.require(chatShellService),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => DFocusHighlight(
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: Directionality(
          textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
    ),
    home: Builder(
      builder: (context) => CallbackShortcuts(
        bindings: {
          newDirectMessageShortcutForPlatform(Theme.of(context).platform): () =>
              open(context),
        },
        child: ColoredBox(
          color: DTokens.of(context).background,
          child: Center(
            child: DCard(
              children: [
                DCardContent(
                  child: Wrap(
                    spacing: DSpacing.controlGap,
                    children: [
                      DButton(
                        key: const ValueKey('open-start-chatting'),
                        focusNode: triggerFocus,
                        label: const Text('Start chatting'),
                        onPressed: () => open(context),
                      ),
                      DButton(
                        label: Text(
                          dark ? 'Light appearance' : 'Dark appearance',
                        ),
                        onPressed: () => setState(() => dark = !dark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
