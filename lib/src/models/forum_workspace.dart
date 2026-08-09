import 'package:flutter/foundation.dart';

import 'content_route.dart';

/// A logical viewport position which can survive a tab being unmounted.
///
/// [kind] names the owning view (`feed`, `topic`, or `chat`), [itemId] is a row,
/// post, or message id, and [offset] is optional alignment within that item.
@immutable
final class ForumTabAnchor {
  const ForumTabAnchor({
    required this.kind,
    required this.itemId,
    this.offset = 0,
  });

  final String kind;
  final int itemId;
  final double offset;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'item_id': itemId,
    if (offset != 0) 'offset': offset,
  };

  factory ForumTabAnchor.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final itemId = json['item_id'];
    final offset = json['offset'];
    if (kind is! String || kind.isEmpty || itemId is! int) {
      throw const FormatException('Invalid forum tab anchor');
    }
    return ForumTabAnchor(
      kind: kind,
      itemId: itemId,
      offset: offset is num ? offset.toDouble() : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTabAnchor &&
      other.kind == kind &&
      other.itemId == itemId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(kind, itemId, offset);
}

/// One open work context inside a single forum.
@immutable
final class ForumTab {
  ForumTab({
    required this.id,
    required this.rootDestinationId,
    required List<ContentRoute> contentStack,
    Map<String, ForumTabAnchor> anchors = const {},
  }) : assert(id.isNotEmpty),
       assert(rootDestinationId.isNotEmpty),
       assert(contentStack.isNotEmpty),
       contentStack = List.unmodifiable(contentStack),
       anchors = Map.unmodifiable(anchors);

  final String id;
  final String rootDestinationId;
  final List<ContentRoute> contentStack;

  /// Restorable positions keyed by route id.
  final Map<String, ForumTabAnchor> anchors;

  ContentRoute get currentContent => contentStack.last;

  ForumTab copyWith({
    String? rootDestinationId,
    List<ContentRoute>? contentStack,
    Map<String, ForumTabAnchor>? anchors,
  }) => ForumTab(
    id: id,
    rootDestinationId: rootDestinationId ?? this.rootDestinationId,
    contentStack: contentStack ?? this.contentStack,
    anchors: anchors ?? this.anchors,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'root_destination_id': rootDestinationId,
    'content_stack': [for (final route in contentStack) route.toJson()],
    if (anchors.isNotEmpty)
      'anchors': {
        for (final entry in anchors.entries) entry.key: entry.value.toJson(),
      },
  };

  static ForumTab? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final id = json['id'];
    final root = json['root_destination_id'];
    final rawStack = json['content_stack'];
    if (id is! String ||
        id.isEmpty ||
        root is! String ||
        root.isEmpty ||
        rawStack is! List) {
      return null;
    }

    final stack = <ContentRoute>[];
    for (final rawRoute in rawStack) {
      try {
        if (rawRoute is Map) {
          stack.add(ContentRoute.fromJson(Map<String, dynamic>.from(rawRoute)));
        }
      } on FormatException {
        // A broken route cannot be left in the middle of a back stack. The tab
        // is discarded below when no valid route remains.
      }
    }
    if (stack.isEmpty) return null;

    final anchors = <String, ForumTabAnchor>{};
    final rawAnchors = json['anchors'];
    if (rawAnchors is Map) {
      for (final entry in rawAnchors.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        try {
          anchors[entry.key as String] = ForumTabAnchor.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        } on FormatException {
          // One stale viewport must not cost the rest of the tab.
        }
      }
    }
    return ForumTab(
      id: id,
      rootDestinationId: root,
      contentStack: stack,
      anchors: anchors,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTab &&
      other.id == id &&
      other.rootDestinationId == rootDestinationId &&
      listEquals(other.contentStack, contentStack) &&
      mapEquals(other.anchors, anchors);

  @override
  int get hashCode => Object.hash(
    id,
    rootDestinationId,
    Object.hashAll(contentStack),
    Object.hashAll(anchors.entries),
  );
}

/// The ordered set of tabs owned by one account on one forum.
@immutable
final class ForumWorkspace {
  ForumWorkspace({
    required this.siteUrl,
    required this.accountIdentity,
    required List<ForumTab> tabs,
    required this.activeTabId,
  }) : assert(siteUrl.isNotEmpty),
       assert(accountIdentity.isNotEmpty),
       assert(tabs.isNotEmpty),
       assert(tabs.map((tab) => tab.id).toSet().length == tabs.length),
       assert(tabs.any((tab) => tab.id == activeTabId)),
       tabs = List.unmodifiable(tabs);

  final String siteUrl;
  final String accountIdentity;
  final List<ForumTab> tabs;
  final String activeTabId;

  ForumTab get activeTab => tabs.firstWhere((tab) => tab.id == activeTabId);

  ForumTab? tabById(String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  ForumWorkspace copyWith({List<ForumTab>? tabs, String? activeTabId}) =>
      ForumWorkspace(
        siteUrl: siteUrl,
        accountIdentity: accountIdentity,
        tabs: tabs ?? this.tabs,
        activeTabId: activeTabId ?? this.activeTabId,
      );

  Map<String, Object?> toJson() => {
    'site_url': siteUrl,
    'account_identity': accountIdentity,
    'active_tab_id': activeTabId,
    'tabs': [for (final tab in tabs) tab.toJson()],
  };

  static ForumWorkspace? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final siteUrl = json['site_url'];
    final accountIdentity = json['account_identity'];
    final rawTabs = json['tabs'];
    if (siteUrl is! String ||
        siteUrl.isEmpty ||
        accountIdentity is! String ||
        accountIdentity.isEmpty ||
        rawTabs is! List) {
      return null;
    }

    final tabs = <ForumTab>[];
    final seen = <String>{};
    for (final rawTab in rawTabs) {
      final tab = ForumTab.tryFromJson(rawTab);
      if (tab != null && seen.add(tab.id)) tabs.add(tab);
    }
    if (tabs.isEmpty) return null;

    final requestedActive = json['active_tab_id'];
    final activeTabId =
        requestedActive is String && seen.contains(requestedActive)
        ? requestedActive
        : tabs.first.id;
    return ForumWorkspace(
      siteUrl: siteUrl,
      accountIdentity: accountIdentity,
      tabs: tabs,
      activeTabId: activeTabId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ForumWorkspace &&
      other.siteUrl == siteUrl &&
      other.accountIdentity == accountIdentity &&
      other.activeTabId == activeTabId &&
      listEquals(other.tabs, tabs);

  @override
  int get hashCode =>
      Object.hash(siteUrl, accountIdentity, activeTabId, Object.hashAll(tabs));
}
