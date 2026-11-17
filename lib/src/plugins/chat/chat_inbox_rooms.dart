import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/widgets.dart';

import 'chat_inbox_filters.dart';

const chatInboxRoomsService = PluginServiceKey<ChatInboxRooms>(
  owner: PluginId('chat'),
  name: 'inbox-rooms',
);

/// Voice supplies room data and actions without making Chat depend on Voice.
abstract interface class ChatInboxRoomProvider implements Listenable {
  bool available(String siteUrl);
  List<ChatInboxRoom> rooms(String siteUrl);
}

/// Optional capability; the Voice plugin owns permissions and the form.
abstract interface class ChatInboxRoomCreator {
  Future<void> Function(BuildContext context)? createRoom(String siteUrl);
}

final class ChatInboxRoom {
  const ChatInboxRoom({
    required this.id,
    required this.name,
    required this.people,
    required this.open,
    this.loading = false,
  });
  final int id;
  final String name;
  final int people;
  final Future<void> Function(BuildContext context) open;
  final bool loading;
}

final class ChatInboxRooms extends FrameSafeNotifier {
  ChatInboxRooms(this.filters, {required this.listedInSide});
  final ChatInboxFilters filters;

  /// Whether chat's own list stands beside the forum for a site, carrying
  /// the rooms as its rows. Without chat there is no such list, and the rooms'
  /// provider lists them in a section of its own.
  final bool Function(String siteUrl) listedInSide;
  ChatInboxRoomProvider? _provider;

  bool available(String siteUrl) => _provider?.available(siteUrl) ?? false;

  Future<void> Function(BuildContext context)? createRoom(String siteUrl) =>
      switch (_provider) {
        final ChatInboxRoomCreator creator => creator.createRoom(siteUrl),
        _ => null,
      };

  bool includesRooms(String siteUrl) =>
      switch (filters.filterFor(siteUrl).kind) {
        ChatInboxKind.all || ChatInboxKind.voiceRooms => true,
        _ => false,
      };

  List<ChatInboxRoom> rooms(String siteUrl) => !includesRooms(siteUrl)
      ? const []
      : _provider?.rooms(siteUrl) ?? const [];

  /// The rooms [place] lists: all of them, or those its words name.
  List<ChatInboxRoom> roomsFor(ChatInboxPlace place, String siteUrl) {
    final query = filters.queryFor(place, siteUrl);
    return [
      for (final room in rooms(siteUrl))
        if (chatInboxWordsMatch(query, [room.name])) room,
    ];
  }

  List<ChatInboxRoom> sidebarRooms(String siteUrl) =>
      roomsFor(ChatInboxPlace.side, siteUrl);

  VoidCallback attach(ChatInboxRoomProvider provider) {
    _provider?.removeListener(notifySafely);
    _provider = provider..addListener(notifySafely);
    notifySafely();
    return () {
      if (!identical(_provider, provider)) return;
      provider.removeListener(notifySafely);
      _provider = null;
      notifySafely();
    };
  }

  @override
  void dispose() {
    _provider?.removeListener(notifySafely);
    super.dispose();
  }
}
