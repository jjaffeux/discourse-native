import 'package:flutter/foundation.dart';

/// A stable, presentation-only identity for a native Chat screen.
///
/// Channel ids deliberately retain the route shape shipped before threading,
/// so persisted forum tabs continue to restore. A thread appends its identity
/// instead of replacing the channel: the channel remains the navigation root
/// and Back can always return to it.
@immutable
final class ChatRoute {
  const ChatRoute._({required this.channelId, this.threadId, this.infoTab});

  factory ChatRoute.channel(int channelId) {
    _requirePositiveId(channelId, 'channelId');
    return ChatRoute._(channelId: channelId);
  }

  factory ChatRoute.thread({required int channelId, required int threadId}) {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    return ChatRoute._(channelId: channelId, threadId: threadId);
  }

  factory ChatRoute.info({
    required int channelId,
    ChatChannelInfoTab tab = ChatChannelInfoTab.settings,
  }) {
    _requirePositiveId(channelId, 'channelId');
    return ChatRoute._(channelId: channelId, infoTab: tab);
  }

  final int channelId;
  final int? threadId;
  final ChatChannelInfoTab? infoTab;

  bool get isThread => threadId != null;
  bool get isInfo => infoTab != null;

  String get routeId {
    final prefix = '$_channelPrefix$channelId';
    if (threadId case final threadId?) return '$prefix$_threadMarker$threadId';
    if (infoTab case final tab?) return '$prefix$_infoMarker${tab.name}';
    return prefix;
  }

  /// Decodes only route ids minted by [routeId].
  ///
  /// Matching is anchored and ids use their canonical decimal spelling. This
  /// avoids treating prefixes, negative values, leading-zero aliases, or a
  /// future Chat route as this screen merely because it starts with `chat-c-`.
  static ChatRoute? parse(String routeId) {
    if (routeId.isEmpty || routeId.length > maximumRouteIdLength) return null;
    final match = _routePattern.firstMatch(routeId);
    if (match == null) return null;

    final channelId = int.tryParse(match.group(1)!);
    final threadId = switch (match.group(2)) {
      final value? => int.tryParse(value),
      null => null,
    };
    final infoTab = ChatChannelInfoTab.parse(match.group(3));
    if (channelId == null || channelId <= 0) return null;
    if (match.group(2) != null && (threadId == null || threadId <= 0)) {
      return null;
    }
    if (match.group(3) != null && infoTab == null) return null;
    return ChatRoute._(
      channelId: channelId,
      threadId: threadId,
      infoTab: infoTab,
    );
  }

  static const int maximumRouteIdLength = 128;
  static const String _channelPrefix = 'chat-c-';
  static const String _threadMarker = '-t-';
  static const String _infoMarker = '-info-';
  static final RegExp _routePattern = RegExp(
    r'^chat-c-([1-9][0-9]*)(?:(?:-t-([1-9][0-9]*))|(?:-info-(settings|members)))?$',
  );

  static void _requirePositiveId(int id, String name) {
    if (id <= 0) throw ArgumentError.value(id, name, 'must be positive');
  }

  @override
  bool operator ==(Object other) =>
      other is ChatRoute &&
      other.channelId == channelId &&
      other.threadId == threadId &&
      other.infoTab == infoTab;

  @override
  int get hashCode => Object.hash(channelId, threadId, infoTab);

  @override
  String toString() => 'ChatRoute($routeId)';
}

enum ChatChannelInfoTab {
  settings,
  members;

  static ChatChannelInfoTab? parse(String? value) => switch (value) {
    'settings' => settings,
    'members' => members,
    _ => null,
  };
}

/// A canonical Discourse Chat link and its optional message anchor.
@immutable
final class ChatLink {
  const ChatLink({required this.uri, required this.route, this.messageId});

  final Uri uri;
  final ChatRoute route;
  final int? messageId;

  /// The native Chat shapes Discourse itself writes, or null for any sibling
  /// route that should remain a browser link.
  ///
  /// Both a channel and a thread may name one message:
  /// `/chat/c/-/9/44` and `/chat/c/-/9/t/3/44`. The channel settings and
  /// members routes use `/chat/c/slug/9/info/{tab}`. Query strings, fragments,
  /// and one trailing slash do not alter that identity.
  static ChatLink? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    if (uri.hasScheme && (!uri.hasAuthority || uri.host.isEmpty)) return null;
    if (uri.hasAuthority && uri.host.isEmpty) return null;

    final match = _pathPattern.firstMatch(uri.path);
    if (match == null) return null;

    final channelId = int.tryParse(match.group(1)!);
    final channelMessageId = _positiveId(match.group(2));
    final threadId = _positiveId(match.group(3));
    final threadMessageId = _positiveId(match.group(4));
    final infoTab = ChatChannelInfoTab.parse(match.group(5));
    if (channelId == null || channelId <= 0) return null;
    if (match.group(2) != null && channelMessageId == null) return null;
    if (match.group(3) != null && threadId == null) return null;
    if (match.group(4) != null && threadMessageId == null) return null;
    if (match.group(5) != null && infoTab == null) return null;

    final route = switch ((threadId, infoTab)) {
      (final threadId?, _) => ChatRoute.thread(
        channelId: channelId,
        threadId: threadId,
      ),
      (_, final infoTab?) => ChatRoute.info(channelId: channelId, tab: infoTab),
      _ => ChatRoute.channel(channelId),
    };
    return ChatLink(
      uri: uri,
      route: route,
      messageId: channelMessageId ?? threadMessageId,
    );
  }

  static const int maximumUrlLength = 2048;
  static final RegExp _pathPattern = RegExp(
    r'^/chat/c/(?:-|[^/]+)/([1-9][0-9]*)(?:(?:/([1-9][0-9]*))|(?:/t/([1-9][0-9]*)(?:/([1-9][0-9]*))?)|(?:/info/(settings|members)))?/?$',
  );

  static int? _positiveId(String? value) {
    if (value == null) return null;
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

/// One route handoff from the shell to the mounted Chat screen.
///
/// The route is durable, but a message anchor is not navigation history. This
/// one-shot value keeps scroll/fetch intent out of [ChatRoute] persistence and
/// gives the channel/thread view a small integration boundary while their
/// controllers remain independently owned.
@immutable
final class ChatNavigationTarget {
  const ChatNavigationTarget({
    required this.siteUrl,
    required this.route,
    this.messageId,
    this.focusComposer = false,
  });

  final String siteUrl;
  final ChatRoute route;
  final int? messageId;
  final bool focusComposer;
}

final class ChatNavigationHandoff extends ChangeNotifier {
  ChatNavigationTarget? _value;

  ChatNavigationTarget? get value => _value;

  void offer(ChatNavigationTarget target) {
    _value = target;
    notifyListeners();
  }

  /// Takes the pending target only when it belongs to the mounting screen.
  ChatNavigationTarget? take({
    required String siteUrl,
    required ChatRoute route,
  }) {
    final target = _value;
    if (target == null || target.siteUrl != siteUrl || target.route != route) {
      return null;
    }
    _value = null;
    return target;
  }
}
