import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

enum ChatInboxKind { all, channels, directMessages }

@immutable
final class ChatInboxFilter {
  const ChatInboxFilter({
    this.kind = ChatInboxKind.all,
    this.unreadOnly = false,
  });

  final ChatInboxKind kind;
  final bool unreadOnly;

  ChatInboxFilter copyWith({ChatInboxKind? kind, bool? unreadOnly}) =>
      ChatInboxFilter(
        kind: kind ?? this.kind,
        unreadOnly: unreadOnly ?? this.unreadOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatInboxFilter &&
      other.kind == kind &&
      other.unreadOnly == unreadOnly;

  @override
  int get hashCode => Object.hash(kind, unreadOnly);
}

/// The inbox filters a reader chose for each forum. Held beside the chat
/// controller rather than in a widget so the choice survives switching sidebar
/// panels, visiting a conversation, and crossing the mobile breakpoint.
/// Deliberately separate from the controller's own notifications: changing a
/// filter redraws only the inbox.
final class ChatInboxFilters extends FrameSafeNotifier {
  final Map<String, ChatInboxFilter> _filters = {};

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
    if (_filters.remove(siteUrl) != null) notifySafely();
  }
}
