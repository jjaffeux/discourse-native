import 'package:discourse_native/discourse_plugin_contracts.dart'
    show DIconData, DIcons, DNativeIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_ui_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_rooms.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', hidePresence: false);
final _config = SiteConfig(
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    const ChatSettings(
      chatEnabled: true,
      publicChannelsEnabled: true,
      threadsEnabled: true,
    ),
  ),
);

final _now = DateTime.now();
DateTime _ago(int minutes) => _now.subtract(Duration(minutes: minutes));

ChatChannel _channel(
  int id,
  String title, {
  int minutesAgo = 0,
  int unread = 0,
  int mentions = 0,
  bool muted = false,
  bool starred = false,
  bool private = false,
  bool direct = false,
  List<ChatUser> users = const [],
  String? preview,
  int? saidBy,
  String? saidByName,
  Map<int, DateTime> threads = const {},
}) => ChatChannel(
  id: id,
  title: title,
  kind: direct ? ChatChannelKind.directMessage : ChatChannelKind.category,
  categoryColor: direct ? null : const Color(0xff2f80ed),
  readRestricted: private,
  isGroup: users.length > 1,
  users: users,
  threadingEnabled: !direct,
  unreadThreadOverview: threads,
  membership: ChatMembership(following: true, muted: muted, starred: starred),
  tracking: ChatTracking(unreadCount: unread, mentionCount: mentions),
  lastMessageId: id * 100,
  lastMessageAt: _ago(minutesAgo),
  lastMessagePreview: preview ?? 'Last said in $title',
  lastMessageUserId: saidBy,
  lastMessageUsername: saidByName,
);

const _ada = ChatUser(id: 21, username: 'ada');
const _bo = ChatUser(id: 22, username: 'bo');

List<ChatChannel> _public() => [
  _channel(
    1,
    'general',
    minutesAgo: 30,
    saidBy: 9,
    saidByName: 'sam',
    preview: 'The design review moved to Friday',
  ),
  _channel(
    2,
    'design',
    minutesAgo: 20,
    unread: 3,
    saidBy: 9,
    saidByName: 'sam',
  ),
  _channel(3, 'secret-ops', minutesAgo: 10, private: true, saidBy: 7),
  _channel(4, 'noisy', minutesAgo: 1, muted: true, mentions: 1),
  _channel(
    5,
    'announcements',
    minutesAgo: 40,
    unread: 1,
    starred: true,
    threads: {70: _ago(5), 71: _ago(6)},
  ),
];

List<ChatChannel> _direct() => [
  _channel(10, 'ada', minutesAgo: 15, direct: true, users: [_ada], saidBy: 21),
  _channel(
    11,
    'ada, bo',
    minutesAgo: 25,
    unread: 2,
    direct: true,
    users: [_ada, _bo],
    saidBy: 22,
    saidByName: 'bo',
    preview: 'Lunch at noon?',
  ),
];

void main() {
  testWidgets('each group leads with what is unread and closes with what is '
      'muted, on the page', (tester) async {
    await prepareNativeUiEvidence(tester);
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));

    double top(int id) => tester.getTopLeft(_row(id)).dy;
    expect(
      tester.getTopLeft(find.text('Starred')).dy,
      lessThan(tester.getTopLeft(find.text('Direct messages')).dy),
    );
    expect(top(5), lessThan(top(11)), reason: 'Starred, then conversations');
    expect(top(11), lessThan(top(10)), reason: 'unread before read');
    expect(top(10), lessThan(top(2)), reason: 'conversations, then channels');
    expect(top(2), lessThan(top(3)), reason: 'unread before more recent read');
    expect(top(3), lessThan(top(1)), reason: 'read, the most recent first');
    expect(top(1), lessThan(top(4)), reason: 'muted last, however recent');
    await captureNativeUi(tester, 'page-by-type');
  });

  testWidgets('an unread row is boxed in the unread fill and a read one is '
      'not', (tester) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    final tokens = DTokens.of(tester.element(_row(2)));

    Finder boxOf(int id) => find.byWidgetPredicate(
      (widget) =>
          widget is DItem &&
          widget.key == ValueKey('chat-inbox-channel-$id') &&
          widget.variant == DItemVariant.unread,
    );
    expect(tokens.unreadFill, tokens.primary.withValues(alpha: .09));
    expect(boxOf(2), findsOneWidget);
    expect(boxOf(1), findsNothing);
    expect(boxOf(4), findsNothing, reason: 'A muted chat is never boxed');
    final page = tester.getRect(find.byType(ChatMobileSidebar));
    final box = tester.getRect(boxOf(2));
    expect(box.left - page.left, 4);
    expect(page.right - box.right, 4);
    expect(tester.widget<DItem>(boxOf(2)).shape, DItemShape.standard);
    // Boxed or not, every row's mark stands on one edge.
    expect(tester.getTopLeft(_mark(2)).dx, tester.getTopLeft(_mark(1)).dx);
    expect(tester.getTopLeft(_mark(1)).dx - page.left, 19);
    expect(tester.getSize(_mark(1)), const Size.square(40));
  });

  testWidgets('a row says how much is new at its top right and when at its '
      'bottom right', (tester) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    final row = tester.getRect(_row(2));
    final count = tester.getRect(
      find.byKey(const ValueKey('chat-inbox-unread-2')),
    );
    final name = tester.getRect(_in(2, find.text('design')));
    final line = tester.getRect(_in(2, find.text('Last said in design')));
    final time = tester.getRect(_in(2, _timeOf(tester, 2)));
    expect(_in(2, find.text('3')), findsOneWidget);
    expect(row.right - count.right, 12);
    expect(count.center.dy, closeTo(name.center.dy, 1));
    expect(row.right - time.right, 12);
    expect(time.center.dy, closeTo(line.center.dy, 1));
    expect(count.center.dy, lessThan(time.center.dy));
    expect(time.left - line.right, greaterThanOrEqualTo(8));
    // A read row has no count, and its name takes the whole line.
    expect(find.byKey(const ValueKey('chat-inbox-unread-1')), findsNothing);
    expect(find.text('3 messages'), findsNothing);

    final design = tester.widget<Text>(_in(2, find.text('design')));
    final general = tester.widget<Text>(_in(1, find.text('general')));
    final noisy = tester.widget<Text>(_in(4, find.text('noisy')));
    final tokens = DTokens.of(tester.element(_row(2)));
    expect(design.style!.fontWeight, FontWeight.w700);
    expect(design.style!.color, tokens.foreground);
    expect(general.style!.fontWeight, FontWeight.w400);
    expect(general.style!.color, tokens.titleRead);
    expect(noisy.style!.color, tokens.mutedForeground);
    expect(
      tester.getSize(_in(2, find.text('design'))).height,
      closeTo(14.5 * 1.35, 1),
    );
  });

  testWidgets('a row marks what is private, muted and starred after its '
      'name', (tester) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    Finder icon(int id, DIconData glyph) =>
        _in(id, find.byWidgetPredicate((w) => w is DIcon && w.icon == glyph));
    expect(icon(3, DIcons.lock), findsOneWidget);
    expect(icon(1, DIcons.lock), findsNothing);
    expect(icon(4, DNativeIcons.bellSlash), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-inbox-muted-unread-4')),
      findsOneWidget,
      reason: 'What is unread in a muted chat is a quiet dot, not a count',
    );
    expect(find.byKey(const ValueKey('chat-inbox-unread-4')), findsNothing);
    expect(
      icon(5, DIcons.star),
      findsNothing,
      reason: 'The Starred heading already says so',
    );
    await tester.tap(find.byTooltip('Newest'));
    await tester.pumpAndSettle();
    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Starred'), findsNothing);
    expect(icon(5, DIcons.star), findsOneWidget);
    // Unread and starred, the rest that is unread, then what is read.
    double top(int id) => tester.getTopLeft(_row(id)).dy;
    expect(top(5), lessThan(top(2)));
    expect(top(2), lessThan(top(11)));
    expect(top(11), lessThan(top(3)));
    await captureNativeUi(tester, 'page-newest');
  });

  testWidgets('whoever spoke is a face before the line, except you and the '
      'one person a conversation is with', (tester) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    Finder face(int id) => find.byKey(ValueKey('chat-inbox-said-by-$id'));
    expect(face(2), findsOneWidget);
    expect(tester.getSize(face(2)).height, 16);
    expect(
      tester.getRect(face(2)).right,
      lessThanOrEqualTo(
        tester.getRect(_in(2, find.text('Last said in design'))).left,
      ),
    );
    expect(face(11), findsOneWidget, reason: 'One of several in a group');
    expect(face(3), findsNothing, reason: 'Your own turn');
    expect(face(10), findsNothing, reason: 'The row is already their face');
    expect(find.textContaining('sam:'), findsNothing);
    expect(find.textContaining('you:'), findsNothing);
  });

  testWidgets('the way to the threads heads the channels and the way to the '
      'rest of them closes them', (tester) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    final threads = find.byKey(const ValueKey('chat-inbox-threads-card'));
    final browse = find.byKey(const ValueKey('chat-inbox-channels-card'));
    await tester.ensureVisible(browse);
    await tester.pumpAndSettle();
    final heading = tester.getTopLeft(find.text('Channels')).dy;
    expect(tester.getTopLeft(threads).dy, greaterThan(heading));
    expect(
      tester.getTopLeft(threads).dy,
      lessThan(tester.getTopLeft(_row(2)).dy),
    );
    expect(
      tester.getTopLeft(browse).dy,
      greaterThan(tester.getTopLeft(_row(4)).dy),
    );
    expect(
      find.descendant(
        of: threads,
        matching: find.text('New replies in 2 threads'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: threads, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: browse,
        matching: find.text('Find and join channels you are not in'),
      ),
      findsOneWidget,
    );
    await tester.tap(threads);
    await tester.pumpAndSettle();
    expect(fixture.shell.currentContent?.id, ChatRoute.myThreadsRouteId);
  });

  testWidgets('the controls are the field, then the order as two marks', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    final field = find.byKey(const ValueKey('chat-search-entry'));
    final order = find.byKey(const ValueKey('chat-inbox-sort-filter'));
    expect(find.text('Find a chat'), findsOneWidget);
    expect(
      tester.getRect(order).top - tester.getRect(field).bottom,
      8,
      reason: 'The switch on the line under the field',
    );
    expect(tester.getRect(order).left, tester.getRect(field).left);
    expect(find.byTooltip('By type'), findsOneWidget);
    expect(find.byTooltip('Newest'), findsOneWidget);
    expect(
      find.descendant(of: order, matching: find.byType(Text)),
      findsNothing,
      reason: 'Each choice is its mark alone',
    );
    expect(
      find.byKey(const ValueKey('chat-inbox-activity-filter')),
      findsNothing,
    );
    expect(find.text('Recent'), findsNothing);
    expect(find.text('Unread'), findsNothing);
  });

  testWidgets('chats are found by name first, then by what was said, each '
      'showing the line that has the words', (tester) async {
    await prepareNativeUiEvidence(tester);
    final fixture = await _pump(tester);
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    await tester.enterText(
      find.byKey(const ValueKey('chat-search-entry')),
      'design',
    );
    await tester.pumpAndSettle();
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Channels'), findsNothing);
    expect(_row(2), findsOneWidget);
    expect(_row(1), findsOneWidget);
    expect(_row(3), findsNothing);
    expect(
      tester.getTopLeft(_row(2)).dy,
      lessThan(tester.getTopLeft(_row(1)).dy),
      reason: 'Found by name before found by what was said',
    );
    expect(
      _in(
        1,
        find.text('The design review moved to Friday', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-inbox-said-by-1')), findsOneWidget);
    final browse = find.byKey(const ValueKey('chat-inbox-channels-card'));
    expect(
      find.descendant(of: browse, matching: find.text('Browse all channels')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: browse,
        matching: find.text('Channels you are not in, for “design”'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-inbox-threads-card')), findsNothing);
    await captureNativeUi(tester, 'page-found');

    await tester.enterText(
      find.byKey(const ValueKey('chat-search-entry')),
      'zebra',
    );
    await tester.pumpAndSettle();
    expect(find.text('None of your chats match “zebra”'), findsOneWidget);
    expect(find.text('Results'), findsNothing);
    await tester.tap(browse);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('chat-channel-panel-field')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'zebra',
      reason: 'The panel opens over the page, holding the words',
    );
  });

  testWidgets('the side draws the page\'s list: the same rows, groups and '
      'ways, with words of its own', (tester) async {
    await prepareNativeUiEvidence(tester);
    final fixture = await _pump(tester, size: const Size(320, 900));
    await fixture.show(_side());
    expect(tester.getSize(_mark(2)), const Size.square(40));
    expect(find.byKey(const ValueKey('chat-inbox-unread-2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-inbox-threads-card')),
      findsOneWidget,
    );
    expect(find.text('Find a chat'), findsOneWidget);
    expect(find.byTooltip('Newest'), findsOneWidget);
    expect(
      tester.getTopLeft(_mark(2)).dx,
      tester.getTopLeft(_mark(1)).dx,
      reason: 'Boxed or not, every mark on one edge',
    );
    await captureNativeUi(tester, 'side-by-type');
    await tester.enterText(
      find.byKey(const ValueKey('chat-search-entry')),
      'general',
    );
    await tester.pumpAndSettle();
    expect(find.text('Results'), findsOneWidget);
    expect(_row(2), findsNothing);
    expect(
      fixture.chat.inboxFilters.queryFor(ChatInboxPlace.side, _site),
      'general',
    );
    expect(
      fixture.chat.inboxFilters.queryFor(ChatInboxPlace.page, _site),
      isEmpty,
      reason: 'The page keeps words of its own',
    );
  });

  testWidgets('voice rooms close the list under their own heading and are '
      'found by name', (tester) async {
    final fixture = await _pump(tester);
    final rooms = _Rooms();
    addTearDown(rooms.dispose);
    addTearDown(fixture.rooms.attach(rooms));
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    await tester.pumpAndSettle();
    final heading = find.byKey(
      const ValueKey('chat-inbox-voice-rooms-heading'),
    );
    await tester.ensureVisible(find.text('Quiet room'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(heading).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('chat-inbox-channels-card')))
            .dy,
      ),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('chat-inbox-room-1')),
          matching: find.byType(DAvatar),
        ),
      ),
      const Size.square(40),
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-search-entry')),
      'quiet',
    );
    await tester.pumpAndSettle();
    expect(find.text('Quiet room'), findsOneWidget);
    expect(find.text('Watercooler'), findsNothing);
    expect(find.textContaining('None of your chats match'), findsNothing);
  });
}

Finder _row(int id) => find.byKey(ValueKey('chat-inbox-channel-$id'));

Finder _in(int id, Finder matching) =>
    find.descendant(of: _row(id), matching: matching);

Finder _mark(int id) => _in(id, find.byType(ChatConversationAvatar));

/// The row's tail is its only text that is neither its name nor its line.
Finder _timeOf(WidgetTester tester, int id) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data != null &&
      RegExp(r'^\d{1,2}:\d{2}').hasMatch(widget.data!),
);

Widget _side() => Builder(
  builder: (context) {
    final section = const ChatPlugin()
        .sidebarSections(context)
        .singleWhere((section) => section.id == 'chat-inbox');
    return DSidebarContent.slivers(
      header: Builder(builder: section.pinnedHeaderBuilder!),
      slivers: [Builder(builder: section.bodyBuilder!)],
    );
  },
);

class _Fixture {
  _Fixture(this.shell, this.chat, this.rooms, this.show);
  final ShellController shell;
  final ChatController chat;
  final ChatInboxRooms rooms;
  final Future<void> Function(Widget) show;
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = FakeDiscourseApi(
    user: _user,
    totals: chatNotificationTotals(),
    siteConfigs: {_site: _config},
    chatChannelsBySite: {
      _site: ChatChannels(
        public: _public(),
        direct: _direct(),
        hasThreads: true,
      ),
    },
  );
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user, config: _config),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  late BuildContext scope;
  Future<void> show(Widget child) async {
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: PluginUiScope.own(
          chatPluginId,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forBrightness(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.macOS),
            builder: nativeUiEvidenceBuilder,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  scope = context;
                  return child;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await show(const SizedBox.shrink());
  final chat = PluginUiScope.require(scope, chatControllerService);
  await chat.loadChannels(_site);
  PluginUiScope.require(scope, chatShellService).openChats();
  await tester.pumpAndSettle();
  return _Fixture(
    shell,
    chat,
    PluginUiScope.require(scope, chatInboxRoomsService),
    show,
  );
}

class _Rooms extends ChangeNotifier implements ChatInboxRoomProvider {
  @override
  bool available(String siteUrl) => true;
  @override
  List<ChatInboxRoom> rooms(String siteUrl) => [
    ChatInboxRoom(id: 1, name: 'Watercooler', people: 3, open: (_) async {}),
    ChatInboxRoom(id: 2, name: 'Quiet room', people: 0, open: (_) async {}),
  ];
}
