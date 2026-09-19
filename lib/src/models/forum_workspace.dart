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
final class ForumTabLocation {
  ForumTabLocation({
    required this.rootDestinationId,
    required List<ContentRoute> contentStack,
  }) : assert(rootDestinationId.isNotEmpty),
       assert(contentStack.isNotEmpty),
       assert(contentStack.length <= ForumTab.maximumContentRoutes),
       contentStack = List.unmodifiable(contentStack);

  final String rootDestinationId;
  final List<ContentRoute> contentStack;

  Map<String, Object?> toJson() => {
    'root_destination_id': rootDestinationId,
    'content_stack': [for (final route in contentStack) route.toJson()],
  };

  static ForumTabLocation? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final root = value['root_destination_id'];
    final routes = ForumTab._readRoutes(
      value['content_stack'],
      ForumTab.maximumContentRoutes,
      preserveRoot: true,
    );
    if (root is! String || root.isEmpty || routes.isEmpty) return null;
    return ForumTabLocation(rootDestinationId: root, contentStack: routes);
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTabLocation &&
      other.rootDestinationId == rootDestinationId &&
      listEquals(other.contentStack, contentStack);

  @override
  int get hashCode =>
      Object.hash(rootDestinationId, Object.hashAll(contentStack));
}

@immutable
final class ForumTab {
  ForumTab({
    required this.id,
    required this.rootDestinationId,
    required List<ContentRoute> contentStack,
    List<ContentRoute> forwardStack = const [],
    List<ForumTabLocation>? backHistory,
    List<ForumTabLocation>? forwardHistory,
    Map<String, ForumTabAnchor> anchors = const {},
  }) : assert(id.isNotEmpty),
       assert(rootDestinationId.isNotEmpty),
       assert(contentStack.isNotEmpty),
       assert(contentStack.length <= maximumContentRoutes),
       assert(forwardStack.length <= maximumHistoryEntries),
       assert(
         backHistory == null || backHistory.length <= maximumHistoryEntries,
       ),
       assert(
         forwardHistory == null ||
             forwardHistory.length <= maximumHistoryEntries,
       ),
       contentStack = List.unmodifiable(contentStack),
       backHistory = List.unmodifiable(
         backHistory ?? _legacyBackHistory(rootDestinationId, contentStack),
       ),
       forwardHistory = List.unmodifiable(
         forwardHistory ??
             _legacyForwardHistory(
               rootDestinationId,
               contentStack,
               forwardStack,
             ),
       ),
       anchors = Map.unmodifiable(anchors);

  static const int maximumContentRoutes = 64;
  static const int maximumHistoryEntries = 50;

  final String id;
  final String rootDestinationId;
  final List<ContentRoute> contentStack;
  // History is separate from the current page's parent routes. Replacing a
  // split-view reader or switching sidebar destinations is still a visit.
  // Entries contain route metadata only, never widgets or loaded page data.
  final List<ForumTabLocation> backHistory;
  final List<ForumTabLocation> forwardHistory;
  List<ContentRoute> get forwardStack => List.unmodifiable([
    for (final entry in forwardHistory) entry.contentStack.last,
  ]);

  final Map<String, ForumTabAnchor> anchors;

  ContentRoute get currentContent => contentStack.last;
  bool get canGoBack => backHistory.isNotEmpty;
  bool get canGoForward => forwardHistory.isNotEmpty;

  ForumTabLocation get location => ForumTabLocation(
    rootDestinationId: rootDestinationId,
    contentStack: contentStack,
  );

  ForumTab copyWith({
    String? rootDestinationId,
    List<ContentRoute>? contentStack,
    List<ForumTabLocation>? backHistory,
    List<ForumTabLocation>? forwardHistory,
    Map<String, ForumTabAnchor>? anchors,
  }) => ForumTab(
    id: id,
    rootDestinationId: rootDestinationId ?? this.rootDestinationId,
    contentStack: contentStack ?? this.contentStack,
    backHistory: backHistory ?? this.backHistory,
    forwardHistory: forwardHistory ?? this.forwardHistory,
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
    return navigate(contentStack: routes);
  }

  ForumTab navigate({
    String? rootDestinationId,
    required List<ContentRoute> contentStack,
  }) {
    final target = ForumTabLocation(
      rootDestinationId: rootDestinationId ?? this.rootDestinationId,
      contentStack: contentStack,
    );
    if (target == location) return this;
    return copyWith(
      rootDestinationId: target.rootDestinationId,
      contentStack: target.contentStack,
      backHistory: _bounded([...backHistory, location]),
      forwardHistory: const [],
    )._pruneAnchors();
  }

  ForumTab goBack() {
    if (!canGoBack) return this;
    return copyWith(
      rootDestinationId: backHistory.last.rootDestinationId,
      contentStack: backHistory.last.contentStack,
      backHistory: backHistory.take(backHistory.length - 1).toList(),
      forwardHistory: _bounded([...forwardHistory, location]),
    )._pruneAnchors();
  }

  ForumTab goForward() {
    if (!canGoForward) return this;
    return copyWith(
      rootDestinationId: forwardHistory.last.rootDestinationId,
      contentStack: forwardHistory.last.contentStack,
      backHistory: _bounded([...backHistory, location]),
      forwardHistory: forwardHistory.take(forwardHistory.length - 1).toList(),
    )._pruneAnchors();
  }

  ForumTab rewriteRoutes(ContentRoute Function(ContentRoute) rewrite) {
    // Route equality compares navigation identity, so it intentionally omits
    // presentation metadata such as the category color. Preserve rewrites of
    // those fields even when the route still has the same identity.
    var changed = false;
    ContentRoute rewriteRoute(ContentRoute route) {
      final updated = rewrite(route);
      changed = changed || !identical(updated, route);
      return updated;
    }

    ForumTabLocation rewriteLocation(ForumTabLocation entry) =>
        ForumTabLocation(
          rootDestinationId: entry.rootDestinationId,
          contentStack: entry.contentStack.map(rewriteRoute).toList(),
        );
    final updated = copyWith(
      contentStack: contentStack.map(rewriteRoute).toList(),
      backHistory: backHistory.map(rewriteLocation).toList(),
      forwardHistory: forwardHistory.map(rewriteLocation).toList(),
    );
    return changed ? updated : this;
  }

  ForumTab _pruneAnchors() => copyWith(
    anchors: _retainAnchors({
      for (final route in contentStack) route.id,
      for (final entry in [...backHistory, ...forwardHistory])
        for (final route in entry.contentStack) route.id,
    }),
  );

  static List<ForumTabLocation> _bounded(List<ForumTabLocation> entries) =>
      entries.length <= maximumHistoryEntries
      ? entries
      : entries.sublist(entries.length - maximumHistoryEntries);

  static List<ForumTabLocation> _legacyBackHistory(
    String root,
    List<ContentRoute> routes,
  ) => _bounded([
    for (var index = 1; index < routes.length; index++)
      ForumTabLocation(
        rootDestinationId: root,
        contentStack: routes.take(index).toList(),
      ),
  ]);

  static List<ForumTabLocation> _legacyForwardHistory(
    String root,
    List<ContentRoute> routes,
    List<ContentRoute> forward,
  ) {
    final entries = <ForumTabLocation>[];
    var stack = routes;
    for (final route in forward.reversed) {
      stack = [
        if (stack.length == maximumContentRoutes) ...[
          stack.first,
          ...stack.skip(2),
        ] else
          ...stack,
        route,
      ];
      entries.add(
        ForumTabLocation(rootDestinationId: root, contentStack: stack),
      );
    }
    return entries.reversed.toList();
  }

  Map<String, ForumTabAnchor> _retainAnchors(Set<String> routeIds) => {
    for (final entry in anchors.entries)
      if (routeIds.contains(entry.key)) entry.key: entry.value,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'root_destination_id': rootDestinationId,
    'content_stack': [for (final route in contentStack) route.toJson()],
    'back_history': [for (final entry in backHistory) entry.toJson()],
    'forward_history': [for (final entry in forwardHistory) entry.toJson()],
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

    final stack = _readRoutes(
      rawStack,
      maximumContentRoutes,
      preserveRoot: true,
    );
    if (stack.isEmpty) return null;
    final backHistory =
        _readHistory(json['back_history']) ?? _legacyBackHistory(root, stack);
    final forwardHistory =
        _readHistory(json['forward_history']) ??
        _legacyForwardHistory(
          root,
          stack,
          _readRoutes(json['forward_content_stack'], maximumHistoryEntries),
        );
    final routeIds = {
      for (final route in stack) route.id,
      for (final entry in [...backHistory, ...forwardHistory])
        for (final route in entry.contentStack) route.id,
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
      backHistory: backHistory,
      forwardHistory: forwardHistory,
      anchors: anchors,
    );
  }

  static List<ContentRoute> _readRoutes(
    Object? value,
    int limit, {
    bool preserveRoot = false,
  }) {
    final routes = <ContentRoute>[];
    if (value is! List) return routes;
    for (final rawRoute in value) {
      try {
        if (rawRoute is Map) {
          routes.add(
            ContentRoute.fromJson(Map<String, dynamic>.from(rawRoute)),
          );
          if (routes.length > limit) routes.removeAt(preserveRoot ? 1 : 0);
        }
      } on FormatException {
        // A broken route must not discard its usable neighbours.
      }
    }
    return routes;
  }

  static List<ForumTabLocation>? _readHistory(Object? value) {
    if (value is! List) return null;
    final entries = <ForumTabLocation>[];
    for (final rawEntry in value) {
      final entry = ForumTabLocation.tryFromJson(rawEntry);
      if (entry == null) continue;
      entries.add(entry);
      if (entries.length > maximumHistoryEntries) entries.removeAt(0);
    }
    return entries;
  }

  @override
  bool operator ==(Object other) =>
      other is ForumTab &&
      other.id == id &&
      other.rootDestinationId == rootDestinationId &&
      listEquals(other.contentStack, contentStack) &&
      listEquals(other.backHistory, backHistory) &&
      listEquals(other.forwardHistory, forwardHistory) &&
      mapEquals(other.anchors, anchors);

  @override
  int get hashCode => Object.hash(
    id,
    rootDestinationId,
    Object.hashAll(contentStack),
    Object.hashAll(backHistory),
    Object.hashAll(forwardHistory),
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
