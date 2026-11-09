import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_rooms.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dock_panel.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

final _inbox = find.byType(ChatMobileSidebar);
final _pageTitle = find.descendant(
  of: _inbox,
  matching: find.byKey(const ValueKey('chat-inbox-title')),
);
final _title = find.byKey(const ValueKey('mobile-page-title'));
final _navigation = find.byKey(const ValueKey('chat-inbox-activity-filter'));

void _mobileTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: const TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  }),
);

/// The production mobile shell on its Chat tab, with more conversations than
/// a phone shows at once.
Future<void> _pumpChatInbox(WidgetTester tester, Size size) async {
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(
        chatEnabled: true,
        publicChannelsEnabled: true,
        threadsEnabled: true,
      ),
    ),
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: _user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(),
      siteConfigs: {_site: config},
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(
          hasThreads: true,
          public: [
            for (var id = 1; id <= 20; id++)
              ChatChannel(
                id: id,
                title: 'Channel $id',
                kind: ChatChannelKind.category,
                membership: const ChatMembership(following: true),
                tracking: const ChatTracking(),
                lastMessageId: id * 100,
                lastMessageAt: DateTime.utc(2026, 10, 1, 0, 21 - id),
              ),
          ],
          direct: const [],
          newChannelBusLastId: 1,
          newMessageBusLastIds: {for (var id = 1; id <= 20; id++) id: 1},
        ),
      },
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(Scaffold).first));
  await shell.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await tester.pumpAndSettle();
  // Enlarged text on a narrow phone moves Chat into the bar's panel.
  final dockTab = find.byKey(const ValueKey('mobile-mode-panel/chat'));
  if (dockTab.evaluate().isEmpty) {
    await openDockPanel(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(DMobileDock.panelKey),
        matching: find.text('Chat'),
      ),
    );
  } else {
    await tester.tap(dockTab);
  }
  await tester.pumpAndSettle();
  expect(_inbox, findsOneWidget);
  expect(
    tester.widget<DButton>(_title).semanticLabel,
    'Back to the top of Chats',
  );
}

Future<void> _scrollInboxTo(
  WidgetTester tester,
  Finder row,
  double delta,
) async {
  for (
    var attempt = 0;
    attempt < 100 && row.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    // The inbox's own list, not its filters' sideways strips.
    final viewport = find
        .descendant(
          of: _inbox,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        )
        .last;
    // The dock overlays the viewport's lower part. Swipe its visible top edge.
    await tester.dragFrom(
      tester.getTopLeft(viewport) + const Offset(10, 10),
      Offset(0, delta),
    );
    await tester.pumpAndSettle();
  }
  expect(row.hitTestable(), findsOneWidget);
}

/// A row of the mobile inbox, kept mounted behind an open conversation. The
/// sidebar panel holds its own rows for the same channels.
Finder _row(int channelId) => find.descendant(
  of: find.byType(ChatMobileSidebar, skipOffstage: false),
  matching: find.byKey(
    ValueKey('chat-inbox-channel-$channelId'),
    skipOffstage: false,
  ),
  skipOffstage: false,
);

/// Voice's closures capture the room as last published, so a row must hold the
/// newest one even when nothing it draws changed.
final class _Rooms extends ChangeNotifier implements ChatInboxRoomProvider {
  int version = 0;
  final opened = <int>[];
  int people = 0;

  void republish() {
    version++;
    notifyListeners();
  }

  @override
  bool available(String siteUrl) => true;

  @override
  List<ChatInboxRoom> rooms(String siteUrl) {
    final published = version;
    return [
      ChatInboxRoom(
        id: 1,
        name: 'Watercooler',
        people: people,
        open: (_) async => opened.add(published),
      ),
    ];
  }
}

typedef _Rebuilds = ({
  int elements,
  int entries,
  int filterBars,
  int navigation,
});

/// What [act] redraws, counted at the framework's own rebuild seam.
Future<_Rebuilds> _countRebuilds(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  var elements = 0;
  var entries = 0;
  var filterBars = 0;
  var navigation = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    elements++;
    if (element.widget is ChatInboxEntry) entries++;
    if (element.widget is ChatInboxFilterBar) filterBars++;
    if (element.widget.key == const ValueKey('chat-inbox-channels-card')) {
      navigation++;
    }
    previous?.call(element, builtOnce);
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  await act();
  debugOnRebuildDirtyWidget = previous;
  return (
    elements: elements,
    entries: entries,
    filterBars: filterBars,
    navigation: navigation,
  );
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    await (FontLoader(
      'Open Sans',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });
  _mobileTest('channel tracking retains unrelated mobile inbox rows', (
    tester,
  ) async {
    await _pumpChatInbox(tester, phone);
    final rows = find.byType(ChatInboxRow).evaluate().toSet();
    expect(rows, isNotEmpty);
    expect(
      rows.any((row) => (row.widget as ChatInboxRow).channel.id == 20),
      isFalse,
    );
    final rebuilt = <int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (rows.contains(element)) {
        rebuilt.add((element.widget as ChatInboxRow).channel.id);
      }
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final tracker = FakeSiteTracker.built.last;
    tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
      'channel_id': 20,
      'last_read_message_id': 1,
      'unread_count': 3,
    });
    await tester.pumpAndSettle();
    expect(rebuilt, isEmpty, reason: 'Only the changed channel needs new rows');
    tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
      'channel_id': 1,
      'last_read_message_id': 1,
      'unread_count': 2,
    });
    await tester.pumpAndSettle();
    expect(rebuilt, {1});
    expect(find.text('2 messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tracking on an off-screen channel does not redraw the mobile inbox',
    (tester) async {
      await _pumpChatInbox(tester, phone);
      final frames = await _countRebuilds(tester, () async {
        final tracker = FakeSiteTracker.built.last;
        for (var event = 0; event < 10; event++) {
          tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
            'channel_id': 20,
            'last_read_message_id': 1,
            'unread_count': 3 + event,
          });
          await tester.pump(const Duration(milliseconds: 16));
        }
      });
      // ignore: avoid_print
      print('PERF_PROOF chat-mobile-inbox elements=${frames.elements}');
      // ignore: avoid_print
      print('PERF_PROOF chat-mobile-inbox entries=${frames.entries}');
      // ignore: avoid_print
      print('PERF_PROOF chat-mobile-inbox filter_bars=${frames.filterBars}');
      // ignore: avoid_print
      print('PERF_PROOF chat-mobile-inbox navigation=${frames.navigation}');
      expect(frames.entries, 0, reason: 'No visible row changed');
      expect(frames.filterBars, 0, reason: 'The filter did not change');
      expect(frames.navigation, 0, reason: 'Site settings did not change');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  group('the gated mobile inbox still redraws for', () {
    _mobileTest('a new channel', (tester) async {
      await _pumpChatInbox(tester, phone);
      expect(_row(21), findsNothing);
      FakeSiteTracker.built.last.deliverPluginMessage('/chat/new-channel', {
        'channel': {
          'id': 21,
          'title': 'Channel 21',
          'chatable_type': 'Category',
          'current_user_membership': {
            'following': true,
            'muted': false,
            'starred': false,
          },
          'last_message': {
            'id': 2100,
            'created_at': '2026-10-02T00:00:00.000Z',
          },
          'meta': {
            'message_bus_last_ids': {'new_messages': 1},
          },
        },
      });
      await tester.pumpAndSettle();
      expect(_row(21).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _mobileTest('a new message moving its channel to the top', (tester) async {
      await _pumpChatInbox(tester, phone);
      expect(_row(20), findsNothing);
      FakeSiteTracker.built.last.deliverPluginMessage('/chat/20/new-messages', {
        'type': 'channel',
        'channel_id': 20,
        'message': {
          'id': 9001,
          'chat_channel_id': 20,
          'cooked': '<p>new</p>',
          'created_at': '2026-10-02T00:00:00.000Z',
          'user': {'id': 2, 'username': 'hawk'},
        },
      });
      await tester.pumpAndSettle();
      expect(_row(20).hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(_row(20)).dy,
        lessThan(tester.getTopLeft(_row(1)).dy),
      );
      expect(tester.takeException(), isNull);
    });

    _mobileTest('a filter change', (tester) async {
      await _pumpChatInbox(tester, phone);
      FakeSiteTracker.built.last.deliverPluginMessage(
        '/chat/user-tracking-state/7',
        {'channel_id': 1, 'last_read_message_id': 1, 'unread_count': 2},
      );
      await tester.pumpAndSettle();
      final choice = find.descendant(
        of: _navigation,
        matching: find.text('Unread'),
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(_row(1), findsOneWidget);
      expect(_row(2), findsNothing);
      await tester.tap(
        find.descendant(of: _navigation, matching: find.text('Recent')),
      );
      await tester.pumpAndSettle();
      expect(_row(2), findsOneWidget);
      // The rows stay the same here; only their grouping follows the choice.
      await tester.tap(find.text('Newest'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _inbox, matching: find.text('All chats')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    _mobileTest('the open channel highlight', (tester) async {
      await _pumpChatInbox(tester, phone);
      final shell = ShellScope.read(tester.element(_inbox));
      final service = shell.pluginSession.require(chatShellService);
      DItem row(int id) => tester.widget<DItem>(_row(id));
      expect(row(2).selected, isFalse);
      service.openChannel(2);
      await tester.pumpAndSettle();
      expect(row(2).selected, isTrue);
      service.openChannel(3);
      await tester.pumpAndSettle();
      expect(row(2).selected, isFalse);
      expect(row(3).selected, isTrue);
      expect(tester.takeException(), isNull);
    });

    _mobileTest('a provider republishing a room', (tester) async {
      await _pumpChatInbox(tester, phone);
      final rooms = _Rooms();
      addTearDown(rooms.dispose);
      final shell = ShellScope.read(tester.element(_inbox));
      addTearDown(
        shell.pluginSession.require(chatInboxRoomsService).attach(rooms),
      );
      await tester.pumpAndSettle();
      rooms.republish();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-inbox-room-1')));
      await tester.pump();
      expect(rooms.opened, [1], reason: 'The row must hold the latest room');
      expect(tester.takeException(), isNull);
    });

    _mobileTest('a room status change without its channel rows', (
      tester,
    ) async {
      await _pumpChatInbox(tester, phone);
      final rooms = _Rooms();
      addTearDown(rooms.dispose);
      final shell = ShellScope.read(tester.element(_inbox));
      addTearDown(
        shell.pluginSession.require(chatInboxRoomsService).attach(rooms),
      );
      await tester.pumpAndSettle();
      expect(find.text('Empty'), findsOneWidget);
      final channelRows = find.byType(ChatInboxRow).evaluate().toSet();
      expect(channelRows, isNotEmpty);
      final redrawn = <Element>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (channelRows.contains(element)) redrawn.add(element);
        previous?.call(element, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      rooms
        ..people = 2
        ..republish();
      await tester.pumpAndSettle();

      expect(find.text('2 people here'), findsOneWidget);
      expect(find.text('Empty'), findsNothing);
      expect(redrawn, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  _mobileTest('scrolling keeps the Chat bar title and activity filter fixed', (
    tester,
  ) async {
    await _pumpChatInbox(tester, phone);
    expect(_pageTitle, findsNothing);
    expect(_title.hitTestable(), findsOneWidget);
    final title = tester.getRect(_title);
    final navigation = tester.getRect(_navigation);
    final list = find.descendant(of: _inbox, matching: find.byType(ListView));
    await tester.drag(list, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(_title.hitTestable(), findsOneWidget);
    expect(_navigation.hitTestable(), findsOneWidget);
    expect(tester.getRect(_title), title);
    expect(tester.getRect(_navigation), navigation);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'keyboard and large text keep navigation and conversations reachable',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 720));
      addTearDown(tester.view.resetViewInsets);
      for (final bottom in [280.0, 340.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pumpAndSettle();
        await _scrollInboxTo(
          tester,
          find.byKey(const ValueKey('chat-inbox-channel-20')),
          -100,
        );
        expect(
          find.byKey(const ValueKey('chat-inbox-channel-20')).hitTestable(),
          findsOneWidget,
        );
        await _scrollInboxTo(
          tester,
          find.byKey(const ValueKey('chat-inbox-channel-1')),
          100,
        );
        expect(_title.hitTestable(), findsOneWidget);
        await tester.tap(_title);
        await tester.pumpAndSettle();
        expect(_navigation.hitTestable(), findsOneWidget);
        final positions = tester
            .stateList<ScrollableState>(
              find.descendant(of: _inbox, matching: find.byType(Scrollable)),
            )
            .map((scrollable) => scrollable.position)
            .where((position) => position.axis == Axis.vertical);
        expect(positions, isNotEmpty);
        expect(positions.map((position) => position.pixels), everyElement(0));
      }
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'the Chat bar title returns to the top after dismissing the keyboard',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 1000));
      tester.view.viewInsets = const FakeViewPadding(bottom: 540);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _scrollInboxTo(
        tester,
        find.byKey(const ValueKey('chat-inbox-channel-20')),
        -150,
      );
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-20')).hitTestable(),
        findsOneWidget,
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_title.hitTestable(), findsOneWidget);
      await tester.tap(_title);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-1')).hitTestable(),
        findsOneWidget,
      );
      expect(_navigation.hitTestable(), findsOneWidget);
      final title = tester.getRect(_title);
      final navigation = tester.getRect(_navigation);
      final list = find.descendant(of: _inbox, matching: find.byType(ListView));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(_title.hitTestable(), findsOneWidget);
      expect(_navigation.hitTestable(), findsOneWidget);
      expect(tester.getRect(_title), title);
      expect(tester.getRect(_navigation), navigation);
      expect(tester.takeException(), isNull);
    },
  );
}
