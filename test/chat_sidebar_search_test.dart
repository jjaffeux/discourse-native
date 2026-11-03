import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_rooms.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_chat_inbox.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_sidebar_parity_test.dart' show capture;
import 'sidebar_panel_tabs_test.dart' as panels;
import 'support/load_test_fonts.dart';
import 'support/native_ui_evidence.dart';

final _field = find.byKey(const ValueKey('chat-search-entry'));
Finder _row(int id) => find.byKey(ValueKey('chat-inbox-channel-$id'));
Finder get _scroll => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.byType(CustomScrollView),
);

void main() {
  setUpAll(loadTestFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  testWidgets(
    'sidebar search uncaps matches, preserves collapses, clear and filters',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      final shell = await panels.pumpTabs(
        tester,
        threads: true,
        channels: {
          panels.site: ChatChannels(
            public: [
              for (var id = 1; id <= 7; id++)
                ChatChannel(
                  id: id,
                  title: 'Signal channel $id',
                  kind: ChatChannelKind.category,
                  membership: ChatMembership(following: true, starred: id == 1),
                ),
            ],
            direct: const [
              ChatChannel(
                id: 20,
                title: 'Signal Alice',
                kind: ChatChannelKind.directMessage,
              ),
              ChatChannel(
                id: 21,
                title: 'Signal group',
                kind: ChatChannelKind.directMessage,
                isGroup: true,
              ),
            ],
          ),
        },
      );
      await tester.tap(panels.tab('chat'));
      await tester.pumpAndSettle();
      final route = shell.currentContent;
      final filters = shell.pluginSession
          .require(chatControllerService)
          .inboxFilters;
      final bounds = tester.getRect(find.byType(DSidebar));
      expect(tester.getRect(_field).left - bounds.left, 4);
      expect(tester.getRect(_field).right - bounds.right, -4);
      expect(tester.getSize(_field).height, 30);
      await _reveal(tester, find.text('View 2 more'));

      await tester.enterText(_field, '  SiGnAl  ');
      await tester.pumpAndSettle();
      expect(filters.sidebarQueryFor(panels.site), '  SiGnAl  ');
      expect(shell.currentContent, same(route));
      expect(find.byType(ChatInboxMore), findsNothing);
      expect(_row(1), findsOneWidget);
      expect(_row(20), findsOneWidget);
      expect(_row(21), findsOneWidget);
      await tester.scrollUntilVisible(
        _row(7),
        250,
        scrollable: find
            .descendant(of: _scroll, matching: find.byType(Scrollable))
            .first,
      );
      await _reveal(tester, _row(7));
      expect(_row(7).hitTestable(), findsOneWidget);
      await capture(tester, 'chat-search-desktop-matches');

      final position = tester.widget<CustomScrollView>(_scroll).controller!;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      final heading = find.ancestor(
        of: find.text('Channels'),
        matching: find.byType(DCollapsibleTrigger),
      );
      await tester.tap(heading);
      await tester.pumpAndSettle();
      expect(_row(2).hitTestable(), findsNothing);
      await tester.enterText(_field, 'no-such-chat');
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('No chats match.')).dx - bounds.left,
        10,
      );
      await capture(tester, 'chat-search-desktop-empty');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsNothing);
      expect(
        _row(2).hitTestable(),
        findsNothing,
        reason: 'hidden sections retain their collapse state',
      );
      final editor = tester.widget<EditableText>(
        find.descendant(of: _field, matching: find.byType(EditableText)),
      );
      expect(editor.controller.text, isEmpty);
      expect(editor.focusNode.hasFocus, isTrue);
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.tap(heading);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('View 2 more'));
      filters.update(
        panels.site,
        const ChatInboxFilter(
          kind: ChatInboxKind.directMessages,
          sort: ChatInboxSort.newest,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field, '   ');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clear search'), findsOneWidget);
      expect(find.text('No chats match.'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(editor.controller.text, isEmpty);
      expect(editor.focusNode.hasFocus, isTrue);
      expect(
        filters.filterFor(panels.site),
        const ChatInboxFilter(
          kind: ChatInboxKind.directMessages,
          sort: ChatInboxSort.newest,
        ),
      );
      expect(shell.currentContent, same(route));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'rooms match by name beyond the cap and newly supplied rooms join the filter',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      final shell = await panels.pumpTabs(tester, roomCount: 12);
      await tester.tap(panels.tab('chat'));
      await tester.pumpAndSettle();
      final more = find.text('View 8 more');
      await _reveal(tester, more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('View less'));
      await tester.enterText(_field, 'no-such-room-or-chat');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('View less'));
      await tester.enterText(_field, 'VoIcE room');
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsNothing);
      expect(_row(9), findsNothing);
      expect(find.byType(ChatInboxMore), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Voice room 11'),
        250,
        scrollable: find
            .descendant(of: _scroll, matching: find.byType(Scrollable))
            .first,
      );
      await _reveal(tester, find.text('Voice room 11'));
      expect(find.text('Voice room 11').hitTestable(), findsOneWidget);
      final rooms = shell.pluginSession.require(voiceChatInboxService);
      final provider = _Rooms();
      final detach = rooms.attach(provider);
      addTearDown(detach);
      addTearDown(provider.dispose);
      await tester.enterText(_field, 'new salon');
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsOneWidget);
      provider.add('New local salon');
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsNothing);
      expect(find.text('New local salon'), findsOneWidget);
      expect(rooms.sidebarRooms(panels.site).single.name, 'New local salon');
      expect(
        rooms.rooms(panels.site),
        hasLength(2),
        reason: 'full Chats page remains unfiltered',
      );
      await tester.enterText(_field, 'New salon missing');
      await tester.pumpAndSettle();
      expect(find.text('No chats match.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Future<void> _reveal(WidgetTester tester, Finder item) async {
  for (var i = 0; i < 12 && item.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(_scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(item.hitTestable(), findsOneWidget);
}

class _Rooms extends ChangeNotifier implements ChatInboxRoomProvider {
  final _names = ['Watercooler'];
  void add(String name) {
    _names.add(name);
    notifyListeners();
  }

  @override
  bool available(String siteUrl) => true;
  @override
  List<ChatInboxRoom> rooms(String siteUrl) => [
    for (final (i, name) in _names.indexed)
      ChatInboxRoom(id: i + 100, name: name, people: 0, open: (_) async {}),
  ];
}
