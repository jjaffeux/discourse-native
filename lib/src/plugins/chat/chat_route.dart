import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

/// Retains the pre-thread channel route for persisted tabs; thread identity is
/// appended so the channel remains the Back-navigation root.
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

  /// Accepts only anchored, canonically spelled ids minted by [routeId].
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

  static const String searchRouteId = 'chat-search';
  static const String myThreadsRouteId = 'chat-my-threads';
  static const String browseRouteId = 'chat-browse';
  static const String inboxRouteId = 'chat-inbox';
  static const String channelsRouteId = 'chat-channels';
  static const String starredRouteId = 'chat-starred';
  static const String directMessagesRouteId = 'chat-direct-messages';

  static String channelThreadsRouteId(int channelId) =>
      'chat-c-$channelId-threads';

  static int? channelIdFromThreadsRoute(String routeId) {
    if (routeId.length > maximumRouteIdLength) return null;
    final match = RegExp(r'^chat-c-([1-9]\d*)-threads$').firstMatch(routeId);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool ownsRouteId(String? routeId) =>
      routeId != null &&
      (parse(routeId) != null ||
          routeId == browseRouteId ||
          routeId == inboxRouteId ||
          routeId == channelsRouteId ||
          routeId == starredRouteId ||
          routeId == directMessagesRouteId ||
          routeId == myThreadsRouteId ||
          routeId == searchRouteId ||
          channelIdFromThreadsRoute(routeId) != null);

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

@immutable
final class ChatLink {
  const ChatLink({required this.route, this.messageId});

  final ChatRoute route;
  final int? messageId;

  /// Recognizes Discourse channel, thread, message-anchor, and info-tab paths;
  /// sibling Chat routes remain browser links. [siteUrl] names the forum the
  /// link belongs to, so a subfolder site's prefix is required and skipped.
  static ChatLink? parse(String url, {String? siteUrl}) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    if (uri.hasScheme && (!uri.hasAuthority || uri.host.isEmpty)) return null;
    if (uri.hasAuthority && uri.host.isEmpty) return null;

    final path = siteUrl == null
        ? uri.path
        : DiscourseInstance.pathWithinUrl(siteUrl, uri);
    if (path == null) return null;
    final match = _pathPattern.firstMatch(path);
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

/// Keeps one-shot message-anchor intent out of durable [ChatRoute] history.
@immutable
final class ChatNavigationTarget {
  const ChatNavigationTarget({
    required this.siteUrl,
    required this.route,
    this.messageId,
    this.focusComposer = false,
    this.tabId,
    this.lease,
  });

  final String siteUrl;
  final ChatRoute route;
  final int? messageId;
  final bool focusComposer;
  final String? tabId;
  final PluginSiteLease? lease;
}

final class ChatNavigationHandoff extends ChangeNotifier {
  final _pending = <(String, String?), ChatNavigationTarget>{};
  final _retirementObservers = <(String, String?), VoidCallback>{};

  ChatNavigationTarget? get value =>
      _pending.isEmpty ? null : _pending.values.last;

  void offer(ChatNavigationTarget target) {
    final key = (target.siteUrl, target.tabId);
    _remove(key);
    if (target.lease?.isCurrent == false) return;
    _pending[key] = target;
    final detach = target.lease?.onRetire(() {
      if (identical(_pending[key], target)) _remove(key);
    });
    if (detach != null) {
      if (identical(_pending[key], target)) {
        _retirementObservers[key] = detach;
      } else {
        detach();
      }
    }
    notifyListeners();
  }

  ChatNavigationTarget? take({
    required String siteUrl,
    required ChatRoute route,
    String? tabId,
  }) {
    final scoped = (siteUrl, tabId);
    final key = _pending.containsKey(scoped) ? scoped : (siteUrl, null);
    final target = _pending[key];
    if (target == null || target.siteUrl != siteUrl || target.route != route) {
      return null;
    }
    _remove(key);
    if (target.lease?.isCurrent == false) return null;
    return target;
  }

  void retain(bool Function(ChatNavigationTarget target) predicate) {
    for (final entry in _pending.entries.toList()) {
      if (!predicate(entry.value)) _remove(entry.key);
    }
  }

  void _remove((String, String?) key) {
    _pending.remove(key);
    _retirementObservers.remove(key)?.call();
  }

  @override
  void dispose() {
    for (final detach in _retirementObservers.values) {
      detach();
    }
    _retirementObservers.clear();
    _pending.clear();
    super.dispose();
  }
}
