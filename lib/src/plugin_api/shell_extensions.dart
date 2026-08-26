import 'dart:async';

import '../data/site_tracker.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/notification_totals.dart';
import '../models/sidebar.dart';
import 'plugin_manifest.dart';

/// Core navigation primitives available to session-scoped plugin routers.
abstract interface class PluginNavigationHost {
  bool get isDisposed;
  List<DiscourseInstance> get instances;
  DiscourseInstance? get currentInstance;
  ContentRoute? get currentContent;
  List<ContentRoute> get contentStack;
  NotificationTotals? get currentTotals;

  void selectInstance(int index);
  void selectDestination(SidebarDestination destination);
  void pushContent(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);
  void showPluginContent();

  Future<String?> insertPluginTranscriptIntoNewTopic({
    required String siteUrl,
    required String sourceRouteId,
    required String markdown,
    int? initialCategoryId,
  });
}

abstract interface class PluginLinkHandler implements PluginSessionCapability {
  Future<bool> openPluginUrl(String url);
}

enum PluginRouteRetryResult { notHandled, failed, succeeded }

abstract interface class PluginRouteRetry implements PluginSessionCapability {
  Future<PluginRouteRetryResult> retryPluginRoute(
    String siteUrl,
    String routeId,
  );
}

abstract interface class PluginRouteHydrator
    implements PluginSessionCapability {
  bool handlesPluginRoute(String routeId);
  FutureOr<void> hydratePluginRoute(String siteUrl, String routeId);
}

abstract interface class PluginSiteActivator
    implements PluginSessionCapability {
  FutureOr<void> activatePluginSite(String siteUrl, {required bool connected});
}

abstract interface class PluginTotalsObserver
    implements PluginSessionCapability {
  FutureOr<void> pluginTotalsLoaded(
    String siteUrl,
    NotificationTotals totals, {
    required bool selected,
  });
}

abstract interface class PluginTrackerAttachment
    implements PluginSessionCapability {
  void attachPluginTracker(String siteUrl, SiteTracker tracker);
}

abstract interface class PluginBackgroundSite
    implements PluginSessionCapability {
  String? get pluginBackgroundSiteUrl;
}

abstract interface class PluginComposerTargetProvider
    implements PluginSessionCapability {
  bool supportsPluginComposerTarget(String siteUrl, String kind);
}

abstract interface class PluginBookmarkObserver
    implements PluginSessionCapability {
  bool handlesPluginBookmark(String targetType);
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark);
  void removePluginBookmark(String siteUrl, int targetId);
  FutureOr<void> reconcilePluginBookmark(String siteUrl, int targetId);
}
