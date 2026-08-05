import 'package:flutter/material.dart';

import 'discourse_user.dart';
import 'sidebar.dart';

/// A Discourse site the user has connected to — one entry in the rail.
///
/// Fields mirror what `/site/basic-info.json` gives us, which is everything we
/// can know before the user authenticates.
@immutable
class DiscourseInstance {
  const DiscourseInstance({
    required this.url,
    required this.title,
    this.description,
    this.iconUrl,
    this.apiVersion = 0,
    this.loginRequired = false,
    this.unreadCount = 0,
    this.user,
  });

  factory DiscourseInstance.fromJson(Map<String, dynamic> json) {
    return DiscourseInstance(
      url: json['url'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      iconUrl: json['iconUrl'] as String?,
      apiVersion: json['apiVersion'] as int? ?? 0,
      loginRequired: json['loginRequired'] as bool? ?? false,
      user: json['user'] == null
          ? null
          : DiscourseUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  DiscourseInstance copyWith({
    String? title,
    String? description,
    String? iconUrl,
    int? apiVersion,
    bool? loginRequired,
    int? unreadCount,
    DiscourseUser? user,
    bool clearUser = false,
  }) {
    return DiscourseInstance(
      url: url,
      title: title ?? this.title,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      apiVersion: apiVersion ?? this.apiVersion,
      loginRequired: loginRequired ?? this.loginRequired,
      unreadCount: unreadCount ?? this.unreadCount,
      user: clearUser ? null : (user ?? this.user),
    );
  }

  /// Canonical origin, without a trailing slash. Doubles as the identity.
  final String url;

  final String title;
  final String? description;
  final String? iconUrl;
  final int apiVersion;
  final bool loginRequired;

  /// Not persisted — refreshed from the site once we can authenticate.
  final int unreadCount;

  /// Who we are on this site, or null if not connected. Safe to persist; the
  /// API key itself lives in the keychain, never here.
  final DiscourseUser? user;

  bool get isConnected => user != null;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'iconUrl': iconUrl,
    'apiVersion': apiVersion,
    'loginRequired': loginRequired,
    'user': user?.toJson(),
  };

  /// Host and port, which is what identifies a site to a human.
  String get host {
    final uri = Uri.parse(url);
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// Stand-in for the site's own color scheme, which needs an authenticated
  /// request to read. Derived from [url] so a given site keeps its color.
  Color get accentColor {
    final hash = url.codeUnits.fold<int>(0, (sum, unit) => (sum * 31 + unit) & 0xFFFFFF);
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.55, 0.5).toColor();
  }

  /// Up to two letters, shown until the real icon loads.
  String get monogram {
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return words.take(2).map((w) => w[0]).join().toUpperCase();
  }

  /// Routes every Discourse has. Categories and chat channels need an
  /// authenticated request, so they are not here yet.
  List<SidebarSection> get sections => const [
    SidebarSection(
      title: 'Community',
      destinations: [
        SidebarDestination(
          id: 'latest',
          label: 'Latest',
          icon: Icons.forum_outlined,
        ),
        SidebarDestination(
          id: 'new',
          label: 'New',
          icon: Icons.fiber_new_outlined,
        ),
        SidebarDestination(
          id: 'unread',
          label: 'Unread',
          icon: Icons.mark_chat_unread_outlined,
        ),
        SidebarDestination(
          id: 'top',
          label: 'Top',
          icon: Icons.trending_up_outlined,
        ),
        SidebarDestination(
          id: 'bookmarks',
          label: 'Bookmarks',
          icon: Icons.bookmark_outline,
        ),
      ],
    ),
  ];

  SidebarDestination get defaultDestination =>
      sections.first.destinations.first;

  @override
  bool operator ==(Object other) =>
      other is DiscourseInstance && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
