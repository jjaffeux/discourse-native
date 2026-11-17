import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/write_failure.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_ui_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_panel.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'joffreyj');
const _open = ChatChannelBrowseStatus.open;
const _pageSize = ChatChannelBrowsePage.pageSize;

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets(
      'channels are browsed in a panel that opens on Not joined and Open '
      'on $platform',
      (tester) async {
        final phone = platform == TargetPlatform.iOS;
        final api = _PanelApi(
          chatBrowsePagesByKey: {
            _key(): ChatChannelBrowsePage(
              channels: [
                _channel(1, following: true),
                _channel(
                  2,
                  members: 12,
                  description:
                      'Where the design team talks through what it is '
                      'drawing, asks for a second pair of eyes and settles '
                      'what ships. Long enough to need more than one line.',
                ),
                _channel(3, members: 1),
              ],
            ),
          },
        );
        await _pumpPanel(tester, api, phone: phone);

        expect(api.chatBrowseRequested.single.status, _open);
        expect(_row(1), findsNothing, reason: 'Already joined');
        expect(_row(2), findsOneWidget);
        expect(_row(3), findsOneWidget);
        expect(find.text('Find a channel'), findsOneWidget);
        expect(_chosen(tester, 'Not joined'), isTrue);
        expect(_chosen(tester, 'All'), isFalse);
        expect(_chosen(tester, 'Open'), isTrue);
        expect(_chosen(tester, 'Closed'), isFalse);

        final row = tester.getRect(_row(2));
        final mark = find.descendant(
          of: _row(2),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.hashtag,
          ),
        );
        expect(mark, findsOneWidget);
        expect(
          find.descendant(of: _row(2), matching: find.textContaining('· 12')),
          findsOneWidget,
          reason: 'How many are in it stands after its name',
        );
        final about = find.descendant(
          of: _row(2),
          matching: find.textContaining('Where the design team'),
        );
        expect(
          tester.getSize(about).height,
          greaterThan(tester.getSize(_join(2)).height),
          reason: 'What it is about is given in full, over several lines',
        );
        expect(
          tester.getRect(about).top,
          greaterThan(tester.getRect(mark).bottom),
        );
        expect(
          tester.getRect(about).left,
          lessThan(tester.getRect(mark).right),
          reason: 'It runs across the row, under the mark',
        );
        expect(tester.getRect(_join(2)).right, lessThanOrEqualTo(row.right));
        expect(
          find.descendant(of: _join(2), matching: find.text('Join')),
          findsOneWidget,
        );

        final field = tester.getRect(_field);
        final chips = tester.getRect(_membership);
        expect(field.bottom, lessThan(row.top));
        expect(
          chips.top,
          greaterThan(tester.getRect(_row(3)).bottom),
          reason: 'What narrows the channels stands at the panel\'s foot',
        );
        if (phone) {
          expect(find.text('Channels'), findsNothing);
          expect(find.byType(DSheetContent), findsOneWidget);
          expect(
            tester
                .widget<DSheetContent>(find.byType(DSheetContent))
                .semanticLabel,
            'Channels',
          );
        } else {
          expect(find.byType(DDialogContent), findsOneWidget);
          expect(find.text('Channels'), findsOneWidget);
          expect(tester.getSize(find.byType(DDialogContent)).width, 380);
        }
        await captureNativeUi(
          tester,
          'channel-panel-browse-${phone ? 'phone' : 'desktop'}',
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('a channel is joined and left from its row', (tester) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2), _channel(3)]),
      },
    );
    final controller = await _pumpPanel(tester, api);
    final chat = controller.pluginSession.require(chatControllerService);

    final gate = api.followGate = Completer<void>();
    await tester.tap(_join(2));
    await tester.pump();
    expect(api.chatChannelFollowsUpdated, const [
      (channelId: 2, following: true),
    ]);
    expect(
      tester.widget<DToggle>(_join(2)).readOnly,
      isTrue,
      reason: 'A second press cannot overtake the join still being answered',
    );
    await tester.tap(_join(2), warnIfMissed: false);
    await tester.pump();
    expect(api.chatChannelFollowsUpdated, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();

    expect(chat.channel(_site, 2)?.membership.following, isTrue);
    expect(_row(2), findsNothing, reason: 'Joined, so no longer Not joined');
    expect(_row(3), findsOneWidget);
    expect(controller.currentContent?.id, isNot('chat-c-2'));

    await _press(tester, 'Joined');
    expect(_row(3), findsNothing);
    expect(
      find.descendant(of: _leave(2), matching: find.text('Leave')),
      findsOneWidget,
    );
    api.followGate = null;
    await tester.tap(_leave(2));
    await tester.pumpAndSettle();
    expect(api.chatChannelFollowsUpdated.last, (
      channelId: 2,
      following: false,
    ));
    expect(chat.channel(_site, 2)?.membership.following, isFalse);
    expect(_row(2), findsNothing, reason: 'Left, so no longer Joined');

    await _press(tester, 'All');
    expect(_join(2), findsOneWidget);
    expect(_join(3), findsOneWidget);
  });

  testWidgets('a refused join says why and leaves the row as it was', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [_channel(2), _channel(3, canJoin: false)],
        ),
      },
    )..followFailure = const WriteException(WriteFailure.forbidden);
    await _pumpPanel(tester, api);

    expect(tester.widget<DToggle>(_join(3)).enabled, isFalse);
    await tester.tap(_join(2));
    await tester.pumpAndSettle();
    expect(
      find.text(const WriteException(WriteFailure.forbidden).message),
      findsOneWidget,
    );
    expect(_join(2), findsOneWidget);
  });

  testWidgets('the chips narrow by membership here and by status there', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [_channel(1, following: true), _channel(2)],
        ),
        _key(status: ChatChannelBrowseStatus.closed): ChatChannelBrowsePage(
          channels: [_channel(4, status: ChatChannelStatus.closed)],
        ),
        _key(status: ChatChannelBrowseStatus.all): ChatChannelBrowsePage(
          channels: [
            _channel(2),
            _channel(4, status: ChatChannelStatus.closed),
            _channel(5, status: ChatChannelStatus.archived),
          ],
        ),
      },
    );
    await _pumpPanel(tester, api);

    await _press(tester, 'All');
    expect(_row(1), findsOneWidget);
    expect(_row(2), findsOneWidget);
    expect(api.chatBrowseRequested, hasLength(1), reason: 'Narrowed here');
    await _press(tester, 'Joined');
    expect(_row(1), findsOneWidget);
    expect(_row(2), findsNothing);

    await _press(tester, 'Not joined');
    await _press(tester, 'Closed');
    expect(api.chatBrowseRequested.last.status, ChatChannelBrowseStatus.closed);
    expect(_row(4), findsOneWidget);
    expect(
      find.descendant(of: _row(4), matching: find.textContaining('Closed')),
      findsOneWidget,
      reason: 'A channel that is not open says so beside its members',
    );
    expect(
      tester.widget<DToggle>(_join(4)).enabled,
      isFalse,
      reason: 'The server lets nobody join a closed channel',
    );

    await _press(tester, 'Closed');
    expect(
      api.chatBrowseRequested.last.status,
      ChatChannelBrowseStatus.all,
      reason: 'Pressing the status chosen lets every status back in',
    );
    expect(_chosen(tester, 'Closed'), isFalse);
    expect(_row(2), findsOneWidget);
    expect(_row(5), findsOneWidget);
  });

  testWidgets('what was chosen at the foot is kept for the next opening', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
        _key(status: ChatChannelBrowseStatus.archived):
            const ChatChannelBrowsePage(),
      },
    );
    await _pumpPanel(tester, api);
    await _press(tester, 'Joined');
    await _press(tester, 'Archived');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(_chosen(tester, 'Joined'), isTrue);
    expect(_chosen(tester, 'Archived'), isTrue);
    expect(
      api.chatBrowseRequested.last.status,
      ChatChannelBrowseStatus.archived,
    );
  });

  testWidgets('a channel is found by name along the field', (tester) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2), _channel(3)]),
        _key(filter: 'des'): ChatChannelBrowsePage(channels: [_channel(3)]),
        _key(filter: 'zzz'): const ChatChannelBrowsePage(),
      },
    );
    await _pumpPanel(tester, api);

    await tester.enterText(_field, 'des');
    await tester.pump(const Duration(milliseconds: 349));
    expect(api.chatBrowseRequested, hasLength(1), reason: 'Still typing');
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(api.chatBrowseRequested.last.filter, 'des');
    expect(_row(2), findsNothing);
    expect(_row(3), findsOneWidget);

    await tester.enterText(_field, 'zzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('No channels match “zzz”'), findsOneWidget);
  });

  testWidgets('the panel opens holding the words it was asked with', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(filter: 'design'): ChatChannelBrowsePage(channels: [_channel(3)]),
      },
    );
    await _pumpPanel(tester, api, words: 'design');
    expect(api.chatBrowseRequested.single.filter, 'design');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: _field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'design',
    );
    expect(_row(3), findsOneWidget);
  });

  testWidgets('pressing a channel opens it and puts the panel away', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
      },
      chatChannelsById: {2: _channel(2)},
    );
    final controller = await _pumpPanel(tester, api);
    await tester.tap(
      find.descendant(of: _row(2), matching: find.textContaining('Channel 2')),
    );
    await tester.pumpAndSettle();
    expect(controller.currentContent?.id, 'chat-c-2');
    expect(_field, findsNothing);
    expect(api.chatChannelFollowsUpdated, isEmpty);
  });

  testWidgets('a channel that cannot be opened says so and keeps the panel', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
      },
    );
    final controller = await _pumpPanel(tester, api);
    await tester.tap(
      find.descendant(of: _row(2), matching: find.textContaining('Channel 2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not open this channel.'), findsOneWidget);
    expect(_field, findsOneWidget);
    expect(controller.currentContent?.id, isNot('chat-c-2'));
  });

  testWidgets('rows stand in for the channels until the first page answers', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
      },
    );
    final gate = api.hold(_key());
    await _pumpPanel(tester, api, settle: false);
    expect(_skeleton, findsOneWidget);
    expect(_row(2), findsNothing);
    expect(find.text('No channels match these filters.'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(_skeleton, findsNothing);
    expect(_row(2), findsOneWidget);
  });

  testWidgets('a first page that fails is asked for again from the start', (
    tester,
  ) async {
    final api = _PanelApi(chatBrowsePagesByKey: {});
    await _pumpPanel(tester, api);
    expect(_retry, findsOneWidget);
    expect(_row(2), findsNothing);

    api.chatBrowsePagesByKey[_key()] = ChatChannelBrowsePage(
      channels: [_channel(2)],
    );
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, 0]);
    expect(_row(2), findsOneWidget);
    expect(_retry, findsNothing);
  });

  testWidgets('scrolling to the end lists the next page once', (tester) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [for (var id = 1; id <= _pageSize; id++) _channel(id)],
          hasMore: true,
        ),
        _key(offset: _pageSize): ChatChannelBrowsePage(
          channels: [_channel(_pageSize), _channel(_pageSize + 1)],
        ),
      },
    );
    await _pumpPanel(tester, api);
    expect(_offsets(api), [0]);

    await tester.scrollUntilVisible(
      _row(_pageSize + 1),
      300,
      scrollable: _scrollable,
    );
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, _pageSize]);
    expect(_row(_pageSize + 1), findsOneWidget);
    expect(
      _row(_pageSize),
      findsOneWidget,
      reason: 'A channel the next page repeats is listed once',
    );
  });

  testWidgets('a next page that fails waits for Try again', (tester) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [for (var id = 1; id <= _pageSize; id++) _channel(id)],
          hasMore: true,
        ),
      },
    );
    await _pumpPanel(tester, api);
    await tester.scrollUntilVisible(_retry, 300, scrollable: _scrollable);
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, _pageSize]);
    await tester.drag(_list, const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.drag(_list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, _pageSize], reason: 'Scrolling does not retry');

    api.chatBrowsePagesByKey[_key(offset: _pageSize)] = ChatChannelBrowsePage(
      channels: [_channel(_pageSize + 1)],
    );
    await tester.ensureVisible(_retry);
    await tester.tap(_retry);
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, _pageSize, _pageSize]);
    await tester.scrollUntilVisible(
      _row(_pageSize + 1),
      300,
      scrollable: _scrollable,
    );
    expect(_row(_pageSize + 1), findsOneWidget);
  });

  testWidgets('pages with nothing to join are read on until one has', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [
            for (var id = 1; id <= _pageSize; id++)
              _channel(id, following: true),
          ],
          hasMore: true,
        ),
        _key(offset: _pageSize): ChatChannelBrowsePage(
          channels: [
            for (var id = _pageSize + 1; id <= _pageSize * 2; id++)
              _channel(id, following: true),
          ],
          hasMore: true,
        ),
        _key(offset: _pageSize * 2): ChatChannelBrowsePage(
          channels: [_channel(99)],
        ),
      },
    );
    final second = api.hold(_key(offset: _pageSize));
    await _pumpPanel(tester, api, settle: false);
    expect(find.text('No matching channels loaded yet.'), findsOneWidget);
    expect(_offsets(api), [0, _pageSize]);
    second.complete();
    await tester.pumpAndSettle();
    expect(_offsets(api), [0, _pageSize, _pageSize * 2]);
    expect(_row(99), findsOneWidget);
    expect(find.text('No matching channels loaded yet.'), findsNothing);
  });

  testWidgets('a page answered after the words changed is not listed', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
        _key(filter: 'des'): ChatChannelBrowsePage(channels: [_channel(3)]),
      },
    );
    final first = api.hold(_key());
    await _pumpPanel(tester, api, settle: false);
    await tester.enterText(_field, 'des');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_row(3), findsOneWidget);
    first.complete();
    await tester.pumpAndSettle();
    expect(_row(2), findsNothing);
    expect(_row(3), findsOneWidget);
  });

  testWidgets('the keyboard goes from the field through each row and its '
      'chip to what narrows them', (tester) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(channels: [_channel(2)]),
      },
    );
    await _pumpPanel(tester, api);
    bool within(Finder finder) {
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus == null) return false;
      final target = tester.element(finder);
      var found = focus == target;
      focus.visitAncestorElements((element) {
        found = found || element == target;
        return !found;
      });
      return found;
    }

    expect(within(_field), isTrue, reason: 'A desktop opens ready to type');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(within(_row(2)), isTrue);
    expect(within(_join(2)), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(within(_join(2)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(within(_membership), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      within(find.byKey(const ValueKey('chat-channel-panel-status'))),
      isTrue,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a channel left from elsewhere leaves the Joined it was under', (
    tester,
  ) async {
    final api = _PanelApi(
      chatBrowsePagesByKey: {
        _key(): ChatChannelBrowsePage(
          channels: [
            _channel(1, following: true),
            _channel(2, following: true),
          ],
        ),
      },
      chatChannelsBySite: {
        _site: ChatChannels(
          public: [_channel(1, following: true), _channel(2, following: true)],
        ),
      },
    );
    final controller = await _pumpPanel(tester, api, loadChannels: true);
    final chat = controller.pluginSession.require(chatControllerService);
    await _press(tester, 'Joined');
    expect(_row(1), findsOneWidget);
    expect(_row(2), findsOneWidget);

    expect(
      await chat.updateChannelFollowing(_site, chat.channel(_site, 2)!, false),
      isNull,
    );
    await tester.pumpAndSettle();
    expect(_row(1), findsOneWidget);
    expect(_row(2), findsNothing);
  });

  testWidgets('what is said in a channel does not lay the panel out again', (
    tester,
  ) async {
    final channels = [
      for (var id = 1; id <= 12; id++) _channel(id, following: true),
    ];
    final api = _PanelApi(
      chatBrowsePagesByKey: {_key(): ChatChannelBrowsePage(channels: channels)},
      chatChannelsBySite: {_site: ChatChannels(public: channels)},
    );
    await _pumpPanel(tester, api, loadChannels: true);
    await _press(tester, 'Joined');
    final tracker = FakeSiteTracker.built.lastWhere((t) => t.siteUrl == _site);

    var panels = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, built) {
      previous?.call(element, built);
      if (element.widget is ChatChannelPanel) panels++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    for (var index = 0; index < 10; index++) {
      tracker.deliverPluginMessage('/chat/3/new-messages', {
        'type': 'channel',
        'channel_id': 3,
        'message': {
          'id': 2000 + index,
          'chat_channel_id': 3,
          'cooked': '<p>Busy.</p>',
          'created_at': DateTime.utc(2026, 10, 2, 0, index).toIso8601String(),
          'user': {'id': 2, 'username': 'sam'},
        },
      });
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = previous;
    expect(tester.takeException(), isNull);
    expect(panels, 0);
    expect(_row(3), findsOneWidget);
  });

  testWidgets(
    'a phone keeps its keyboard up while the panel under the field is pressed',
    (tester) async {
      final api = _PanelApi(
        chatBrowsePagesByKey: {
          _key(): ChatChannelBrowsePage(
            channels: [_channel(1, following: true), _channel(2)],
          ),
        },
      );
      await _pumpPanel(tester, api, phone: true);
      final field = tester.widget<EditableText>(
        find.descendant(of: _field, matching: find.byType(EditableText)),
      );
      expect(field.focusNode.hasFocus, isFalse, reason: 'No keyboard unasked');
      await tester.tap(_field);
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      await _press(tester, 'All');
      expect(_row(1), findsOneWidget);
      expect(field.focusNode.hasFocus, isTrue);
      await tester.tap(_join(2));
      await tester.pumpAndSettle();
      expect(field.focusNode.hasFocus, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

final _field = find.byKey(const ValueKey('chat-channel-panel-field'));
final _list = find.byKey(const ValueKey('chat-channel-panel-list'));
final _membership = find.byKey(const ValueKey('chat-channel-panel-membership'));
final _skeleton = find.byKey(const ValueKey('chat-channel-panel-skeleton'));
final _retry = find.byKey(const ValueKey('chat-channel-panel-retry'));
final _scrollable = find
    .descendant(of: _list, matching: find.byType(Scrollable))
    .first;

Finder _row(int id) => find.byKey(ValueKey('chat-channel-panel-channel-$id'));
Finder _join(int id) => find.byKey(ValueKey('chat-channel-panel-join-$id'));
Finder _leave(int id) => find.byKey(ValueKey('chat-channel-panel-leave-$id'));

Finder _chip(String label) => find.descendant(
  of: find.byType(DSheetScrollBody),
  matching: find.widgetWithText(DToggle, label),
);

bool _chosen(WidgetTester tester, String label) =>
    tester.widget<DToggle>(_chip(label)).pressed == true;

Future<void> _press(WidgetTester tester, String label) async {
  await tester.ensureVisible(_chip(label));
  await tester.pumpAndSettle();
  await tester.tap(_chip(label));
  await tester.pumpAndSettle();
}

Iterable<int> _offsets(FakeDiscourseApi api) =>
    api.chatBrowseRequested.map((request) => request.offset);

String _key({
  String filter = '',
  ChatChannelBrowseStatus status = _open,
  int offset = 0,
}) => FakeDiscourseApi.chatBrowseKey(
  filter: filter,
  status: status,
  offset: offset,
);

ChatChannel _channel(
  int id, {
  bool following = false,
  bool canJoin = true,
  int members = 0,
  String? description,
  ChatChannelStatus status = ChatChannelStatus.open,
}) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  canJoin: canJoin,
  status: status,
  description: description,
  membershipsCount: members,
  membership: ChatMembership(following: following),
);

Future<ShellController> _pumpPanel(
  WidgetTester tester,
  FakeDiscourseApi api, {
  bool phone = false,
  bool settle = true,
  bool loadChannels = false,
  String words = '',
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await prepareNativeUiEvidence(tester);
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(Uri.parse(_site).host).copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  if (loadChannels) {
    await controller.pluginSession
        .require(chatControllerService)
        .loadChannels(_site);
  }
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: ContentSettingsScope(
        controller: controller.appSettings,
        child: PluginUiScope.own(
          chatPluginId,
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) =>
                nativeUiEvidenceBuilder(context, DToaster(child: child!)),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: DButton(
                    label: const Text('Browse'),
                    onPressed: () => unawaited(
                      showChatChannelBrowser(
                        context,
                        siteUrl: _site,
                        words: words,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Browse'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  return controller;
}

class _PanelApi extends FakeDiscourseApi {
  _PanelApi({
    required Map<String, ChatChannelBrowsePage> chatBrowsePagesByKey,
    super.chatChannelsById,
    super.chatChannelsBySite,
  }) : super(user: _user, chatBrowsePagesByKey: {...chatBrowsePagesByKey});

  final _gates = <String, Completer<void>>{};
  Completer<void>? followGate;
  WriteException? followFailure;

  Future<ChatMembership> _answer(Future<ChatMembership> write) async {
    await followGate?.future;
    if (followFailure case final failure?) throw failure;
    return write;
  }

  @override
  Future<ChatMembership> followChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _answer(
    super.followChatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      clientId: clientId,
    ),
  );

  @override
  Future<ChatMembership> unfollowChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _answer(
    super.unfollowChatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      clientId: clientId,
    ),
  );

  Completer<void> hold(String key) {
    final gate = _gates[key] = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    return gate;
  }

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    final key = FakeDiscourseApi.chatBrowseKey(
      filter: filter,
      status: status,
      offset: offset,
    );
    try {
      return await super.browseChatChannels(
        siteUrl: siteUrl,
        apiKey: apiKey,
        filter: filter,
        status: status,
        offset: offset,
        limit: limit,
        clientId: clientId,
      );
    } finally {
      await _gates[key]?.future;
    }
  }
}
