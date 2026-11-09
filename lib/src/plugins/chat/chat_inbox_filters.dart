import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'chat_channel.dart';

enum ChatInboxSort { byType, newest }

enum ChatInboxKind { all, channels, directMessages, voiceRooms }

enum ChatChannelJoinedFilter { all, joined, notJoined }

/// Directory choices survive moving between the peer chat routes.
final class ChatBrowseFilters {
  String query = '';
  ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all;
  ChatChannelJoinedFilter membership = ChatChannelJoinedFilter.all;
  int? threadChannelId;
}

@immutable
final class ChatInboxFilter {
  const ChatInboxFilter({
    this.kind = ChatInboxKind.all,
    this.unreadOnly = false,
    this.sort = ChatInboxSort.byType,
  });

  final ChatInboxKind kind;
  final bool unreadOnly;
  final ChatInboxSort sort;

  ChatInboxFilter copyWith({
    ChatInboxKind? kind,
    bool? unreadOnly,
    ChatInboxSort? sort,
  }) => ChatInboxFilter(
    kind: kind ?? this.kind,
    unreadOnly: unreadOnly ?? this.unreadOnly,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatInboxFilter &&
      other.kind == kind &&
      other.unreadOnly == unreadOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(kind, unreadOnly, sort);
}

/// The inbox filters a reader chose for each forum. Held beside the chat
/// controller rather than in a widget so the choice survives switching sidebar
/// panels, visiting a conversation, and crossing the mobile breakpoint.
/// Deliberately separate from the controller's own notifications: changing a
/// filter redraws only the inbox.
final class ChatInboxFilters extends FrameSafeNotifier {
  final Map<String, ChatInboxFilter> _filters = {};
  final Map<String, ChatBrowseFilters> _browseFilters = {};
  final Map<String, String> _sidebarQueries = {};
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

  String sidebarQueryFor(String siteUrl) => _sidebarQueries[siteUrl] ?? '';

  void setSidebarQuery(String siteUrl, String query) {
    if (sidebarQueryFor(siteUrl) == query) return;
    if (query.isEmpty) {
      _sidebarQueries.remove(siteUrl);
    } else {
      _sidebarQueries[siteUrl] = query;
    }
    notifySafely();
  }

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
    final hadQuery = _sidebarQueries.remove(siteUrl) != null;
    if (_filters.remove(siteUrl) != null || hadQuery) notifySafely();
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
