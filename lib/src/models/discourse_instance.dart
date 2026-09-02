import 'package:flutter/material.dart';

import '../plugin_api/notification_counters.dart';
import '../plugin_api/plugin_data.dart';
import '../theme/d_icons.dart';
import 'discourse_user.dart';
import 'notification_totals.dart';
import 'sidebar.dart';
import 'site_appearance.dart';
import 'site_config.dart';

final RegExp _instanceTitleWord = RegExp(r'\S+');

@immutable
class DiscourseInstance {
  const DiscourseInstance({
    required this.url,
    required this.title,
    this.description,
    this.iconUrl,
    this.apiVersion = 0,
    this.loginRequired = false,
    this.user,
    this.notificationTotals,
    this.appearance,
    this.config = const SiteConfig.unknown(),
  });

  factory DiscourseInstance.fromJson(
    Map<String, dynamic> json, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    PluginNotificationCounterCodec counterCodec =
        const EmptyPluginNotificationCounterCodec(),
  }) {
    final user = json['user'] == null
        ? null
        : DiscourseUser.fromJson(
            json['user'] as Map<String, dynamic>,
            extensions: extensions,
          );
    return DiscourseInstance(
      url: json['url'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      iconUrl: json['iconUrl'] as String?,
      apiVersion: json['apiVersion'] as int? ?? 0,
      loginRequired: json['loginRequired'] as bool? ?? false,
      user: user,
      notificationTotals: user == null
          ? null
          : _notificationTotalsFromJson(
              json['notificationTotals'],
              counterCodec,
            ),
      // Malformed optional appearance must not discard the site.
      appearance: _appearanceFromJson(json['appearance']),
      // Missing config is an old snapshot; malformed config invalidates this entry.
      config: json['config'] == null
          ? const SiteConfig.unknown()
          : SiteConfig.fromJson(
              json['config'] as Map<String, dynamic>,
              extensions: extensions,
            ),
    );
  }

  DiscourseInstance copyWith({
    String? title,
    String? description,
    String? iconUrl,
    int? apiVersion,
    bool? loginRequired,
    DiscourseUser? user,
    bool clearUser = false,
    NotificationTotals? notificationTotals,
    bool clearNotificationTotals = false,
    SiteAppearance? appearance,
    bool clearAppearance = false,
    SiteConfig? config,
    bool clearConfig = false,
  }) {
    return DiscourseInstance(
      url: url,
      title: title ?? this.title,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      apiVersion: apiVersion ?? this.apiVersion,
      loginRequired: loginRequired ?? this.loginRequired,
      user: clearUser ? null : (user ?? this.user),
      notificationTotals: clearUser || clearNotificationTotals
          ? null
          : (notificationTotals ?? this.notificationTotals),
      appearance: clearAppearance ? null : (appearance ?? this.appearance),
      config: clearConfig
          ? const SiteConfig.unknown()
          : (config ?? this.config),
    );
  }

  final String url;

  final String title;
  final String? description;
  final String? iconUrl;
  final int apiVersion;
  final bool loginRequired;

  final DiscourseUser? user;

  final NotificationTotals? notificationTotals;

  final SiteAppearance? appearance;

  final SiteConfig config;

  bool get isConnected => user != null;

  Map<String, dynamic> toJson({
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    PluginNotificationCounterCodec counterCodec =
        const EmptyPluginNotificationCounterCodec(),
  }) => {
    'url': url,
    'title': title,
    'description': description,
    'iconUrl': iconUrl,
    'apiVersion': apiVersion,
    'loginRequired': loginRequired,
    'user': user?.toJson(extensions: extensions),
    if (user != null && notificationTotals != null)
      'notificationTotals': notificationTotals!.toStoredJson(
        counterCodec: counterCodec,
      ),
    'appearance': appearance?.toJson(),
    'config': config.toJson(extensions: extensions),
  };

  static NotificationTotals? _notificationTotalsFromJson(
    Object? value,
    PluginNotificationCounterCodec counterCodec,
  ) {
    if (value is! Map) return null;
    try {
      return NotificationTotals.fromStoredJson(
        Map<String, dynamic>.from(value),
        counterCodec: counterCodec,
      );
    } catch (_) {
      return null;
    }
  }

  static SiteAppearance? _appearanceFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final appearance = SiteAppearance.fromJson(
        Map<String, dynamic>.from(value),
      );
      return appearance.isKnown ? appearance : null;
    } catch (_) {
      return null;
    }
  }

  String get host => _authority(Uri.parse(url));

  /// The path a forum served from a subfolder lives under; empty at the root.
  List<String> get basePathSegments => basePathSegmentsOf(url);

  static List<String> basePathSegmentsOf(String siteUrl) => [
    for (final segment in Uri.parse(siteUrl).pathSegments)
      if (segment.isNotEmpty) segment,
  ];

  /// Whether [link] is one of this forum's pages: the same host, and under
  /// the subfolder when the forum is served from one.
  bool serves(Uri link) => urlServes(url, link);

  static bool urlServes(String siteUrl, Uri link) =>
      link.hasAuthority &&
      _authority(link) == _authority(Uri.parse(siteUrl)) &&
      pathSegmentsWithin(siteUrl, link) != null;

  /// [link]'s path below the forum's subfolder, as the root-relative path a
  /// root install would write; null when the link is not under it. Discourse
  /// writes a subfolder site's links with the subfolder, so its own route
  /// patterns apply to what is left.
  String? pathWithin(Uri link) => pathWithinUrl(url, link);

  static String? pathWithinUrl(String siteUrl, Uri link) {
    final segments = pathSegmentsWithin(siteUrl, link);
    return segments == null ? null : '/${segments.join('/')}';
  }

  static List<String>? pathSegmentsWithin(String siteUrl, Uri link) {
    final base = basePathSegmentsOf(siteUrl);
    final segments = link.pathSegments;
    if (segments.length < base.length) return null;
    for (var index = 0; index < base.length; index++) {
      if (segments[index] != base[index]) return null;
    }
    return segments.sublist(base.length);
  }

  static String _authority(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  Color get accentColor {
    final hash = url.codeUnits.fold<int>(
      0,
      (sum, unit) => (sum * 31 + unit) & 0xFFFFFF,
    );
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.55, 0.5).toColor();
  }

  String get monogram {
    final source = title.trim();
    final words = _instanceTitleWord.allMatches(source).iterator;
    if (!words.moveNext()) return '?';
    final first = words.current;
    if (!words.moveNext()) {
      final length = first.end - first.start;
      return source
          .substring(first.start, first.start + (length >= 2 ? 2 : 1))
          .toUpperCase();
    }
    return '${source[first.start]}${source[words.current.start]}'.toUpperCase();
  }

  List<SidebarSection> get sections {
    final base = isConnected ? _connectedSections : _anonymousSections;
    if (config.groupDirectoryEnabled || user?.staff == true) return base;
    return isConnected
        ? _connectedSectionsWithoutGroups
        : _anonymousSectionsWithoutGroups;
  }

  static final List<SidebarSection> _anonymousSectionsWithoutGroups =
      _withoutGroups(_anonymousSections);
  static final List<SidebarSection> _connectedSectionsWithoutGroups =
      _withoutGroups(_connectedSections);

  static List<SidebarSection> _withoutGroups(List<SidebarSection> sections) =>
      List.unmodifiable([
        for (final section in sections)
          SidebarSection(
            id: section.id,
            title: section.title,
            destinations: [
              for (final destination in section.destinations)
                if (destination.id != 'groups') destination,
            ],
            moreDestinations: [
              for (final destination in section.moreDestinations)
                if (destination.id != 'groups') destination,
            ],
            showHeader: section.showHeader,
            collapsible: section.collapsible,
            actionIcon: section.actionIcon,
            actionLabel: section.actionLabel,
            onAction: section.onAction,
          ),
      ]);

  static const List<SidebarSection> _anonymousSections = [
    SidebarSection(
      id: 'community',
      title: 'Community',
      showHeader: false,
      collapsible: false,
      destinations: [
        SidebarDestination(
          id: 'latest',
          label: 'Topics',
          icon: DIcons.layerGroup,
        ),
      ],
      moreDestinations: [
        SidebarDestination(id: 'groups', label: 'Groups', icon: DIcons.users),
        SidebarDestination(id: 'filter', label: 'Filter', icon: DIcons.filter),
      ],
    ),
  ];

  static const List<SidebarSection> _connectedSections = [
    SidebarSection(
      id: 'community',
      title: 'Community',
      showHeader: false,
      collapsible: false,
      destinations: [
        SidebarDestination(
          id: 'latest',
          label: 'Topics',
          icon: DIcons.layerGroup,
        ),
        SidebarDestination(
          id: 'messages',
          label: 'Messages',
          icon: DIcons.inbox,
        ),
        SidebarDestination(id: 'drafts', label: 'Drafts', icon: DIcons.pencil),
      ],
      moreDestinations: [
        SidebarDestination(id: 'groups', label: 'Groups', icon: DIcons.users),
        SidebarDestination(id: 'filter', label: 'Filter', icon: DIcons.filter),
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
