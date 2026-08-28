import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/notification_totals.dart';
import '../models/sidebar.dart';
import 'plugin_manifest.dart';

/// Route-safe information about one configured forum.
///
/// Unlike [DiscourseInstance], this carries no account record, site settings,
/// or appearance data. A plugin with route-only authority can identify and
/// select a destination without also receiving unrelated session state.
final class PluginRouteSite {
  const PluginRouteSite({
    required this.url,
    required this.title,
    required this.isConnected,
  });

  final String url;
  final String title;
  final bool isConnected;

  bool serves(Uri link) {
    if (!link.hasAuthority) return false;
    final own = Uri.parse(url);
    return _authority(link) == _authority(own);
  }

  static String _authority(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// The route mutations needed by a plugin which only opens its own screen.
abstract interface class PluginRouteNavigationHost {
  List<PluginRouteSite> get sites;
  PluginRouteSite? get currentSite;
  ContentRoute? get currentContent;

  void selectInstance(int index);
  void pushContent(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);
}

/// Full navigation primitives used by a plugin with nested/restored routes.
abstract interface class PluginNavigationHost {
  /// Invalidates navigation-derived presentation snapshots without exposing
  /// the concrete shell notifier to the plugin.
  Listenable get changes;

  List<DiscourseInstance> get instances;
  DiscourseInstance? get currentInstance;
  bool get forumActive;
  bool get isDisposed;
  ContentRoute? get currentContent;
  List<ContentRoute> get contentStack;
  NotificationTotals? get currentTotals;

  void selectInstance(int index);
  void pushContent(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);
  void selectDestination(SidebarDestination destination);
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

abstract interface class PluginChannelAttachment
    implements PluginSessionCapability {
  void attachPluginChannels(String siteUrl, PluginChannelHost channels);
}

/// A cancel-only handle for one plugin channel subscription.
abstract interface class PluginChannelSubscription {
  void cancel();
}

/// The message-bus authority exposed to plugin-owned background services.
///
/// This intentionally omits transport start/stop, immediate polling, topic
/// watches, and disposal. Those remain properties of the host-owned site
/// connection.
abstract interface class PluginChannelHost {
  PluginChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  });
}

typedef PluginChannelReader = PluginChannelHost? Function(String siteUrl);

/// Observes a freshly fetched `/session/current.json` account snapshot.
///
/// This is intentionally an invalidation hint rather than the user record:
/// plugins read the narrow site-state port they declared when they need it.
abstract interface class PluginCurrentUserObserver
    implements PluginSessionCapability {
  void pluginCurrentUserRefreshed(String siteUrl);
}

abstract interface class PluginBackgroundSite
    implements PluginSessionCapability {
  String? get pluginBackgroundSiteUrl;
}

/// Adds server-owned hashtag target types to composer autocomplete.
///
/// A session capability is used because availability can depend on plugin
/// state loaded after installation. Core only sees type names; it never
/// dispatches on a plugin-specific kind.
abstract interface class PluginComposerHashtagProvider
    implements PluginSessionCapability {
  Iterable<String> composerHashtagTypes(String siteUrl);
}

abstract interface class PluginBookmarkTargetStrategy
    implements PluginSessionCapability {
  BookmarkTargetType get pluginBookmarkTarget;
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark);
  void removePluginBookmark(String siteUrl, int targetId);
  FutureOr<void> reconcilePluginBookmark(String siteUrl, int targetId);
}
