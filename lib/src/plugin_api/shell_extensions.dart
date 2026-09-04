import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../data/discourse_api_contracts.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
import '../models/sidebar.dart';
import '../models/user_preferences.dart';
import 'composer_syntax.dart';
import 'live_channels.dart';
import 'plugin_manifest.dart';

export 'background_retention.dart';
export 'live_channels.dart';

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

  bool serves(Uri link) => DiscourseInstance.urlServes(url, link);

  /// [link]'s path below this site's subfolder, or null when it is not
  /// under it; see [DiscourseInstance.pathWithin].
  String? pathWithin(Uri link) => DiscourseInstance.pathWithinUrl(url, link);
}

abstract interface class PluginRouteNavigationHost {
  List<PluginRouteSite> get sites;
  PluginRouteSite? get currentSite;
  ContentRoute? get currentContent;

  void selectInstance(int index);
  void pushContent(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);

  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  });
}

abstract interface class PluginTopicListNavigationHost {
  /// The selected site must already serve the route's site-relative path.
  void openTopicList(ContentRoute route);
}

/// The topic that remains visible behind a non-modal plugin surface.
///
/// This is intentionally a presentation snapshot rather than general topic
/// access. Plugins can use it to associate a write with what the reader was
/// looking at without receiving core topic or post records.
@immutable
final class PluginVisibleTopicContext {
  PluginVisibleTopicContext({
    required this.siteUrl,
    required this.topicId,
    required Iterable<int> postIds,
  }) : postIds = List.unmodifiable(postIds);

  final String siteUrl;
  final int topicId;
  final List<int> postIds;
}

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
  PluginVisibleTopicContext? get visibleTopicContext;

  /// The painted bounds of the shell's floating composer in global logical
  /// coordinates, or null when no composer is visible.
  Rect? get floatingComposerBounds;

  void selectInstance(int index);
  void pushContent(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);
  void selectDestination(SidebarDestination destination);
  void showPluginContent();

  /// Saves the active forum tab and restores this plugin's last tab snapshot.
  /// Returns whether a plugin snapshot was available.
  bool activatePluginPane(PluginId owner);

  /// Saves the active plugin tab and restores the forum snapshot captured when
  /// the pane was entered. A fresh forum root is used after a cold launch.
  void deactivatePluginPane(PluginId owner);
}

/// Lets the shell preserve a plugin panel before a navigation target leaves
/// that panel through an ordinary link, logo action, or core destination.
abstract interface class PluginPaneRoutePolicy
    implements PluginSessionCapability {
  PluginId get pluginPaneOwner;
  bool ownsPluginPaneRoute(String routeId);
  bool separatesPluginPane(String routeId);
}

enum PluginLinkOrigin { direct, inApp }

abstract interface class PluginLinkHandler implements PluginSessionCapability {
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  });
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
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels);
}

/// This is intentionally an invalidation hint rather than the user record:
/// plugins read the narrow site-state port they declared when they need it.
abstract interface class PluginCurrentUserObserver
    implements PluginSessionCapability {
  void pluginCurrentUserRefreshed(String siteUrl);
}

/// Lets an installed plugin finish an author-requested transformation before
/// the shell captures the body and sends the post request.
@immutable
final class PluginComposerSubmitPreparation {
  const PluginComposerSubmitPreparation.proceed({this.changed = false})
    : failure = null;

  const PluginComposerSubmitPreparation.failed(this.failure)
    : assert(failure != null),
      changed = false;

  final bool changed;
  final WriteException? failure;
}

abstract interface class PluginComposerSubmitPreparer
    implements PluginSessionCapability {
  FutureOr<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  );
}

abstract interface class PluginUserPreferenceMirror
    implements PluginSessionCapability {
  DiscourseUser mirrorUserPreference(
    DiscourseUser user,
    PreferenceSection section,
    UserPreferences preferences,
  );
}

abstract interface class PluginBookmarkTargetStrategy
    implements PluginSessionCapability {
  BookmarkTargetType get pluginBookmarkTarget;
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark);
  void removePluginBookmark(String siteUrl, int targetId);
  FutureOr<void> reconcilePluginBookmark(String siteUrl, int targetId);
}
