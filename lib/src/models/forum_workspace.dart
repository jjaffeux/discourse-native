import 'package:flutter/foundation.dart';

import 'content_route.dart';

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
    if (kind is! String || kind.isEmpty || itemId is! int || itemId < 0) {
      throw const FormatException('Invalid forum tab anchor');
    }
    final restoredOffset = offset is num ? offset.toDouble() : 0.0;
    return ForumTabAnchor(
      kind: kind,
      itemId: itemId,
      // A corrupt exponent such as `1e999` can decode to infinity. Retain the
      // useful item anchor, but never let non-finite local state reach a
      // ScrollController jump.
      offset: restoredOffset.isFinite ? restoredOffset : 0,
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

@immutable
final class ForumTab {
  ForumTab({
    required this.id,
    required this.rootDestinationId,
    required List<ContentRoute> contentStack,
    List<ContentRoute> forwardStack = const [],
    Map<String, ForumTabAnchor> anchors = const {},
  }) : assert(id.isNotEmpty),
       assert(rootDestinationId.isNotEmpty),
       assert(contentStack.isNotEmpty),
       assert(
         contentStack.length + forwardStack.length <= maximumContentRoutes,
       ),
       contentStack = List.unmodifiable(contentStack),
       forwardStack = List.unmodifiable(forwardStack),
       anchors = Map.unmodifiable(anchors);

  static const int maximumContentRoutes = 64;

  final String id;
  final String rootDestinationId;
  final List<ContentRoute> contentStack;
  final List<ContentRoute> forwardStack;

  final Map<String, ForumTabAnchor> anchors;

  ContentRoute get currentContent => contentStack.last;
  bool get canGoBack => contentStack.length > 1;
  bool get canGoForward => forwardStack.isNotEmpty;

  ForumTab copyWith({
    String? rootDestinationId,
    List<ContentRoute>? contentStack,
    List<ContentRoute>? forwardStack,
    Map<String, ForumTabAnchor>? anchors,
  }) => ForumTab(
    id: id,
    rootDestinationId: rootDestinationId ?? this.rootDestinationId,
    contentStack: contentStack ?? this.contentStack,
    forwardStack: forwardStack ?? this.forwardStack,
    anchors: anchors ?? this.anchors,
  );

  ForumTab push(ContentRoute route) {
    late final List<ContentRoute> routes;
    if (contentStack.length < maximumContentRoutes) {
      routes = [...contentStack, route];
    } else {
      routes = [
        contentStack.first,
        ...contentStack.skip(contentStack.length - maximumContentRoutes + 2),
        route,
      ];
    }
    return copyWith(
      contentStack: routes,
      forwardStack: const [],
      anchors: _retainAnchors({for (final item in routes) item.id}),
    );
  }

  ForumTab goBack() {
    if (!canGoBack) return this;
    return copyWith(
      contentStack: contentStack.take(contentStack.length - 1).toList(),
      forwardStack: [...forwardStack, currentContent],
    );
  }

  ForumTab goForward() {
    if (!canGoForward) return this;
    return copyWith(
      contentStack: [...contentStack, forwardStack.last],
      forwardStack: forwardStack.take(forwardStack.length - 1).toList(),
    );
  }

  Map<String, ForumTabAnchor> _retainAnchors(Set<String> routeIds) => {
    for (final entry in anchors.entries)
      if (routeIds.contains(entry.key)) entry.key: entry.value,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'root_destination_id': rootDestinationId,
    'content_stack': [for (final route in contentStack) route.toJson()],
    if (forwardStack.isNotEmpty)
      'forward_content_stack': [
        for (final route in forwardStack) route.toJson(),
      ],
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

    ContentRoute? rootRoute;
    final recent = <ContentRoute>[];
    for (final rawRoute in rawStack) {
      try {
        if (rawRoute is Map) {
          final route = ContentRoute.fromJson(
            Map<String, dynamic>.from(rawRoute),
          );
          if (rootRoute == null) {
            rootRoute = route;
          } else {
            recent.add(route);
            if (recent.length >= maximumContentRoutes) recent.removeAt(0);
          }
        }
      } on FormatException {
        // A broken route cannot be left in the middle of a back stack. The tab
        // is discarded below when no valid route remains.
      }
    }
    if (rootRoute == null) return null;
    final stack = <ContentRoute>[rootRoute, ...recent];

    final forwardStack = <ContentRoute>[];
    final rawForwardStack = json['forward_content_stack'];
    final forwardCapacity = maximumContentRoutes - stack.length;
    if (rawForwardStack is List && forwardCapacity > 0) {
      for (final rawRoute in rawForwardStack) {
        try {
          if (rawRoute is Map) {
            forwardStack.add(
              ContentRoute.fromJson(Map<String, dynamic>.from(rawRoute)),
            );
            if (forwardStack.length > forwardCapacity) {
              forwardStack.removeAt(0);
            }
          }
        } on FormatException {
          // One broken future entry does not invalidate the usable history.
        }
      }
    }

    final routeIds = {
      for (final route in stack) route.id,
      for (final route in forwardStack) route.id,
    };
    final anchors = <String, ForumTabAnchor>{};
    final rawAnchors = json['anchors'];
    if (rawAnchors is Map) {
      for (final entry in rawAnchors.entries) {
        if (entry.key is! String ||
            !routeIds.contains(entry.key) ||
            entry.value is! Map) {
          continue;
        }
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
      forwardStack: forwardStack,
      anchors: anchors,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTab &&
      other.id == id &&
      other.rootDestinationId == rootDestinationId &&
      listEquals(other.contentStack, contentStack) &&
      listEquals(other.forwardStack, forwardStack) &&
      mapEquals(other.anchors, anchors);

  @override
  int get hashCode => Object.hash(
    id,
    rootDestinationId,
    Object.hashAll(contentStack),
    Object.hashAll(forwardStack),
    // MapEntry hashes by identity while == uses mapEquals, so the anchors
    // must be hashed by key/value pairs, order-independently, to keep equal
    // tabs — such as one snapshot decoded twice — on one hash code.
    Object.hashAllUnordered([
      for (final entry in anchors.entries) Object.hash(entry.key, entry.value),
    ]),
  );
}

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
       assert(tabs.length <= maximumTabs),
       assert(tabs.map((tab) => tab.id).toSet().length == tabs.length),
       assert(tabs.any((tab) => tab.id == activeTabId)),
       tabs = List.unmodifiable(tabs);

  static const int maximumTabs = 20;

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
      final rawId = rawTab is Map ? rawTab['id'] : null;
      final isPersistedActive = rawId == json['active_tab_id'];
      if (tabs.length >= maximumTabs && !isPersistedActive) continue;

      final tab = ForumTab.tryFromJson(rawTab);
      if (tab == null || !seen.add(tab.id)) continue;
      if (tabs.length < maximumTabs) {
        tabs.add(tab);
      } else {
        // Keep the restored active context reachable even when a snapshot
        // predates the cap. The oldest inactive overflow context is dropped.
        seen.remove(tabs.last.id);
        tabs[tabs.length - 1] = tab;
      }
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
