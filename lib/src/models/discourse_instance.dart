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
      // Appearance is optional presentation metadata. An old, partial, or
      // malformed value must not make the whole site disappear from the rail.
      appearance: _appearanceFromJson(json['appearance']),
      // Absent for every site stored before this existed, which is what the
      // unknown default is for. A malformed optional value makes only this
      // stored entry unreadable; `InstanceStore` preserves the other sites.
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

  /// Canonical origin, without a trailing slash. Doubles as the identity.
  final String url;

  final String title;
  final String? description;
  final String? iconUrl;
  final int apiVersion;
  final bool loginRequired;

  /// Who we are on this site, or null if not connected. Safe to persist; the
  /// API key itself lives in platform-private storage, never here.
  final DiscourseUser? user;

  /// Last account totals snapshot, retained for an immediate warm start.
  ///
  /// Plugin-owned counts remain namespaced and opaque when their plugin is not
  /// installed, so a core-only build can safely load and save this instance.
  final NotificationTotals? notificationTotals;

  /// The last resolved theme colors for this site. They are safe to persist:
  /// unlike the API key, compiled color variables contain no credentials.
  final SiteAppearance? appearance;

  /// What this site's client settings said, or [SiteConfig.unknown] before it
  /// has been asked.
  ///
  /// Persisted rather than kept for the session because it decides *rendering*
  /// — a site drawing google emoji would otherwise draw twitter ones through
  /// the first topic of every launch. The cost is that it can be one launch
  /// stale, which nothing here is harmed by; see [SiteConfig].
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

  /// Host and port, which is what identifies a site to a human.
  String get host => _authority(Uri.parse(url));

  /// True when [link] is a page on this site.
  ///
  /// Host and port decide it, not scheme: an old `http://` link to a site now
  /// served over https is still that site, while two forums running on
  /// localhost during development differ only by their port.
  bool serves(Uri link) => link.hasAuthority && _authority(link) == host;

  static String _authority(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  /// Stable fallback used until the site's resolved appearance is available.
  /// Derived from [url] so a given site keeps its color.
  Color get accentColor {
    final hash = url.codeUnits.fold<int>(
      0,
      (sum, unit) => (sum * 31 + unit) & 0xFFFFFF,
    );
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.55, 0.5).toColor();
  }

  /// Up to two letters, shown until the real icon loads.
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

  /// Routes every Discourse has before any forum response arrives. Categories
  /// and chat channels are appended by the shell once their live data loads.
  ///
  /// Messages and drafts belong to an account rather than the public forum, so
  /// anonymous readers do not get destinations that cannot resolve their data.
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
        // `layer-group` is what Discourse's own sidebar gives Everything.
        // The id stays `latest` — it is the feed this entry reads.
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
        // `layer-group` is what Discourse's own sidebar gives Everything.
        // The id stays `latest` — it is the feed this entry reads.
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
