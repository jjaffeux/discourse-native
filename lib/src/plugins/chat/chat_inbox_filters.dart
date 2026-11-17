import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'chat_channel.dart';

enum ChatInboxSort { byType, newest }

enum ChatInboxKind { all, channels, directMessages, voiceRooms }

enum ChatChannelJoinedFilter { all, joined, notJoined }

/// What the channel panel and the Threads page are narrowed to, kept for a
/// forum between one visit and the next.
final class ChatBrowseFilters {
  /// Open channels unless asked for the rest, as those are the ones to join.
  ChatChannelBrowseStatus status = ChatChannelBrowseStatus.open;

  /// What can be joined, as the chats a reader is in are already listed.
  ChatChannelJoinedFilter membership = ChatChannelJoinedFilter.notJoined;
  int? threadChannelId;
}

@immutable
final class ChatInboxFilter {
  const ChatInboxFilter({
    this.kind = ChatInboxKind.all,
    this.sort = ChatInboxSort.byType,
  });

  final ChatInboxKind kind;
  final ChatInboxSort sort;

  ChatInboxFilter copyWith({ChatInboxKind? kind, ChatInboxSort? sort}) =>
      ChatInboxFilter(kind: kind ?? this.kind, sort: sort ?? this.sort);

  @override
  bool operator ==(Object other) =>
      other is ChatInboxFilter && other.kind == kind && other.sort == sort;

  @override
  int get hashCode => Object.hash(kind, sort);
}

/// Where chat's list is shown. Each place keeps the words it is narrowed to.
enum ChatInboxPlace { page, side }

/// The inbox filters a reader chose for each forum. Held beside the chat
/// controller rather than in a widget so the choice survives switching sidebar
/// panels, visiting a conversation, and crossing the mobile breakpoint.
/// Deliberately separate from the controller's own notifications: changing a
/// filter redraws only the inbox.
final class ChatInboxFilters extends FrameSafeNotifier {
  final Map<String, ChatInboxFilter> _filters = {};
  final Map<String, ChatBrowseFilters> _browseFilters = {};
  final Map<(ChatInboxPlace, String), String> _queries = {};
  final Set<String> _expandedSidebarRooms = {};

  bool sidebarRoomsExpandedFor(String siteUrl) =>
      _expandedSidebarRooms.contains(siteUrl);

  void setSidebarRoomsExpanded(String siteUrl, bool expanded) {
    if (sidebarRoomsExpandedFor(siteUrl) == expanded) return;
    if (expanded) {
      _expandedSidebarRooms.add(siteUrl);
    } else {
      _expandedSidebarRooms.remove(siteUrl);
    }
    notifySafely();
  }

  /// The words [place] is narrowed to, as typed.
  String queryFor(ChatInboxPlace place, String siteUrl) =>
      _queries[(place, siteUrl)] ?? '';

  void setQuery(ChatInboxPlace place, String siteUrl, String query) {
    if (queryFor(place, siteUrl) == query) return;
    if (query.isEmpty) {
      _queries.remove((place, siteUrl));
    } else {
      _queries[(place, siteUrl)] = query;
    }
    notifySafely();
  }

  String sidebarQueryFor(String siteUrl) =>
      queryFor(ChatInboxPlace.side, siteUrl);

  void setSidebarQuery(String siteUrl, String query) =>
      setQuery(ChatInboxPlace.side, siteUrl, query);

  ChatBrowseFilters browseFor(String siteUrl) =>
      _browseFilters.putIfAbsent(siteUrl, ChatBrowseFilters.new);

  ChatInboxFilter filterFor(String siteUrl) =>
      _filters[siteUrl] ?? const ChatInboxFilter();

  void update(String siteUrl, ChatInboxFilter filter) {
    if (filterFor(siteUrl) == filter) return;
    if (filter == const ChatInboxFilter()) {
      _filters.remove(siteUrl);
    } else {
      _filters[siteUrl] = filter;
    }
    notifySafely();
  }

  void forget(String siteUrl) {
    _browseFilters.remove(siteUrl);
    _expandedSidebarRooms.remove(siteUrl);
    final queries = _queries.length;
    _queries.removeWhere((key, _) => key.$2 == siteUrl);
    if (_filters.remove(siteUrl) != null || _queries.length != queries) {
      notifySafely();
    }
  }
}

bool chatInboxWordsMatch(String query, Iterable<String?> fields) {
  final text = fields.whereType<String>().join('\n').toLowerCase();
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(text.contains);
}
