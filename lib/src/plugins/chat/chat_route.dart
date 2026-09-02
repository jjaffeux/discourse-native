import 'package:flutter/foundation.dart';
import '../../models/discourse_instance.dart';

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
  const ChatLink({required this.uri, required this.route, this.messageId});

  final Uri uri;
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

/// Keeps one-shot message-anchor intent out of durable [ChatRoute] history.
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
