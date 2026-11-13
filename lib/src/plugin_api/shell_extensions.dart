import 'dart:async';
import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import '../data/discourse_api_contracts.dart';
import '../data/live_channels.dart';
import '../foundation/icons/d_icon_data.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/forum_workspace.dart' show ForumPanel;
import '../models/notification_totals.dart';
import '../models/sidebar.dart';
import '../models/user_preferences.dart';
import 'composer_syntax.dart';
import 'global_search.dart';
import 'plugin_manifest.dart';

export '../data/live_channels.dart';
export 'background_retention.dart';
export 'bookmark_host.dart'
    show PluginBookmarkLinkResolver, PluginBookmarkTargetStrategy;

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

  /// Stable identity of the selected reader tab, including tabs that share
  /// the same content route. Null when the host has no reader tab.
  String? get activeTabId;

  ContentRoute? get currentContent;

  void selectInstance(int index);

  /// Opens a route with the link's site and tab/panel intent. Background opens
  /// preserve the selected forum and do not call [onNavigated]. Returns false
  /// when the destination cannot be committed, including a full workspace.
  /// [onOpened] receives the identity of the committed destination tab.
  bool pushContent(
    ContentRoute route, {
    String? siteUrl,
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
    void Function(String tabId)? onOpened,
  });
  void replaceCurrentContent(ContentRoute route);

  /// Opens [postNumber] and briefly emphasizes its rendered post when
  /// [highlight] is true. Ordinary navigation keeps the emphasis disabled.
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  });
}

/// Optional presentation observations for overlays that follow a content route.
/// This exposes visibility, never the shell controller or unrelated state.
abstract interface class PluginRoutePresentationHost implements Listenable {
  bool get currentContentVisible;
  bool get mobileNavigationEnabled;

  String? tabIdOf(BuildContext context);

  /// The tab's current route, or null after its workspace or tab is retired.
  ContentRoute? contentForTab(String siteUrl, String tabId);
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
  bool get desktopPanelsEnabled;
  bool get isDisposed;

  /// Stable identity of the selected reader tab, including tabs that share
  /// the same content route. Null when the host has no reader tab.
  String? get activeTabId;

  ContentRoute? get currentContent;
  List<ContentRoute> get contentStack;
  NotificationTotals? get currentTotals;
  PluginVisibleTopicContext? get visibleTopicContext;

  /// Remaining reader bounds in main-view global logical coordinates,
  /// excluding shell navigation and a docked composer.
  ///
  /// The bounds move on every frame of a window resize or composer dock drag,
  /// so [changes] does not report them; observe
  /// [readerContentBoundsListenable] instead.
  Rect? get readerContentBounds;
  ValueListenable<Rect?> get readerContentBoundsListenable;

  void selectInstance(int index);
  void pushContent(
    ContentRoute route, {
    bool newTab = false,
    ForumPanel? panel,
  });

  /// Opens or focuses a directory's own tab; mobile uses ordinary navigation.
  /// At the tab limit, navigates the active tab while preserving its history.
  void openPageTab(ContentRoute route);
  void replaceCurrentContent(ContentRoute route);
  void selectDestination(SidebarDestination destination);

  /// Updates highlights only in the current site's current route and tab.
  void setPageSearchWords(String siteUrl, String routeId, String words);

  /// Opens the shared search with removable defaults for the current site.
  void openSearch(String siteUrl, GlobalSearchContext context);
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

enum PluginLinkOrigin {
  direct,
  inApp,
  newTab,
  mainPanel,
  mainPanelNewTab,
  secondaryPanel,
  secondaryPanelNewTab,
}

abstract interface class PluginLinkHandler implements PluginSessionCapability {
  /// Returns whether the URL was handled. [onNavigated] reports only a
  /// committed foreground navigation, never background or retired work.
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
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
  FutureOr<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  });
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
  const PluginComposerSubmitPreparation.proceed({
    this.changed = false,
    this.notice,
  }) : failure = null;

  const PluginComposerSubmitPreparation.failed(WriteException this.failure)
    : changed = false,
      notice = null;

  final bool changed;
  final WriteException? failure;
  final String? notice;
}

abstract interface class PluginComposerSubmitPreparer
    implements PluginSessionCapability {
  FutureOr<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  );
}

abstract interface class PluginUserPreferenceMirror
    implements PluginSessionCapability {
  /// Projects every current-user field this module mirrors from the section.
  /// Preserve other fields, even when the section has additional wire settings.
  /// May replay against an older current-user response; must be side-effect free.
  DiscourseUser mirrorUserPreference(
    DiscourseUser user,
    PreferenceSection section,
    UserPreferences preferences,
  );
}

/// Presentation supplied by the owner of a bookmark's target type.
@immutable
final class BookmarkPresentation {
  const BookmarkPresentation({
    required this.title,
    required this.typeLabel,
    required this.icon,
    this.contextLabel,
    this.color,
  });

  final String title;
  final String typeLabel;
  final DIconData icon;
  final String? contextLabel;
  final Color? color;

  String get subtitle => [typeLabel, ?contextLabel].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is BookmarkPresentation &&
      other.title == title &&
      other.typeLabel == typeLabel &&
      other.icon == icon &&
      other.contextLabel == contextLabel &&
      other.color == color;

  @override
  int get hashCode => Object.hash(title, typeLabel, icon, contextLabel, color);
}

abstract interface class PluginBookmarkPresenter
    implements PluginSessionCapability {
  BookmarkPresentation? presentBookmark(String siteUrl, Bookmark bookmark);
}
