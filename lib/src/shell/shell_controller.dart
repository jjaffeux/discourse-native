import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueListenable, listEquals;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../data/account_request_session.dart';
import '../data/account_session_coordinator.dart';
import '../data/api_credentials.dart';
import '../data/app_settings_store.dart';
import '../data/application_cooking.dart';
import '../data/authenticator.dart';
import '../data/badges_api.dart';
import '../data/composer_media_optimizer.dart';
import '../data/current_user_reconciler.dart';
import '../data/custom_sidebar_sections.dart';
import '../data/destination_bookmarks_store.dart';
import '../data/discourse_api_contracts.dart';
import '../data/discover_sites.dart';
import '../data/draft_store.dart';
import '../data/emoji_picker_store.dart';
import '../data/forum_settings_store.dart';
import '../data/forum_tab_store.dart';
import '../data/groups_api.dart';
import '../data/http_transport.dart';
import '../data/instance_store.dart';
import '../data/recent_destinations_store.dart';
import '../data/request_intent.dart';
import '../data/shell_api_ports.dart';
import '../data/sidebar_section_store.dart';
import '../data/site_image_repository.dart';
import '../data/site_lifecycle.dart';
import '../data/site_message_bus_bootstrap.dart';
import '../data/site_pdf_thumbnail_repository.dart';
import '../data/site_preference_keys.dart';
import '../data/site_tracker.dart';
import '../data/site_video_thumbnail_repository.dart';
import '../data/store.dart';
import '../data/topic_sidebar_store.dart';
import '../data/topic_tracking_reconciler.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../data/user_directory_api.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/surface_opening_trace.dart';
import '../foundation/bounded_lru_cache.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/timezone_environment.dart';
import '../models/badge_route.dart';
import '../models/bookmark.dart';
import '../models/bookmark_feed.dart';
import '../models/category_feed.dart';
import '../models/category_sidebar.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/content_route.dart';
import '../models/destination_bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/forum_about.dart';
import '../models/forum_workspace.dart';
import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../models/incoming_topics.dart';
import '../models/json.dart';
import '../models/list_link.dart';
import '../models/live_refresh_id.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../models/post.dart';
import '../models/post_checklist.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/post_revision.dart';
import '../models/search_results.dart';
import '../models/sidebar.dart';
import '../models/sidebar_tag.dart';
import '../models/site_appearance.dart';
import '../models/site_basic_info.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/tag_directory_feed.dart';
import '../models/tag_sidebar.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../models/topic_filter.dart';
import '../models/topic_link.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
import '../models/user_directory.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_status.dart';
import '../models/user_summary.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/cooking_plugin.dart';
import '../plugin_api/core_plugin_host.dart';
import '../plugin_api/core_plugin_manifest.dart';
import '../plugin_api/emoji_preferences.dart';
import '../plugin_api/plugin_runtime.dart';
import '../plugin_api/site_plugin_api.dart';
import '../site_preference_inventory.g.dart';
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'app_settings_controller.dart';
import 'badges_controller.dart';
import 'bookmark_transactions.dart';
import 'composer/autocomplete.dart';
import 'composer/components/quote.dart';
import 'composer/controller.dart';
import 'composer/draft_coordinator.dart';
import 'composer/pills.dart';
import 'composer/triggers.dart';
import 'content_page_contract.dart';
import 'do_not_disturb_controller.dart';
import 'draft_list_controller.dart';
import 'forum_settings_controller.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'groups_controller.dart';
import 'hashtag.dart';
import 'mobile_navigation.dart';
import 'plugin_background_retention.dart';
import 'post_checklist_write.dart';
import 'post_quote.dart';
import 'preferences_controller.dart';
import 'preview_requests.dart';
import 'shell_search_controller.dart';
import 'site_presentation_controller.dart';
import 'site_url.dart';
import 'topic_category_path.dart' as category_path;
import 'topic_data_owner.dart';
import 'topic_feed_controller.dart';
import 'topic_filter_controller.dart' show splitTopicFilterQuery;
import 'topic_filter_scope.dart';
import 'topic_prefetch_controller.dart';
import 'topic_read_controller.dart';
import 'unread_topic_feed.dart';
import 'update_controller.dart';
import 'user_directory_controller.dart';
import 'user_status_overrides.dart';
import 'user_summary_controller.dart';

part 'shell_tab_context.dart';
part 'workspace_controller.dart';
part 'taxonomy_directory_controller.dart';

enum MobilePane { sidebar, content }

enum ShellRootMode { forum }

enum InstanceLoadStatus { loading, ready, failed }

enum TabOpenResult { opened, unsupported, limitReached }

typedef TopicMoveDestination = ({int id, String title, String slug});

// A site can retain a substantial topic, post, and taxonomy working set, while
// per-site/type shares stop one long browsing session from displacing every
// other connected forum.
const _shellEntityStorePolicy = StorePolicy(
  maxEntries: 4096,
  maxEntriesPerSite: 2048,
  maxEntriesPerSiteAndType: 1024,
);

typedef TopicMoveDestinationSearchResult = ({
  List<TopicMoveDestination> destinations,
  String? error,
});
typedef TopicPostMoveResult = ({String? destinationUrl, String? error});
typedef _ShellWriteCredential = ({
  String? apiKey,
  AccountRequestCredentials? request,
  WriteException? failure,
});
typedef _PluginPaneKey = ({String siteUrl, String tabId, PluginId owner});
typedef _PluginPaneStateKey = ({String siteUrl, String tabId});
typedef _PostWindow = ({List<int> stream, (int, int)? range, List<int> ids});
typedef _ClosedForumTab = ({
  String siteUrl,
  String accountIdentity,
  ForumTab tab,
  int index,
});
typedef _TopicPostHighlight = ({
  String siteUrl,
  int topicId,
  int postNumber,
  String? tabId,
});

int? _destinationNumericId(String destinationId, String prefix) {
  if (!destinationId.startsWith(prefix)) return null;
  final id = int.tryParse(destinationId.substring(prefix.length));
  return id != null && id > 0 ? id : null;
}

final class DestinationBookmarkAction {
  const DestinationBookmarkAction({
    required this.bookmarked,
    required this.invoke,
  });
  final bool bookmarked;
  final Future<BookmarkWriteResult> Function() invoke;
}

final class PostPermanentDeleteTarget {
  const PostPermanentDeleteTarget._({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required this.postNumber,
    required this._lease,
  });

  final String siteUrl;
  final int topicId;
  final int postId;
  final int postNumber;
  final SiteLease _lease;

  bool get deletesTopic => postNumber == 1;
}

final class PostNoticeTarget {
  const PostNoticeTarget._({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required this._lease,
  });

  final String siteUrl;
  final int topicId;
  final int postId;
  final SiteLease _lease;
}

final class TopicPostMoveTarget {
  const TopicPostMoveTarget._({
    required this.siteUrl,
    required this.topicId,
    required this.privateMessage,
    required this._lease,
  });

  final String siteUrl;
  final int topicId;

  /// Whether the source was a message when the move was offered. Its posts
  /// move only into a message, and a source that has changed archetype since
  /// is refused rather than moved as the other kind.
  final bool privateMessage;
  final SiteLease _lease;
}

final class TopicPostOwnerTarget {
  const TopicPostOwnerTarget._({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required this._lease,
  });

  final String siteUrl;
  final int topicId;

  // Null retains selected-post mode: read the topic's selection on submit.
  final int? postId;
  final SiteLease _lease;
}

class ShellController extends FrameSafeNotifier
    implements
        PluginNavigationHost,
        BookmarkHost,
        PluginNotificationFeedHost,
        AccountSessionHost {
  ShellController({
    required this.instanceStore,
    required ShellApiCapabilities api,
    required this.authenticator,
    required this.drafts,
    EmojiPickerStore? emojiPickerStore,
    AppSettingsStore? appSettingsStore,
    ForumSettingsStore? forumSettingsStore,
    ForumTabStore? forumTabs,
    RecentDestinationsStore? recentDestinations,
    DestinationBookmarksStore? destinationBookmarks,
    this.forumTabsEnabled = true,
    this.mobileNavigationEnabled = false,
    Store? store,
    SiteLifecycle? lifecycle,
    DateTime Function()? clock,
    SiteImageRepository? siteImages,
    SiteVideoThumbnailRepository? videoThumbnails,
    SitePdfThumbnailRepository? pdfThumbnails,
    this._discoverSites,
    this.trackers = SiteTracker.new,
    Updater updater = const UnsupportedUpdater(),
    UpdateStore? updateStore,
    this.ownsApi = true,
    this.topicLoadTimeout = const Duration(seconds: 30),
    this.anchorPersistDebounce = const Duration(milliseconds: 500),
    this.pluginNotificationFeedRefreshDebounce = const Duration(
      milliseconds: 500,
    ),
    ShellRootMode initialRootMode = ShellRootMode.forum,
    InstalledPlugins? plugins,
    CookingServicePort? cookingService,
    PluginDiagnosticsReporter? pluginDiagnosticsReporter,
  }) : api = ShellApiPorts.fromCapabilities(api),
       forumTabs = forumTabs ?? ForumTabStore.memory(),
       recentDestinations =
           recentDestinations ?? RecentDestinationsStore.memory(),
       destinationBookmarks =
           destinationBookmarks ?? DestinationBookmarksStore.memory(),
       appSettings = AppSettingsController(
         store:
             appSettingsStore ??
             AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
       ),
       forumSettings = ForumSettingsController(
         store: forumSettingsStore ?? ForumSettingsStore.memory(),
       ),
       emojiPickerStore = emojiPickerStore ?? EmojiPickerStore(),
       assert(topicLoadTimeout > Duration.zero),
       assert(anchorPersistDebounce >= Duration.zero),
       assert(pluginNotificationFeedRefreshDebounce >= Duration.zero),
       store = store ?? Store(policy: _shellEntityStorePolicy),
       lifecycle = lifecycle ?? SiteLifecycle(),
       _clock = clock ?? DateTime.now,
       _providedSiteImages = siteImages,
       _providedVideoThumbnails = videoThumbnails,
       _providedPdfThumbnails = pdfThumbnails,
       _rootMode = initialRootMode,
       _providedCookingService = cookingService,
       _ownsPlugins = plugins == null,
       _pluginDiagnosticsReporter =
           pluginDiagnosticsReporter ??
           const PluginDiagnosticsReporter.ambient(),
       plugins = plugins ?? PluginInstaller.install(corePluginManifest),
       updates = UpdateController(
         updater: updater,
         store: updateStore ?? UpdateStore(),
       );

  final CookingServicePort? _providedCookingService;
  late final ApplicationCooking cooking = ApplicationCooking(
    plugins: plugins,
    service: _providedCookingService,
  );
  final _cookingRequestStamps = Expando<_CookingSourceStamp>();
  final Set<_CookingWatch> _cookingWatches = {};

  _CookingSourceStamp _cookingStamp(String siteUrl) {
    final user = currentUserFor(siteUrl);
    return (
      revision: cooking.contextRevisionFor(siteUrl),
      config: siteConfigFor(siteUrl),
      presentation: _presentation.presentationTokenFor(siteUrl),
      staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
      user: (user?.id, user?.username, user?.timezone),
      readerTimezone: TimezoneEnvironment.instance.readerTimezone(
        user?.timezone,
      ),
      users: store.generationOf<UserCard>(siteUrl),
      topics: store.generationOf<TopicDetail>(siteUrl),
    );
  }

  /// Original request identity is retained for host preflight decisions.
  bool cookingRequestIsCurrent(CookingRequest request) =>
      !isDisposed &&
      cooking.isCurrent(request) &&
      _cookingRequestStamps[request] == _cookingStamp(request.snapshot.siteId);

  VoidCallback watchCooking({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  }) {
    if (isDisposed) return () {};
    final watch = _CookingWatch(
      read: () => _cookingStamp(siteUrl),
      onChanged: onChanged,
    );
    _cookingWatches.add(watch);
    watch.listen(_presentation);
    watch.listen(TimezoneEnvironment.instance);
    watch.onRetire(cooking.watchContext(siteUrl, watch.changed));
    if (raw.length <= 65536) {
      for (final id in _cookingTopicIds(raw)) {
        watch.listen(store.ref<TopicDetail>(siteUrl, id));
      }
      for (final name in _cookingUsernames(raw)) {
        watch.listen(store.ref<UserCard>(siteUrl, name.toLowerCase()));
      }
    }
    return () {
      watch.retire();
      _cookingWatches.remove(watch);
    };
  }

  CookingRequest cookingRequest({
    required String siteUrl,
    required String raw,
    CookingProfile profile = CookingProfile.post,
    CookingContext context = const CookingContext(),
    CookingCachedMetadata? cachedMetadata,
  }) {
    CookingRequest track(CookingRequest request) {
      _cookingRequestStamps[request] = _cookingStamp(siteUrl);
      return request;
    }

    if (raw.length > 65536) {
      return track(
        cooking.request(
          siteUrl: siteUrl,
          accountId: _instanceAt(siteUrl)?.user?.id.toString() ?? 'anonymous',
          raw: raw,
          profile: profile,
          config: const SiteConfig.unknown(),
        ),
      );
    }
    return track(
      cooking.request(
        siteUrl: siteUrl,
        accountId: _instanceAt(siteUrl)?.user?.id.toString() ?? 'anonymous',
        raw: raw,
        profile: profile,
        context: context,
        cachedMetadata: cachedMetadata ?? _cachedCookingMetadata(siteUrl, raw),
        config: siteConfigFor(siteUrl),
        staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
        mentions: _mentioned[siteUrl]?.snapshot ?? const {},
        hashtags: {
          for (final entry in (_hashtags[siteUrl]?.snapshot ?? {}).entries)
            if (entry.value case final FoundHashtag hashtag)
              entry.key: {
                'type': hashtag.type,
                'ref': hashtag.ref,
                'slug': hashtag.slug,
                'text': hashtag.text,
                'relative_url': hashtag.relativeUrl,
                'icon': hashtag.icon,
                'id': hashtag.id,
                'style_type': hashtag.styleType,
                'emoji': hashtag.emoji,
                'colors': hashtag.colors,
              },
        },
        customEmoji: _presentation.cachedCustomEmojiFor(siteUrl),
      ),
    );
  }

  static Iterable<int> _cookingTopicIds(String raw) => RegExp(r'topic:(\d+)')
      .allMatches(raw)
      .take(128)
      .map((match) => int.tryParse(match[1]!))
      .whereType<int>()
      .toSet();

  static Set<String> _cookingUsernames(String raw) => {
    for (final match in RegExp(
      r'(?:@|quote="|\[quote=")([\w.-]+)',
    ).allMatches(raw).take(128))
      match[1]!,
  };

  CookingCachedMetadata _cachedCookingMetadata(String siteUrl, String raw) {
    final topics = <String, CookingTopic>{};
    for (final id in _cookingTopicIds(raw)) {
      final topic = store.read<TopicDetail>(siteUrl, id);
      if (topic != null) {
        topics['${topic.id}'] = CookingTopic(
          title: topic.title,
          href: '$siteUrl/t/${topic.id}',
        );
      }
    }
    final names = _cookingUsernames(raw);
    final mentions = <String, CookingMention>{};
    final avatars = <String, String>{};
    for (final name in names) {
      final card = store.read<UserCard>(siteUrl, name.toLowerCase());
      if (card == null) continue;
      mentions[name] = CookingMention(
        username: card.username,
        href:
            '${Uri.parse(siteUrl).path.replaceFirst(RegExp(r'/+$'), '')}/u/${Uri.encodeComponent(card.username)}',
        kind: CookingMentionKind.user,
      );
      if (card.avatarUrl case final String url) {
        avatars[name] =
            '<img class="avatar" src="${const HtmlEscape().convert(url)}">';
      }
    }
    return CookingCachedMetadata(
      topics: topics,
      mentions: mentions,
      avatars: avatars,
    );
  }

  final InstanceStore instanceStore;
  final ForumTabStore forumTabs;
  final RecentDestinationsStore recentDestinations;
  final DestinationBookmarksStore destinationBookmarks;
  int _destinationBookmarksRevision = 0;
  int get destinationBookmarksRevision => _destinationBookmarksRevision;
  final AppSettingsController appSettings;
  final ForumSettingsController forumSettings;
  final sidebarSections = SidebarSectionStore();
  final topicSidebar = TopicSidebarStore();

  final bool forumTabsEnabled;
  final bool mobileNavigationEnabled;
  final mobileNavigation = MobileNavigation();

  @override
  final Store store;

  final ShellApiPorts api;

  DiscoverSites? _discoverSites;
  DiscoverSites get discoverSites => _discoverSites ??= DiscoverSites();

  final bool ownsApi;

  final Duration topicLoadTimeout;

  final Duration anchorPersistDebounce;

  final Duration pluginNotificationFeedRefreshDebounce;

  /// Reaches secure storage whatever the account state, which only the account
  /// session transaction may do: connect must find the key it replaces to
  /// revoke it. Site requests read their key through [credentials].
  final Authenticator authenticator;

  /// The only reader of site API keys for requests: it answers a key only
  /// while the rail's stored instance for that site is signed in, so a key
  /// left in secure storage after a reinstall or a failed deletion never
  /// reads or writes as the retired account.
  late final ApiCredentialReader credentials = ConnectedAccountCredentials(
    authenticator,
    isConnected: (siteUrl) => _instanceAt(siteUrl)?.isConnected == true,
  );
  final DraftStore drafts;
  final EmojiPickerStore emojiPickerStore;
  final SiteLifecycle lifecycle;
  final DateTime Function() _clock;
  late final AccountSessionCoordinator _accountSessions =
      AccountSessionCoordinator(
        authenticator: authenticator,
        instances: instanceStore,
        drafts: drafts,
        lifecycle: lifecycle,
        api: api.site,
        host: this,
        reportError: (error, stackTrace, operation, {required bool warning}) {
          _reportOperationalError(
            error,
            stackTrace,
            operation,
            severity: warning
                ? DiagnosticSeverity.warning
                : DiagnosticSeverity.error,
          );
        },
      );
  final SiteImageRepository? _providedSiteImages;
  final SiteVideoThumbnailRepository? _providedVideoThumbnails;
  final SitePdfThumbnailRepository? _providedPdfThumbnails;
  final InstalledPlugins plugins;
  final bool _ownsPlugins;
  final PluginDiagnosticsReporter _pluginDiagnosticsReporter;
  Future<void>? _pluginTeardownFuture;

  Future<void> get pluginTeardown =>
      _pluginTeardownFuture ?? Future<void>.value();

  late final PluginBackgroundRetentionRegistry _backgroundRetention =
      PluginBackgroundRetentionRegistry(
        canRetain: (siteUrl) => _instanceAt(siteUrl) != null,
        onChanged: _syncTracking,
      );

  late final SiteImageRepository siteImages =
      _providedSiteImages ??
      SiteImageRepository(credentials: credentials, lifecycle: lifecycle);

  late final SiteVideoThumbnailRepository videoThumbnails =
      _providedVideoThumbnails ??
      SiteVideoThumbnailRepository(
        credentials: credentials,
        lifecycle: lifecycle,
      );

  late final SitePdfThumbnailRepository pdfThumbnails =
      _providedPdfThumbnails ??
      SitePdfThumbnailRepository(
        credentials: credentials,
        lifecycle: lifecycle,
      );

  late final PluginSession _pluginSession = plugins.openSession(
    PluginHostBindings(<PluginHostPort<Object>>[
      PluginHostPort<Object>(corePluginTransportPort, api.pluginTransport),
      PluginHostPort<Object>(
        corePluginTimezonePort,
        PluginTimezoneHost(
          readerTimezone: TimezoneEnvironment.instance.readerTimezone,
          location: TimezoneEnvironment.instance.location,
          timezoneNames: () => TimezoneEnvironment.instance.timezoneNames,
          changes: Listenable.merge([TimezoneEnvironment.instance]),
        ),
      ),
      PluginHostPort<Object>(
        corePluginPostEditorPort,
        PluginPostEditorHost(
          open: (siteUrl, postId, {focusText}) {
            final post = store.read<Post>(siteUrl, postId);
            if (currentInstance?.url != siteUrl ||
                post == null ||
                currentTopic?.stream.contains(postId) != true ||
                !post.canEdit) {
              return false;
            }
            openEdit(post, focusText: focusText);
            return switch (_composer?.target) {
              PostEditingComposerTarget(:final editingPostId) =>
                editingPostId == postId,
              _ => false,
            };
          },
        ),
      ),
      PluginHostPort<Object>(
        corePluginPostQuotePort,
        PluginPostQuoteHost(
          open: (siteUrl, postId, contents) async {
            final post = store.read<Post>(siteUrl, postId);
            final topic = currentTopic;
            if (isDisposed ||
                currentInstance?.url != siteUrl ||
                topic == null ||
                post == null ||
                !topic.stream.contains(postId)) {
              return;
            }
            await openQuote(
              post,
              buildPostQuote(
                post: post,
                topicId: topic.id,
                contents: contents,
                config: siteConfigFor(siteUrl),
              ),
            );
          },
        ),
      ),
      PluginHostPort<Object>(corePluginModelCodecPort, api.models),
      PluginHostPort<Object>(
        corePluginRequestPort,
        _ShellPluginRequestHost(this),
      ),
      PluginHostPort<Object>(
        corePluginUserOptionsPort,
        PluginUserOptionsHost(
          api: api.userPreferences,
          updateData: (siteUrl, field, update) {
            final instance = _instanceAt(siteUrl);
            final user = instance?.user;
            if (instance == null || user == null) return;
            final updated = _currentUserReconcilerFor(
              siteUrl,
            ).updatePluginOption(field, previous: user, update: update);
            if (updated == user) return;
            _replaceInstance(instance, instance.copyWith(user: updated));
            unawaited(_persistPreferencesMirror(List.of(_instances)));
          },
        ),
      ),
      _pluginPostHostPort(),
      PluginHostPort<Object>(
        corePluginAccountConnectionPort,
        _ShellPluginAccountConnectionHost(this),
      ),
      PluginHostPort<Object>(
        pluginDiagnosticsReporterPort,
        _pluginDiagnosticsReporter,
      ),
      PluginHostPort<Object>(
        corePluginSiteStatePort,
        PluginSiteStateHost(
          currentUserFor: (siteUrl) => _instanceAt(siteUrl)?.user,
          siteConfigFor: siteConfigFor,
          categoryFor: (siteUrl, id) => categoryFor(id, siteUrl: siteUrl),
        ),
      ),
      PluginHostPort<Object>(
        corePluginStaticContributionsPort,
        plugins.staticContributionsFor(const PluginId('core')),
        scopeToConsumer: plugins.staticContributionsFor,
      ),
      PluginHostPort<Object>(
        corePluginCurrentSitePort,
        () => currentInstance?.url,
      ),
      PluginHostPort<Object>(corePluginPostFlagCatalogPort, postFlagTypesFor),
      PluginHostPort<Object>(
        corePluginCookingPort,
        PluginCookingHost(
          request: cookingRequest,
          cook: cooking.cook,
          isCurrent: cookingRequestIsCurrent,
          watch: watchCooking,
        ),
      ),
      _pluginAccountEventsHostPort(),
      _pluginTargetHostPort(),
      _pluginFreshAccountHostPort(),
      PluginHostPort<Object>(
        corePluginTopicRefreshPort,
        PluginTopicRefreshHost(
          reloadTopic: (siteUrl, topicId) =>
              _topicData.forSite(siteUrl).refresh(topicId, slug: ''),
        ),
      ),
      _pluginTrackerHostPort(),
      _pluginBackgroundRetentionHostPort(),
      PluginHostPort<Object>(
        corePluginUserPort,
        (String siteUrl) => _instanceAt(siteUrl)?.user?.id,
      ),
      PluginHostPort<Object>(
        corePluginPresentationPort,
        (String siteUrl) => _presentation.resolveConfig(siteUrl),
      ),
      PluginHostPort<Object>(
        corePluginNavigationPort,
        _ShellPluginNavigationHost(this, () => isDisposed),
      ),
      PluginHostPort<Object>(
        corePluginRouteNavigationPort,
        _ShellPluginRouteNavigationHost(this),
      ),
      PluginHostPort<Object>(
        corePluginTopicListNavigationPort,
        _ShellPluginTopicListNavigationHost(this),
      ),
      _pluginBookmarkHostPort(),
      _pluginComposerHostPort(),
      _pluginEmojiHostPort(),
      _pluginNotificationFeedHostPort(),
    ]),
  );

  PluginSession get pluginSession => _pluginSession;

  PluginHostPort<Object> _pluginBookmarkHostPort() {
    final factory = _ShellPluginBookmarkHostFactory(this);
    return PluginHostPort<Object>(
      corePluginBookmarkPort,
      factory,
      scopeToConsumer: factory.scopedTo,
    );
  }

  PluginHostPort<Object> _pluginAccountEventsHostPort() {
    final host = PluginAccountEventsHost(
      updateNotificationCounter: (siteUrl, id, reduce) {
        final counter = plugins.registry.notificationCounter(id);
        if (counter == null) {
          throw PluginInstallationException(
            appL10n.notificationCounterIsNotRegistered((id.id).toString()),
          );
        }
        accountActivity.applyPluginCounter(siteUrl, counter, reduce);
      },
      markSiteUnreachable: _markForumUnavailable,
    );
    return PluginHostPort<Object>(
      corePluginAccountEventsPort,
      host,
      scopeToConsumer: (consumer) => PluginAccountEventsHost(
        updateNotificationCounter: (siteUrl, id, reduce) {
          if (id.owner != consumer) {
            throw PluginInstallationException(
              appL10n.pluginCannotUpdateNotificationCounter(
                (consumer).toString(),
                (id.id).toString(),
              ),
            );
          }
          host.updateNotificationCounter(siteUrl, id, reduce);
        },
        markSiteUnreachable: host.markSiteUnreachable,
      ),
    );
  }

  PluginHostPort<Object> _pluginPostHostPort() => PluginHostPort<Object>(
    corePluginPostPort,
    _ShellPluginPostHost(this, const PluginId('core')),
    scopeToConsumer: (consumer) => _ShellPluginPostHost(this, consumer),
  );

  PluginHostPort<Object> _pluginTargetHostPort() => PluginHostPort<Object>(
    corePluginTargetPort,
    _ShellPluginTargetHost(this, const PluginId('core')),
    scopeToConsumer: (consumer) => _ShellPluginTargetHost(this, consumer),
  );

  PluginHostPort<Object> _pluginFreshAccountHostPort() =>
      PluginHostPort<Object>(
        corePluginFreshAccountPort,
        _ShellPluginFreshAccountHost(this, const PluginId('core')),
        scopeToConsumer: (consumer) =>
            _ShellPluginFreshAccountHost(this, consumer),
      );

  PluginHostPort<Object> _pluginComposerHostPort() {
    final host = PluginComposerHost(
      buildComposer: buildPluginComposer,
      openNewTopic: openNewTopicFromPlugin,
      isActive: (composer) =>
          !isDisposed && identical(visibleComposer, composer),
      siteConfigFor: siteConfigFor,
      siteConfigListenableFor: _pluginSiteConfigListenableFor,
    );
    return PluginHostPort<Object>(
      corePluginComposerPort,
      host,
      scopeToConsumer: (consumer) => PluginComposerHost(
        buildComposer: (request) {
          if (request.kind.owner != consumer) {
            throw PluginInstallationException(
              appL10n.pluginCannotBuildComposerTarget(
                (consumer).toString(),
                (request.kind.id).toString(),
              ),
            );
          }
          return host.buildComposer(request);
        },
        openNewTopic: host.openNewTopic,
        isActive: host.isActive,
        siteConfigFor: host.siteConfigFor,
        siteConfigListenableFor: host.siteConfigListenableFor,
      ),
    );
  }

  PluginHostPort<Object> _pluginEmojiHostPort() {
    final host = PluginEmojiHost(
      preferences: emojiPickerStore,
      siteConfigFor: siteConfigFor,
      loadCatalog: (siteUrl, {refresh = false}) =>
          refresh ? refreshEmojiCatalog(siteUrl) : ensureEmojiCatalog(siteUrl),
      loadSearchAliases: (siteUrl, {refresh = false}) => refresh
          ? refreshEmojiSearchAliases(siteUrl)
          : ensureEmojiSearchAliases(siteUrl),
      resolveUrl: emojiUrlFor,
    );
    return PluginHostPort<Object>(
      corePluginEmojiPort,
      host,
      scopeToConsumer: (consumer) => PluginEmojiHost(
        preferences: _ScopedEmojiPreferenceStore(emojiPickerStore, consumer),
        siteConfigFor: host.siteConfigFor,
        loadCatalog: host.loadCatalog,
        loadSearchAliases: host.loadSearchAliases,
        resolveUrl: host.resolveUrl,
      ),
    );
  }

  PluginHostPort<Object> _pluginNotificationFeedHostPort() {
    final host = _ShellPluginNotificationFeedHost(this);
    return PluginHostPort<Object>(
      corePluginNotificationFeedPort,
      host,
      scopeToConsumer: (consumer) =>
          _ShellScopedPluginNotificationFeedHost(host, consumer, {
            for (final source in plugins.registry.notificationFeeds)
              if (source.id.owner == consumer) source.id: source,
          }),
    );
  }

  PluginHostPort<Object> _pluginTrackerHostPort() {
    PluginTrackerReader scopedReader(PluginId consumer) => (siteUrl) {
      final tracker = _trackers[siteUrl];
      if (tracker == null) return null;
      return tracker.pluginLiveChannels(plugins.liveChannelScopesFor(consumer));
    };

    return PluginHostPort<Object>(
      corePluginTrackerPort,
      scopedReader(const PluginId('core')),
      scopeToConsumer: scopedReader,
    );
  }

  PluginHostPort<Object> _pluginBackgroundRetentionHostPort() =>
      PluginHostPort<Object>(
        corePluginBackgroundRetentionPort,
        _backgroundRetention.scopedTo(const PluginId('core')),
        scopeToConsumer: _backgroundRetention.scopedTo,
        revokeConsumer: _backgroundRetention.releaseOwner,
      );

  Set<String> get _pluginBackgroundSiteUrls => _backgroundRetention.siteUrls;

  Future<PluginWriteCredential> pluginWriteCredential(String siteUrl) async {
    try {
      final lease = lifecycle.capture(siteUrl);
      final snapshot = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (snapshot.apiKey == null) {
        return (
          credentials: null,
          failure: const WriteException(WriteFailure.forbidden),
        );
      }
      return (
        credentials: PluginRequestCredentials(
          apiKey: snapshot.apiKey,
          clientId: '',
          execute: snapshot.run,
        ),
        failure: null,
      );
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.readWriteCredential',
      );
      return (
        credentials: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  bool beginPluginPostWrite(String siteUrl, int postId) =>
      _topicData.forSite(siteUrl).beginPluginWrite(postId);

  void endPluginPostWrite(String siteUrl, int postId) =>
      _topicData.forSite(siteUrl).endPluginWrite(postId);

  bool pluginPostWriteInFlight(String siteUrl, int postId) =>
      _topicData.forSite(siteUrl).postWriting(postId);

  Future<void> refreshPluginPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) async {
    await _topicData
        .forLease(siteUrl, lease)
        ?.repairPost(topicId, postId, apiKey, lease);
  }

  void notifyPluginStateChanged() => _notify();

  void _reportOperationalError(
    Object error,
    StackTrace stackTrace,
    String operation, {
    bool degraded = true,
    DiagnosticSeverity severity = DiagnosticSeverity.error,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'shell',
      severity: severity,
      handled: true,
      degraded: degraded,
    );
  }

  void _observePluginLifecycle(Future<void> task, String operation) {
    unawaited(
      task.onError((Object error, StackTrace stackTrace) {
        _reportOperationalError(
          error,
          stackTrace,
          operation,
          severity: DiagnosticSeverity.warning,
        );
      }),
    );
  }

  Future<_ShellWriteCredential> _credentialForWrite(
    String siteUrl, {
    SiteLease? lease,
    bool withClientId = false,
  }) async {
    try {
      final session = AccountRequestSession(
        siteUrl,
        lease ?? lifecycle.capture(siteUrl),
      );
      final request = withClientId
          ? await session.credentials(credentials)
          : await session.keyCredentials(credentials);
      final apiKey = request.apiKey;
      return apiKey == null
          ? (
              apiKey: null,
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: apiKey, request: request, failure: null);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.readWriteCredential',
      );
      return (
        apiKey: null,
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  final SiteTrackerFactory trackers;

  final UpdateController updates;

  late final AccountActivityController accountActivity =
      AccountActivityController(
        likeNotificationTypes: plugins.registry.likeNotificationTypes,
        api: api.accountActivity,
        credentials: credentials,
        lifecycle: lifecycle,
        onTotalsLoaded: _onTotalsLoaded,
        onTotalsChanged: _onTotalsChanged,
        onGroupedUnreadAuthorityAdvanced: _onGroupedUnreadAuthorityAdvanced,
      );

  late final DoNotDisturbController doNotDisturb = DoNotDisturbController(
    api: api.doNotDisturb,
    credentials: credentials,
    lifecycle: lifecycle,
    onCommitted: _commitDoNotDisturb,
    clock: _clock,
  );

  late final UserStatusOverrides userStatuses = UserStatusOverrides();

  /// Profile-card fetches by lowercase username; the cards live in [store].
  late final PreviewRequests<String> userCardRequests = PreviewRequests();

  /// Post-likers fetches by post ID; the likers live in [store].
  late final PreviewRequests<int> likerRequests = PreviewRequests();

  late final DraftListController draftList = DraftListController(
    api: api.drafts,
    credentials: credentials,
    lifecycle: lifecycle,
    deleteDraft: (siteUrl, draft, isCurrent) =>
        _composerDrafts.deleteListedDraft(siteUrl, draft, isCurrent),
  );

  late final UserSummaryController userSummary = UserSummaryController(
    api: api.userSummaries,
    credentials: credentials,
    lifecycle: lifecycle,
  );

  late final BadgesController badges = BadgesController(
    api: BadgesApi(api.pluginTransport),
    credentials: credentials,
    lifecycle: lifecycle,
  );

  late final GroupsController groups = GroupsController(
    api: GroupsApi(api.pluginTransport, api.models),
    credentials: credentials,
    lifecycle: lifecycle,
  );

  late final UserDirectoryController userDirectory = UserDirectoryController(
    api: UserDirectoryApi(api.pluginTransport, api.models),
    credentials: credentials,
    lifecycle: lifecycle,
  );

  late final PreferencesController preferences = PreferencesController(
    api: api.userPreferences,
    credentials: credentials,
    lifecycle: lifecycle,
    onSaved: _onPreferencesSaved,
  );

  late final TopicFeedController topicFeeds = _createTopicFeedController();

  TopicFeedController _createTopicFeedController() {
    return TopicFeedController(
      api: api.topicFeeds,
      credentials: credentials,
      lifecycle: lifecycle,
      store: store,
      readerTopics: (siteUrl, destinationId) => {
        for (final tab in workspaceFor(siteUrl)?.tabs ?? const <ForumTab>[])
          if (tab.currentContent.topicId case final id?)
            if ((tab.contentStack.reversed
                        .where((route) => !route.isTopic)
                        .firstOrNull
                        ?.id ??
                    tab.rootDestinationId) ==
                destinationId)
              id,
      },
      prepareFeed: (instance, apiKey, categories, categoryIds) async {
        final lease = lifecycle.capture(instance.url);
        if (categories.isNotEmpty) {
          _taxonomy.mergeCategories(instance.url, categories);
          _notify();
        }
        if (isDisposed || !lease.isCurrent) return;
        unawaited(
          RequestIntent.background().run(
            () => _taxonomy.ensureCategoriesFor(instance),
          ),
        );
        await _taxonomy.ensureCategoryIds(instance, categoryIds);
      },
      readPersonalizationVersion: (siteUrl) =>
          _bookmarks.forSite(siteUrl).epoch,
      prepareTopicForStore: _prepareTopicForStore,
      incomingFilterFor: _incomingTopicsFilter,
      onFeedLoaded: (instance, _, _, _) => _trackIncomingLists(instance.url),
    );
  }

  late final TopicReadController _topicReads = TopicReadController(
    api: api.topicReads,
    credentials: credentials,
    lifecycle: lifecycle,
    store: store,
    reportError: (error, stackTrace, operation) {
      _reportOperationalError(
        error,
        stackTrace,
        operation,
        severity: DiagnosticSeverity.warning,
      );
    },
  );

  late final ShellSearchController search = ShellSearchController(
    api: api.search,
    credentials: credentials,
    lifecycle: lifecycle,
  );

  late final GlobalSearchController globalSearch = GlobalSearchController(
    api: GlobalSearchApi(transport: api.pluginTransport),
    credentials: credentials,
    lifecycle: lifecycle,
    recentSource: search,
  );

  SitePresentationController? _sitePresentation;
  final Map<String, _PluginSiteConfigListenable> _pluginSiteConfigListenables =
      {};

  ValueListenable<SiteConfig> _pluginSiteConfigListenableFor(String siteUrl) =>
      _pluginSiteConfigListenables.putIfAbsent(
        siteUrl,
        () => _PluginSiteConfigListenable(
          _presentation,
          () => siteConfigFor(siteUrl),
        ),
      );

  SitePresentationController get _presentation =>
      _sitePresentation ??= _createSitePresentationController();

  SitePresentationController _createSitePresentationController() {
    final controller = SitePresentationController(
      loadAppearance: _loadSiteAppearance,
      loadConfig: _loadSiteConfig,
      loadCustomEmojis: _loadCustomEmojis,
      loadEmojiCatalog: _loadEmojiCatalog,
      loadEmojiSearchAliases: _loadEmojiSearchAliases,
      credentials: credentials,
      lifecycle: lifecycle,
      readPersistedAppearance: (siteUrl) => _instanceAt(siteUrl)?.appearance,
      readPersistedConfig: (siteUrl) => _instanceAt(siteUrl)?.config,
      onAppearanceLoaded: _persistSiteAppearance,
      onConfigLoaded: _persistSiteConfig,
    );
    controller.addListener(_notify);
    return controller;
  }

  Future<SiteAppearance?> _loadSiteAppearance({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    // A failed credential deletion can leave an orphaned key behind. The stored
    // instance identity is the account boundary: signed-out sites may refresh
    // their public colors, but must never forward that leftover credential.
    final instance = _instanceAt(siteUrl);
    final authenticate = apiKey != null && instance?.isConnected == true;
    return api.site.siteAppearance(
      siteUrl: siteUrl,
      username: authenticate ? instance!.user!.username : null,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<ForumAbout> loadForumAbout(String siteUrl) async {
    final instance = instanceFor(siteUrl);
    final lease = lifecycle.capture(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    final session = AccountRequestSession(siteUrl, lease);
    final credential = instance.isConnected
        ? await session.credentials(credentials)
        : session.anonymousCredentials();
    if (instance.isConnected && credential.apiKey == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    final about = await credential.run(
      () => api.site.forumAbout(
        siteUrl: siteUrl,
        apiKey: credential.apiKey,
        clientId: credential.clientId,
      ),
    );
    if (isDisposed || !lease.isCurrent) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return about;
  }

  Future<SiteConfig> _loadSiteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    // As with appearance, key presence is not account identity: secure storage
    // can retain a key after a failed deletion. A signed-out instance must ask
    // only for the site's public client settings.
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.siteConfig(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<Map<String, String>> _loadCustomEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.customEmojis(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<SiteEmojiCatalog> _loadEmojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.emojiCatalog(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<Map<String, List<String>>> _loadEmojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.emojiSearchAliases(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  String? _connectingSiteUrl;

  bool get connecting => _connectingSiteUrl == currentInstance?.url;

  final Map<String, String> _connectErrors = {};

  String? get connectError {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _connectErrors[siteUrl];
  }

  final Set<String> _unavailableForums = {};
  final Set<String> _retryingUnavailableForums = {};

  bool get currentForumUnavailable {
    final siteUrl = currentInstance?.url;
    return siteUrl != null && _unavailableForums.contains(siteUrl);
  }

  bool get retryingCurrentForum {
    final siteUrl = currentInstance?.url;
    return siteUrl != null && _retryingUnavailableForums.contains(siteUrl);
  }

  void _markForumUnavailable(String siteUrl) {
    if (_instanceAt(siteUrl) == null || !_unavailableForums.add(siteUrl)) {
      return;
    }
    _notify();
  }

  Future<void> retryCurrentForum() async {
    final instance = currentInstance;
    final route = currentContent;
    if (instance == null ||
        route == null ||
        ContentPageContract.resolve(route).retry !=
            PageRetry.unavailableExtension ||
        !_unavailableForums.contains(instance.url) ||
        !_retryingUnavailableForums.add(instance.url)) {
      return;
    }

    _notify();
    try {
      for (final retry in _pluginSession.capabilities<PluginRouteRetry>()) {
        final result = await retry.retryPluginRoute(instance.url, route.id);
        if (result == PluginRouteRetryResult.notHandled) continue;
        if (!isDisposed && result == PluginRouteRetryResult.succeeded) {
          _unavailableForums.remove(instance.url);
        }
        break;
      }
    } finally {
      if (!isDisposed) {
        _retryingUnavailableForums.remove(instance.url);
        _notify();
      }
    }
  }

  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    for (final handler in _pluginSession.capabilities<PluginLinkHandler>()) {
      if (await handler.openPluginUrl(
        url,
        origin: origin,
        onNavigated: onNavigated,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<bool> openNotificationUrl(String url) async {
    if (isDisposed ||
        !loaded ||
        url.isEmpty ||
        url.length > TopicLink.maximumUrlLength) {
      return false;
    }

    final Uri target;
    try {
      target = requireSafeHttpUrl(_notificationSpelling(Uri.parse(url)));
    } on FormatException {
      return false;
    } on UnsafeHttpTransportException {
      return false;
    }

    final owner = mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (instance) => instance.url,
    );
    if (owner == null || !owner.forum.isConnected) return false;

    final ownerUrl = owner.forum.url;
    final lease = lifecycle.capture(ownerUrl);
    final absolute = target.toString();
    final pluginHandled = await openPluginUrl(
      absolute,
      origin: PluginLinkOrigin.inApp,
    );
    if (isDisposed ||
        !lease.isCurrent ||
        _instanceAt(ownerUrl)?.isConnected != true) {
      return false;
    }
    final currentOwner = mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (instance) => instance.url,
    );
    if (currentOwner?.forum.url != ownerUrl) {
      return false;
    }
    if (pluginHandled) {
      return _revealNotificationTarget();
    }
    if (openBadgeUrl(absolute, refresh: true)) {
      return _revealNotificationTarget();
    }
    if (openGroupUrl(absolute)) return _revealNotificationTarget();
    if (_openTopicUrl(absolute, refresh: true)) {
      return _revealNotificationTarget();
    }
    if (openCorePageUrl(absolute)) return _revealNotificationTarget();
    if (openListUrl(absolute)) return _revealNotificationTarget();
    return false;
  }

  /// Discourse spells the URL a push carries with `http` unless the site
  /// forces https, which is off by default, so a forum this app reaches over
  /// https names its own pages in plaintext. Nothing is fetched from a
  /// notification URL — it only selects a route — so such a URL is read as
  /// the page of the connected https forum serving that host and port. Any
  /// other plaintext URL is left for the transport check to refuse.
  Uri _notificationSpelling(Uri link) {
    if (link.scheme != 'http') return link;
    final owned = _instances.any(
      (instance) =>
          instance.isConnected &&
          Uri.parse(instance.url).scheme == 'https' &&
          instance.serves(link),
    );
    return owned ? link.replace(scheme: 'https') : link;
  }

  bool _revealNotificationTarget() {
    final changed = _setForumContentRoot();
    if (changed) _notify();
    return true;
  }

  bool _setForumContentRoot() {
    final changed =
        _rootMode != ShellRootMode.forum || _mobilePane != MobilePane.content;
    _rootMode = ShellRootMode.forum;
    _mobilePane = MobilePane.content;
    return changed;
  }

  final List<DiscourseInstance> _instances = [];
  @override
  List<DiscourseInstance> get instances => List.unmodifiable(_instances);
  bool get hasInstances => _instances.isNotEmpty;

  // Reorders are optimistic, just like adding and removing a site. This small
  // drain owns their writes because InstanceStore coalesces queued snapshots:
  // one failed older write must not roll a newer drag out of the rail.
  int _instanceReorderRevision = 0;
  bool _savingInstanceOrder = false;
  List<String> _durableInstanceOrder = const [];
  final List<({int revision, Completer<bool> result})>
  _pendingInstanceReorders = [];

  InstanceLoadStatus _loadStatus = InstanceLoadStatus.loading;

  InstanceLoadStatus get loadStatus => _loadStatus;

  bool get loaded => _loadStatus == InstanceLoadStatus.ready;

  int _instanceIndex = 0;
  int get instanceIndex => _instanceIndex;
  @override
  DiscourseInstance? get currentInstance =>
      hasInstances ? _instances[_instanceIndex] : null;

  String? get currentAccountIdentity {
    final instance = currentInstance;
    return instance == null ? null : _workspaceAccountIdentity(instance);
  }

  late final _workspace = _WorkspaceController(this);
  late final _taxonomy = _TaxonomyDirectoryController(this);

  /// The workspace an account-session operation rotated away, until that
  /// operation settles. Only a rollback to the account that owned it may put
  /// it back; every other outcome lets it go.
  final Map<String, ForumWorkspace> _rotatedWorkspaces = {};
  ForumWorkspace? get currentWorkspace {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _workspace.forSite(siteUrl);
  }

  ForumWorkspace? workspaceFor(String siteUrl) => _workspace.forSite(siteUrl);

  bool _desktopTopicTabs = false;
  bool get desktopTopicTabs => _desktopTopicTabs;
  set desktopTopicTabs(bool value) {
    if (_desktopTopicTabs == value) return;
    _desktopTopicTabs = value;
    if (value) _workspace.configureDesktopPanels();
  }

  /// Whether the desktop workspace currently has room for both panels.
  bool topicPanelsVisible = false;
  @override
  bool get desktopPanelsEnabled => desktopTopicTabs && forumTabsEnabled;

  bool isTabVisible(String? id) {
    if (id == null) {
      return false;
    }
    final workspace = currentWorkspace;
    if (workspace == null) return false;
    if (!desktopTopicTabs) return workspace.activeTabId == id;
    return ForumPanel.values.any(
      (panel) => workspace.selectedTabIn(panel)?.id == id,
    );
  }

  ForumTab? get listPanelTab =>
      currentWorkspace?.selectedTabIn(ForumPanel.main);

  int? get readingTopicId => focusedTabContext.readingTopicId;

  ForumTab? selectedTabIn(ForumPanel panel) =>
      currentWorkspace?.selectedTabIn(panel);

  bool get _tabContextDisposed => isDisposed;
  bool get _workspaceHasListeners => hasListeners;

  ShellTabContext tabContext(String? tabId) => ShellTabContext._(this, tabId);
  ShellTabContext get focusedTabContext => tabContext(activeTabId);

  ForumTab? get activeTab => currentWorkspace?.activeTab;
  @override
  String? get activeTabId => activeTab?.id;
  List<ForumTab> get tabsForCurrentForum => currentWorkspace?.tabs ?? const [];
  List<ForumTab> get recentlyClosedTabsForCurrentForum =>
      _workspace.recentlyClosed;

  bool get canCreateTab => _workspace.canCreateTab;

  String? get destinationId => activeTab?.rootDestinationId;

  @override
  List<ContentRoute> get contentStack => focusedTabContext.contentStack;
  @override
  ContentRoute? get currentContent => focusedTabContext.currentContent;

  String _recentAccountIdentity(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    return instance == null ? 'anonymous' : _workspaceAccountIdentity(instance);
  }

  List<ContentRoute> recentCategoriesFor(String siteUrl) => recentDestinations
      .categoriesFor(siteUrl, _recentAccountIdentity(siteUrl));

  List<DestinationBookmark> destinationBookmarksFor(String siteUrl) =>
      destinationBookmarks.entriesFor(siteUrl, _recentAccountIdentity(siteUrl));

  DestinationBookmarkAction? destinationBookmarkAction(
    ContentRoute route, {
    String? siteUrl,
  }) {
    final site = siteUrl ?? currentInstance?.url;
    final bookmark = DestinationBookmark.fromRoute(route);
    if (site == null ||
        _instanceAt(site)?.isConnected != true ||
        bookmark == null) {
      return null;
    }
    final account = _recentAccountIdentity(site);
    final lease = lifecycle.capture(site);
    final bookmarked = destinationBookmarksFor(
      site,
    ).any((entry) => entry.identity == bookmark.identity);
    bool current() =>
        !isDisposed &&
        lease.isCurrent &&
        _recentAccountIdentity(site) == account;
    return DestinationBookmarkAction(
      bookmarked: bookmarked,
      invoke: () async {
        if (!current()) {
          return BookmarkWriteResult.refused(
            appL10n.bookmarkChangedRefreshMenu,
          );
        }
        try {
          await destinationBookmarks.set(
            site,
            account,
            bookmark,
            bookmarked: !bookmarked,
            isCurrent: current,
          );
          if (!current()) {
            return BookmarkWriteResult.refused(
              appL10n.bookmarkChangedRefreshMenu,
            );
          }
          _destinationBookmarksRevision++;
          _notify();
          return const BookmarkWriteResult.saved();
        } catch (error, stack) {
          _reportOperationalError(
            error,
            stack,
            'destinationBookmarks.save',
            degraded: true,
          );
          return BookmarkWriteResult.refused(appL10n.couldNotSaveChanges);
        }
      },
    );
  }

  String? destinationBookmarkSiteForUrl(String url, {String? siteUrl}) {
    final target = Uri.tryParse(absoluteUrl(url, siteUrl: siteUrl));
    return target == null
        ? null
        : mostSpecificServingForum(
            _instances,
            target,
            siteUrl: (site) => site.url,
          )?.forum.url;
  }

  ContentRoute? destinationBookmarkRouteForUrl(
    String url, {
    String? siteUrl,
    String? title,
  }) {
    final absolute = absoluteUrl(url, siteUrl: siteUrl);
    final destination = _routeForLink(absolute, title: title);
    if (destination != null) return destination.route;
    final target = Uri.tryParse(absolute);
    final instance = target == null
        ? null
        : mostSpecificServingForum(
            _instances,
            target,
            siteUrl: (site) => site.url,
          )?.forum;
    if (instance == null) return null;
    final channel = RegExp(
      r'^/chat/c/[^/]+/([1-9][0-9]*)/?$',
    ).firstMatch(instance.pathWithin(target!) ?? '');
    return channel == null
        ? null
        : ContentRoute(
            destination: ExtensionDestination('chat-c-${channel.group(1)}'),
            title: title ?? appL10n.chat,
            icon: DIcons.comments,
          );
  }

  Future<bool> openDestinationBookmark(
    String siteUrl,
    DestinationBookmark bookmark, {
    bool newTab = false,
    ForumPanel? panel,
  }) async {
    if (currentInstance?.url != siteUrl ||
        !destinationBookmarksFor(siteUrl).contains(bookmark)) {
      return false;
    }
    return await openDestinationRoute(
          bookmark.route,
          newTab: newTab,
          panel: panel,
        ) ==
        TabOpenResult.opened;
  }

  Future<TabOpenResult> openDestinationRoute(
    ContentRoute route, {
    String? siteUrl,
    bool newTab = false,
    ForumPanel? panel,
  }) async {
    final instance = siteUrl == null ? currentInstance : _instanceAt(siteUrl);
    if (instance == null) return TabOpenResult.unsupported;
    if (newTab &&
        forumTabsEnabled &&
        (workspaceFor(instance.url)?.tabs.length ?? 0) >=
            ForumWorkspace.maximumTabs) {
      return TabOpenResult.limitReached;
    }
    final bookmark = DestinationBookmark.fromRoute(route);
    if (bookmark?.kind == DestinationBookmarkKind.chat) {
      final channel = bookmark!.identity.substring('chat:'.length);
      final opened = await openPluginUrl(
        siteLink('/chat/c/-/$channel', siteUrl: instance.url),
        origin: newTab
            ? panel == ForumPanel.main
                  ? PluginLinkOrigin.mainPanelNewTab
                  : panel == ForumPanel.secondary
                  ? PluginLinkOrigin.secondaryPanelNewTab
                  : PluginLinkOrigin.newTab
            : panel == ForumPanel.main
            ? PluginLinkOrigin.mainPanel
            : panel == ForumPanel.secondary
            ? PluginLinkOrigin.secondaryPanel
            : PluginLinkOrigin.inApp,
      );
      return opened ? TabOpenResult.opened : TabOpenResult.unsupported;
    }
    if (newTab) {
      return openContentInNewTab(
        route,
        siteUrl: instance.url,
        panel: panel,
        select: false,
      );
    }
    if (currentInstance?.url != instance.url) {
      selectInstance(_instances.indexOf(instance));
    }
    if (panel != null && desktopPanelsEnabled) {
      final target = selectedTabIn(panel);
      if (target == null) {
        return openContentInNewTab(
          route,
          siteUrl: instance.url,
          panel: panel,
          select: true,
        );
      }
      if (target.id != activeTabId) selectTab(target.id);
    }
    _workspace.preparePluginPaneForRoute(route);
    final tab = activeTab;
    if (tab == null) return TabOpenResult.unsupported;
    _workspace.replaceActiveTab(
      tab.navigate(rootDestinationId: route.id, contentStack: [route]),
    );
    _setForumContentRoot();
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    _hydrateActiveTab(instance);
    return TabOpenResult.opened;
  }

  /// Uses the loaded topic tracking snapshot and live updates, with the same
  /// category counting rules as sidebar badges.
  int categoryActivityCountFor(String siteUrl, int categoryId) {
    final user = _instanceAt(siteUrl)?.user;
    final tracking = _topicTrackingBySite[siteUrl];
    if (user == null || tracking == null || !tracking.hasSnapshot) {
      return 0;
    }
    return tracking
        .categoryBadge(
          categoryId: categoryId,
          categories: _taxonomy.categoriesFor(siteUrl),
          unifiedNew: user.unifiedNewEnabled,
          showCount: true,
        )
        .count;
  }

  List<ContentRoute> recentChannelsFor(String siteUrl) =>
      recentDestinations.channelsFor(siteUrl, _recentAccountIdentity(siteUrl));
  List<ContentRoute> recentTopicsFor(String siteUrl) =>
      recentDestinations.topicsFor(siteUrl, _recentAccountIdentity(siteUrl));

  /// Reads the shared Latest feed without starting a request. Start previews
  /// use only data already loaded by the forum's topic list.
  List<Topic> cachedLatestTopicsFor(String siteUrl) {
    final feed = topicFeeds.feedFor(siteUrl, TopicListMode.latest.routeId);
    if (feed?.loaded != true) return const [];
    return List.unmodifiable([
      for (final id in feed!.topicIds) ?store.read<Topic>(siteUrl, id),
    ]);
  }

  void _rememberCurrentContent() {
    if (!loaded) return;
    final siteUrl = currentInstance?.url;
    final route = currentContent;
    if (siteUrl == null || route == null) return;
    _rememberRoute(siteUrl, _recentAccountIdentity(siteUrl), route);
  }

  void _rememberRoute(
    String siteUrl,
    String accountIdentity,
    ContentRoute route,
  ) {
    if (recentDestinations.remember(siteUrl, accountIdentity, route)) {
      unawaited(recentDestinations.save());
    }
  }

  bool get canPopContent => focusedTabContext.canPopContent;
  bool get canForwardContent => focusedTabContext.canForwardContent;

  final _contentRefreshers = <String?, Future<void>? Function()>{};
  final _refreshingTabs = <(ShellRootMode, String?, String?, String?)>{};

  bool get refreshingCurrentTab => focusedTabContext.refreshingCurrentTab;

  bool get canRefreshCurrentTab => focusedTabContext.canRefreshCurrentTab;

  /// Returning null lets the shell use the route's standard loader.
  VoidCallback registerContentRefresher(
    Future<void>? Function() refresh, {
    String? tabId,
  }) {
    final owner = tabId ?? activeTabId;
    _contentRefreshers[owner] = refresh;
    return () {
      if (identical(_contentRefreshers[owner], refresh)) {
        _contentRefreshers.remove(owner);
      }
    };
  }

  Future<void> refreshCurrentTab() => focusedTabContext.refreshTab();

  Future<void> _refreshCurrentContent(ShellTabContext context) async {
    final route = context.currentContent;
    if (route == null) return;
    await _loadPage(
      context,
      route,
      ContentPageContract.resolve(route).refreshLoad,
      force: true,
    );
  }

  Future<void> _loadPage(
    ShellTabContext context,
    ContentRoute route,
    PageLoad? operation, {
    bool force = false,
  }) async {
    final instance = context._instance;
    if (instance == null) return;
    switch (operation) {
      case null:
        break;
      case PageLoad.feed:
        await context.loadFeed(route.id, force: force);
      case PageLoad.rootFeed:
        await context.loadFeed(
          route.feedPath == null ? context.tab!.rootDestinationId : route.id,
          force: force,
        );
      case PageLoad.pathFeed:
        if (route.feedPath != null) {
          await context.loadFeed(route.id, force: force);
        }
      case PageLoad.topic:
        final anchor = force ? null : context.tab?.anchors[route.id];
        await Future.wait([
          context.loadTopic(
            route.topicId!,
            route.slug ?? '',
            postNumber: force
                ? null
                : anchor?.kind == 'topic'
                ? anchor!.itemId
                : route.postNumber,
            force: force,
          ),
          if (context.topicListContent case final source? when force)
            context.loadFeed(source.id, force: true),
        ]);
      case PageLoad.badge:
        await badges.load(instance, route.badgeRoute!, refresh: force);
      case PageLoad.categories:
        await loadCategories(instance.url, force: force);
      case PageLoad.tags:
        await loadTags(instance.url, force: force);
      case PageLoad.users:
        await context.loadUsers(refresh: force);
      case PageLoad.drafts:
        await draftList.load(instance, refresh: force);
      case PageLoad.summary:
        await userSummary.load(instance, refresh: force);
      case PageLoad.activity:
        await accountActivity.loadUserActivity(instance, refresh: force);
      case PageLoad.bookmarks:
        await accountActivity.loadBookmarkList(instance, refresh: true);
      case PageLoad.preferences:
        await preferences.load(instance, refresh: force);
      case PageLoad.extensionRoot:
        if (plugins.registry.homepage(route.id) == null) {
          await _loadPage(context, route, PageLoad.rootFeed, force: force);
        }
      case PageLoad.extension:
        final hydrator = _pluginSession
            .capabilities<PluginRouteHydrator>()
            .where((candidate) => candidate.handlesPluginRoute(route.id))
            .firstOrNull;
        if (hydrator != null) {
          if (force) {
            await hydrator.hydratePluginRoute(
              instance.url,
              route.id,
              force: true,
            );
          } else {
            _observePluginLifecycle(
              Future.sync(
                () => hydrator.hydratePluginRoute(instance.url, route.id),
              ),
              'plugins.session.hydrateRoute',
            );
          }
        } else if (force ||
            (route.feedPath != null &&
                !route.sameDestinationAs(context.contentStack.first))) {
          await context.loadFeed(route.id, force: force);
        }
    }
  }

  MobilePane _mobilePane = MobilePane.sidebar;
  MobilePane get mobilePane => _mobilePane;

  ShellRootMode _rootMode;
  ShellRootMode get rootMode => _rootMode;

  bool _appSettingsModalOpen = false;
  bool get appSettingsModalOpen => _appSettingsModalOpen;

  @override
  Listenable get changes => this;

  @override
  bool get forumActive =>
      _rootMode == ShellRootMode.forum && !_appSettingsModalOpen;

  ({Object owner, PluginVisibleTopicContext context})? _visibleTopicContext;

  @override
  PluginVisibleTopicContext? get visibleTopicContext {
    final held = _visibleTopicContext?.context;
    if (held == null ||
        !forumActive ||
        currentInstance?.url != held.siteUrl ||
        currentContent?.topicId != held.topicId) {
      return null;
    }
    return held;
  }

  /// Publishes the narrow topic viewport snapshot exposed to plugin writes.
  ///
  /// [owner] makes teardown race-safe when one topic view replaces another:
  /// the retiring view cannot clear a newer view's snapshot.
  void updateVisibleTopicContext({
    required Object owner,
    required String siteUrl,
    required int topicId,
    required Iterable<int> postIds,
  }) {
    if (currentInstance?.url != siteUrl || currentContent?.topicId != topicId) {
      clearVisibleTopicContext(owner);
      return;
    }
    final normalizedPostIds = <int>[];
    final seen = <int>{};
    for (final postId in postIds) {
      if (postId > 0 && seen.add(postId)) normalizedPostIds.add(postId);
    }
    _visibleTopicContext = (
      owner: owner,
      context: PluginVisibleTopicContext(
        siteUrl: siteUrl,
        topicId: topicId,
        postIds: normalizedPostIds,
      ),
    );
  }

  void clearVisibleTopicContext(Object owner) {
    if (identical(_visibleTopicContext?.owner, owner)) {
      _visibleTopicContext = null;
    }
  }

  DiscourseInstance? instanceFor(String siteUrl) => _instanceAt(siteUrl);

  static String _workspaceAccountIdentity(DiscourseInstance instance) =>
      instance.user == null
      ? 'anonymous'
      : 'user:${instance.user!.username.toLowerCase()}';

  ContentRoute _homepageFor(DiscourseInstance instance) {
    final config = siteConfigFor(instance.url);
    return ContentRoute.homepage(
      config,
      connected: instance.isConnected,
      registeredHomepage: instance.isConnected
          ? plugins.registry
                .homepage(config.defaultHomepage)
                ?.homepage(config, instance.user)
          : null,
    );
  }

  Future<void>? _loadTask;

  Future<void> load() {
    if (loaded || isDisposed) return Future.value();

    final active = _loadTask;
    if (active != null) return active;

    final shouldNotify = _loadStatus != InstanceLoadStatus.loading;
    if (shouldNotify) {
      _loadStatus = InstanceLoadStatus.loading;
    }

    late final Future<void> task;
    task = _load().whenComplete(() {
      if (identical(_loadTask, task)) _loadTask = null;
    });
    _loadTask = task;
    if (shouldNotify) _notify();
    return task;
  }

  Future<void> _load() async {
    unawaited(cooking.start());
    final settingsLoad = appSettings.load();
    final storedWorkspaces = forumTabs.load();
    final recentDestinationsLoad = recentDestinations.load();
    final destinationBookmarksLoad = destinationBookmarks.load().catchError(
      (Object error, StackTrace stack) => _reportOperationalError(
        error,
        stack,
        'destinationBookmarks.load',
        degraded: true,
      ),
    );
    final List<DiscourseInstance> stored;
    try {
      stored = await instanceStore.load();
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'instances.load',
        degraded: false,
      );
      if (!isDisposed) {
        _loadStatus = InstanceLoadStatus.failed;
        _notify();
      }
      await settingsLoad;
      return;
    }

    await settingsLoad;
    await recentDestinationsLoad;
    await destinationBookmarksLoad;
    if (isDisposed) return;
    _instances
      ..clear()
      ..addAll(stored);
    for (final instance in stored) {
      _taxonomy.bind(instance.url);
      var totals = instance.notificationTotals;
      final storedGroupedCounts = instance.user?.groupedUnreadNotifications;
      if (totals?.groupedUnreadNotifications.isAvailable != true &&
          storedGroupedCounts?.isAvailable == true) {
        // Older snapshots kept grouped counts only on the current user. Seed
        // AccountActivity before local read/dismiss writes so their zero is an
        // available authoritative value, rather than falling back to stale
        // user counts in plugin menu contexts.
        totals = (totals ?? const NotificationTotals())
            .withGroupedUnreadNotifications(storedGroupedCounts!);
      }
      if (totals != null) {
        accountActivity.restoreTotals(instance.url, totals);
      }
      doNotDisturb.restoreSnapshot(
        instance.url,
        instance.user?.doNotDisturbUntil,
      );
    }
    await Future.wait([
      forumSettings.load(ForumSettingsController.homeSite),
      for (final instance in stored)
        forumSettings.load(instance.url, initialMode: appSettings.themeMode),
      forumSettings.loadShared([for (final instance in stored) instance.url]),
      for (final instance in stored) topicSidebar.ensure(siteUrl: instance.url),
      // Only forums on the rail keep their preferences: a removal may have
      // ended before they were dropped, and older builds kept them.
      _forgetStoredPreferences(),
    ]);
    if (isDisposed) return;
    _durableInstanceOrder = [for (final instance in stored) instance.url];
    final workspaces = await storedWorkspaces;
    if (isDisposed) return;
    final selectedIndex = _instances.indexWhere(
      (instance) => instance.url == forumTabs.selectedSiteUrl,
    );
    _instanceIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final workspacesNormalized = _workspace.restore(workspaces);
    // Only forums on the rail keep Start page visits: a removal may have ended
    // before its visits were saved away, and older builds kept them. An empty
    // rail may be a list that could not be decoded, so it must not erase every
    // forum's visits.
    var recentDestinationsChanged =
        stored.isNotEmpty &&
        recentDestinations.retainSites({
          for (final instance in stored) instance.url,
        });
    // Existing installations have tab history but no separate Start page
    // visits yet. Seed it once so those visits appear after the upgrade.
    for (final workspace in _workspace.values) {
      if (recentDestinations.hasVisits(
        workspace.siteUrl,
        workspace.accountIdentity,
      )) {
        continue;
      }
      for (final tab in workspace.tabs) {
        for (final location in tab.backHistory) {
          recentDestinationsChanged |= recentDestinations.remember(
            workspace.siteUrl,
            workspace.accountIdentity,
            location.contentStack.last,
          );
        }
        recentDestinationsChanged |= recentDestinations.remember(
          workspace.siteUrl,
          workspace.accountIdentity,
          tab.currentContent,
        );
      }
    }
    if (recentDestinationsChanged) unawaited(recentDestinations.save());
    if (workspacesNormalized) _workspace.persist();
    final initialInstance = currentInstance;
    // A persisted palette is already good enough for the first frame. Its
    // expensive stylesheet refresh follows the selected account's small JSON
    // reads instead of competing with the feed during the cold-start burst.
    _restoreInstanceWorkspace(
      refreshAppearance: initialInstance?.appearance == null,
    );
    _loadStatus = InstanceLoadStatus.ready;
    _notify();

    unawaited(updates.load());

    // Refresh only the selected account; persisted metadata can draw inactive
    // sites until their first selection.
    unawaited(_refreshAccountState(initialInstance));
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  Future<bool> addInstance(DiscourseInstance instance) async {
    await load();
    if (isDisposed || !loaded) return false;
    if (contains(instance.url)) return true;

    await forumSettings.load(instance.url);
    if (isDisposed) return false;
    if (contains(instance.url)) return true;

    final previousSiteUrl = currentInstance?.url;
    final previousPane = _mobilePane;
    final previousRootMode = _rootMode;

    _instances.add(instance);
    _taxonomy.bind(instance.url);
    _rootMode = ShellRootMode.forum;
    _instanceIndex = _instances.length - 1;
    // The lookup that described this forum has just read its basic info.
    _basicInfoRefreshes.add(instance.url);
    _resetToInstanceDefault();
    _mobilePane = MobilePane.sidebar;
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
      return true;
    } catch (_) {
      if (isDisposed) return false;

      // A failed first save must not leave an in-memory-only site that the add
      // sheet can neither persist nor retry because it now looks duplicated.
      // Only undo the exact object added here; if it was replaced meanwhile,
      // a newer operation owns its state and gets one repair save instead.
      final held = _instanceAt(instance.url);
      if (!identical(held, instance)) {
        try {
          await instanceStore.save(List.of(_instances));
          return true;
        } catch (_) {
          return false;
        }
      }

      final selectedSiteUrl = currentInstance?.url;
      _forgetSiteState(instance.url);
      _instances.remove(instance);
      _rootMode = previousRootMode;

      if (selectedSiteUrl == instance.url) {
        final previousIndex = previousSiteUrl == null
            ? -1
            : _instances.indexWhere((item) => item.url == previousSiteUrl);
        if (previousIndex >= 0) {
          _instanceIndex = previousIndex;
          _restoreInstanceWorkspace();
          _mobilePane = previousPane;
        } else {
          _instanceIndex = _instances.isEmpty ? 0 : _instances.length - 1;
          _restoreInstanceWorkspace();
        }
      } else {
        final selectedIndex = selectedSiteUrl == null
            ? -1
            : _instances.indexWhere((item) => item.url == selectedSiteUrl);
        _instanceIndex = selectedIndex >= 0 ? selectedIndex : 0;
      }
      _notify();

      // A newer save may have been queued while the failed write was active.
      // Make this rollback the newest snapshot before reporting the failure.
      try {
        await instanceStore.save(List.of(_instances));
      } catch (_) {}
      return false;
    }
  }

  Future<bool> moveInstance(DiscourseInstance instance, int newIndex) {
    if (isDisposed || !loaded || _instances.length < 2) {
      return Future.value(false);
    }

    final oldIndex = _instances.indexWhere((item) => item.url == instance.url);
    if (oldIndex < 0) return Future.value(false);
    final destination = newIndex.clamp(0, _instances.length - 1);
    if (oldIndex == destination) return Future.value(true);

    // When no reorder is outstanding, the live membership/order came from a
    // completed load, add or removal and is the rollback boundary for this
    // batch of drags.
    if (!_savingInstanceOrder && _pendingInstanceReorders.isEmpty) {
      _durableInstanceOrder = [for (final item in _instances) item.url];
    }
    final revision = ++_instanceReorderRevision;

    final selectedSiteUrl = currentInstance?.url;
    final moved = _instances.removeAt(oldIndex);
    _instances.insert(destination, moved);
    _followSelectedInstance(selectedSiteUrl);
    _notify();

    final result = Completer<bool>();
    _pendingInstanceReorders.add((revision: revision, result: result));
    if (!_savingInstanceOrder) {
      _savingInstanceOrder = true;
      unawaited(_drainInstanceOrderSaves());
    }
    return result.future;
  }

  Future<void> _drainInstanceOrderSaves() async {
    try {
      while (_pendingInstanceReorders.isNotEmpty) {
        final savedRevision = _instanceReorderRevision;
        final snapshot = List.of(_instances);
        final savedOrder = [for (final item in snapshot) item.url];

        try {
          await instanceStore.save(snapshot);
        } catch (_) {
          if (isDisposed) {
            _completeInstanceReordersThrough(savedRevision, false);
            continue;
          }

          // A drag landed behind the write that failed. Its newest snapshot
          // still contains the whole intended ordering, so let the next loop
          // persist it rather than allowing the older failure to roll it back.
          if (savedRevision != _instanceReorderRevision) continue;

          final restored = _restoreDurableInstanceOrder();
          _completeInstanceReordersThrough(savedRevision, false);

          // Put the rollback (or, if membership changed concurrently, the
          // untouched newest rail) behind the failed snapshot before accepting
          // another batch. New drags can still update the live list while this
          // repair is in flight; the next loop persists them afterward.
          final repairSnapshot = List.of(_instances);
          final repairOrder = [for (final item in repairSnapshot) item.url];
          var repairPersisted = false;
          try {
            await instanceStore.save(repairSnapshot);
            repairPersisted = true;
          } catch (_) {}
          if (restored && repairPersisted) {
            _durableInstanceOrder = repairOrder;
          }
          continue;
        }

        _durableInstanceOrder = savedOrder;
        _completeInstanceReordersThrough(savedRevision, true);
      }
    } finally {
      _savingInstanceOrder = false;
      if (_pendingInstanceReorders.isNotEmpty) {
        _savingInstanceOrder = true;
        unawaited(_drainInstanceOrderSaves());
      }
    }
  }

  void _completeInstanceReordersThrough(int revision, bool persisted) {
    final completed = _pendingInstanceReorders
        .where((request) => request.revision <= revision)
        .toList();
    _pendingInstanceReorders.removeWhere(
      (request) => request.revision <= revision,
    );
    for (final request in completed) {
      if (!request.result.isCompleted) request.result.complete(persisted);
    }
  }

  void _followSelectedInstance(String? selectedSiteUrl) {
    if (selectedSiteUrl == null) {
      _instanceIndex = _instances.isEmpty ? 0 : _instanceIndex;
      return;
    }
    final selectedIndex = _instances.indexWhere(
      (item) => item.url == selectedSiteUrl,
    );
    if (selectedIndex >= 0) _instanceIndex = selectedIndex;
  }

  bool _restoreDurableInstanceOrder() {
    if (_instances.length != _durableInstanceOrder.length) return false;
    final byUrl = {for (final instance in _instances) instance.url: instance};
    if (byUrl.length != _durableInstanceOrder.length ||
        _durableInstanceOrder.any((url) => !byUrl.containsKey(url))) {
      return false;
    }

    final selectedSiteUrl = currentInstance?.url;
    _instances
      ..clear()
      ..addAll(_durableInstanceOrder.map((url) => byUrl[url]!));
    _followSelectedInstance(selectedSiteUrl);
    _notify();
    return true;
  }

  Future<bool> removeInstance(DiscourseInstance instance) async {
    if (!_instances.contains(instance)) return false;

    // Try revoking the old key and its native push registration, but an
    // unreachable forum must not prevent the user from removing it locally.
    final disconnected = await _accountSessions.disconnect(
      instance.url,
      waitForRemoteRevocation: false,
    );
    final lease = disconnected.lease;
    if (isDisposed ||
        disconnected.outcome != AccountDisconnectionOutcome.disconnected ||
        lease == null ||
        !lease.isCurrent) {
      return false;
    }

    // Presentation metadata may have replaced the immutable instance object
    // while disconnection was in flight. URL is the rail identity; resolve the
    // object owned by the new lifecycle generation before mutating the list.
    final held = _instanceAt(instance.url);
    if (held == null) return false;
    final index = _instances.indexOf(held);
    if (index < 0) return false;
    final selected = currentInstance;
    final removingSelected = selected?.url == held.url;
    final signedOut = held.copyWith(
      clearUser: true,
      clearConfig: true,
      clearAppearance: true,
    );
    _instances.removeAt(index);
    if (_instances.isEmpty) _rootMode = ShellRootMode.forum;
    _instanceIndex = removingSelected
        ? (_instances.isEmpty ? 0 : index.clamp(0, _instances.length - 1))
        : _instances.indexOf(selected!);

    // The final disconnected phase re-activates a selected public forum under
    // the lease it returns, and a selector may have read the signed-out state
    // of any removed forum since. Retire that lifecycle so those loads cannot
    // commit into a forum that has left the rail, and drop what they cached.
    // The index must already be valid: forgetting notifies listeners.
    _forgetSiteState(held.url);
    // Only a rollback that no later operation on this URL has overtaken may
    // put the forum back.
    final removal = lifecycle.capture(held.url);
    if (removingSelected) _restoreInstanceWorkspace();
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
      // Start page visits name private messages and direct chats, and stored
      // preferences name the forum, its usernames and what was used there, so
      // both leave with the forum for every account. Only a durable removal
      // drops them: a rollback restores the forum with them, and a re-add that
      // landed during the save owns the URL's again.
      if (_instanceAt(held.url) == null) {
        unawaited(
          destinationBookmarks
              .forgetSite(held.url)
              .catchError(
                (Object error, StackTrace stack) => _reportOperationalError(
                  error,
                  stack,
                  'destinationBookmarks.forgetSite',
                  degraded: true,
                ),
              ),
        );
        if (recentDestinations.forgetSite(held.url)) {
          unawaited(recentDestinations.save());
        }
        unawaited(_forgetStoredPreferences(removed: held.url));
      }
      return true;
    } catch (_) {
      if (isDisposed ||
          !removal.isCurrent ||
          _instanceAt(instance.url) != null) {
        return false;
      }

      final restoredIndex = index.clamp(0, _instances.length);
      _instances.insert(restoredIndex, signedOut);
      _taxonomy.bind(signedOut.url);
      if (removingSelected) {
        _instanceIndex = restoredIndex;
        _mobilePane = MobilePane.sidebar;
        _resetToInstanceDefault();
      } else {
        final selectedIndex = selected == null
            ? -1
            : _instances.indexWhere((item) => item.url == selected.url);
        _instanceIndex = selectedIndex >= 0 ? selectedIndex : 0;
      }
      _notify();

      // The failed write may have raced a newer queued snapshot. Make the
      // signed-out rollback the latest value before handing control back.
      try {
        await instanceStore.save(List.of(_instances));
      } catch (_) {}
      return false;
    }
  }

  /// Drops the preferences kept on this device for forums that left the rail
  /// for good: [removed] once its removal is saved, or else every forum off
  /// the rail. What the stores read of them goes in the same turn as what is
  /// stored, so neither brings the other back.
  Future<void> _forgetStoredPreferences({String? removed}) =>
      forgetSitePreferences(
        [...declaredSitePreferenceKeys, ...plugins.registry.sitePreferenceKeys],
        () {
          // The app home keeps an appearance of its own, like a forum.
          final keeping = [
            ForumSettingsController.homeSite,
            for (final instance in _instances) instance.url,
          ];
          final ForgottenSites sites;
          if (removed == null) {
            // An empty rail may be a list that could not be decoded, so it
            // must not erase every forum's preferences.
            if (_instances.isEmpty) return null;
            sites = ForgottenSites.except(keeping);
          } else {
            // A re-add that landed while storage opened owns the URL again.
            if (_instanceAt(removed) != null) return null;
            sites = ForgottenSites.removed(removed, keeping: keeping);
          }
          return sites;
        },
      );

  NotificationTotals? totalsFor(DiscourseInstance instance) =>
      accountActivity.totalsFor(instance.url);

  @override
  NotificationTotals? get currentTotals {
    final instance = currentInstance;
    return instance == null ? null : accountActivity.totalsFor(instance.url);
  }

  @override
  Rect? get readerContentBounds => _readerContentBounds.value;

  @override
  ValueListenable<Rect?> get readerContentBoundsListenable =>
      _readerContentBounds;

  int railBadgeFor(DiscourseInstance instance) =>
      accountActivity.totalsFor(instance.url)?.badge ?? 0;

  SidebarBadge sidebarBadgeFor(String destinationId) {
    if (destinationId == 'drafts') {
      return SidebarBadge.count(draftCountFor(currentInstance?.url));
    }
    final totals = currentTotals;
    if (destinationId == 'latest') {
      final count = currentInstance?.user?.unifiedNewEnabled == true
          ? newActivityCount
          : totals?.topicTrackingSidebarCount ?? 0;
      return SidebarBadge.count(count);
    }
    if (destinationId == 'messages') {
      return SidebarBadge.count(totals?.unreadPersonalMessages ?? 0);
    }

    final instance = currentInstance;
    final user = instance?.user;
    final tracking = instance == null
        ? null
        : _topicTrackingBySite[instance.url];
    // A live message can seed a site's tracking state before its snapshot
    // has landed, or after that load failed. Counting from that state would
    // show whichever topics happened to arrive on the bus as the whole
    // category, so until the snapshot is in, there is no badge — the same
    // rule topicListNewCounts applies before it trusts the state.
    if (instance == null ||
        user == null ||
        tracking == null ||
        !tracking.hasSnapshot) {
      return SidebarBadge.none;
    }
    final showCount = user.sidebarShowCountOfNewItems;
    final unifiedNew = user.unifiedNewEnabled;

    if (_destinationNumericId(destinationId, 'category-') case final id?) {
      return tracking.categoryBadge(
        categoryId: id,
        categories: _taxonomy.categoriesFor(instance.url),
        unifiedNew: unifiedNew,
        showCount: showCount,
      );
    }
    if (_destinationNumericId(destinationId, 'tag-') case final id?) {
      if (_taxonomy.isPrivateSidebarTag(instance.url, id)) {
        return SidebarBadge.none;
      }
      return tracking.tagBadge(
        tagId: id,
        unifiedNew: unifiedNew,
        showCount: showCount,
      );
    }
    return SidebarBadge.none;
  }

  int topicTrackingRevisionFor(String siteUrl) =>
      _topicTrackingBySite[siteUrl]?.revision ?? 0;

  int draftCountFor(String? siteUrl) {
    if (siteUrl == null) return 0;
    final feed = draftList.feedFor(siteUrl);
    if (feed.totalCount case final count?) return count;
    return _instanceAt(siteUrl)?.user?.draftCount ?? 0;
  }

  void _recordDraftDestroyed(
    String siteUrl,
    String draftKey, {
    required bool knownToExist,
  }) {
    final wasListed = draftList
        .feedFor(siteUrl)
        .drafts
        .any((draft) => draft.key == draftKey);
    draftList.recordDeleted(siteUrl, draftKey);
    if (!knownToExist || wasListed) return;
    final instance = _instanceAt(siteUrl);
    if (instance?.isConnected == true) {
      // A cached count may predate a newly-created draft, so subtracting can
      // under-count. Refresh the authoritative account count instead.
      draftList.invalidateTotalCount(siteUrl);
      unawaited(_refreshSessionUserFor(instance!, force: true));
    }
  }

  Future<void> _refreshOne(DiscourseInstance instance) async {
    await accountActivity.refresh(instance);
  }

  Future<void> _refreshAccountState(DiscourseInstance? initialInstance) async {
    if (initialInstance case final instance? when instance.isConnected) {
      // The tracker installs the root document's snapshot before opening its
      // matching MessageBus cursors. Let later JSON refreshes run second so a
      // slow HTML response cannot overwrite a newer totals response.
      await _trackerStartRequests[instance.url];
      if (isDisposed || !contains(instance.url)) return;
      await Future.wait([
        _refreshOne(instance),
        _refreshSessionUserFor(instance),
      ]);
      if (isDisposed || !contains(instance.url)) return;
      await _presentation.ensureAppearance(instance.url);
    } else if (initialInstance case final instance?
        when !instance.loginRequired) {
      if (isDisposed || !contains(instance.url)) return;
      // Anonymous appearance is public and may have been populated by lookup
      // moments ago. Refresh it normally; the warm-start suppression is for a
      // persisted connected account whose many authenticated appearance reads
      // otherwise join the cold-start burst.
      await _presentation.refreshAppearance(instance.url);
    }
  }

  /// Forums whose basic info this launch has asked for. The rail stores a
  /// forum's name, icon and `login_required` as they were when it was added,
  /// and any of them can change since; each forum reads them again once, on
  /// its first activation, so inactive forums add nothing to a cold start.
  /// Forgetting a forum's state re-arms it: the lifecycle rotation that comes
  /// with that discards a read still in flight.
  final Set<String> _basicInfoRefreshes = {};

  void _refreshBasicInfoOnce(String siteUrl) {
    if (!_basicInfoRefreshes.add(siteUrl)) return;
    unawaited(_refreshBasicInfo(siteUrl));
  }

  Future<void> _refreshBasicInfo(String siteUrl) async {
    final lease = lifecycle.capture(siteUrl);
    final SiteBasicInfo info;
    try {
      info = await RequestIntent.background().run(
        () => api.siteLookup.basicInfo(siteUrl),
      );
    } catch (_) {
      // What was stored still draws the forum; the next launch asks again.
      return;
    }
    if (isDisposed || !lease.isCurrent) return;
    final held = _instanceAt(siteUrl);
    if (held == null) return;
    final refreshed = held.withBasicInfo(info);
    if (identical(refreshed, held)) return;

    _replaceInstance(held, refreshed);
    // Whether a signed-out reader may read this forum just changed. Activating
    // it again puts the sign-in boundary up, or takes it down and hydrates
    // what it had hidden.
    if (currentInstance?.url == siteUrl &&
        !refreshed.isConnected &&
        refreshed.loginRequired != held.loginRequired) {
      _restoreInstanceWorkspace();
    }
    _notify();
    instanceStore.save(List.of(_instances)).ignore();
  }

  Future<void> _refreshSessionUserFor(
    DiscourseInstance instance, {
    bool force = false,
  }) async {
    final lease = lifecycle.capture(instance.url);
    try {
      final credential = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final apiKey = credential.apiKey;
      if (apiKey == null) {
        await _expireMissingAccount(instance.url, lease);
        return;
      }
      await _sessionUser(instance.url, apiKey, lease: lease, force: force);
      if (!lease.isCurrent || currentInstance?.url != instance.url) return;
      await _customSidebar.ensure(instance.url, account: lease);
    } catch (_) {
      // Freshness-sensitive plugin capabilities remain unknown. Persisted
      // extension state must not authorize them in their place. A key that
      // could not be read is not a missing key, so the account stays.
    }
  }

  late final CustomSidebarSections _customSidebar = CustomSidebarSections(
    api: api.site,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceFor: _instanceAt,
    selectedSite: () => currentInstance?.url,
    onChanged: _notify,
    reportFailure: (error, stackTrace) => _reportOperationalError(
      error,
      stackTrace,
      'sidebar.loadCustomSections',
      severity: DiagnosticSeverity.warning,
    ),
    clock: _clock,
  );

  List<SidebarSection> customSidebarSectionsFor(String siteUrl) =>
      _customSidebar.customFor(siteUrl);

  bool canEditSidebarLinks(String siteUrl, SidebarSection section) =>
      _customSidebar.canEdit(siteUrl, section);

  /// [newIndex] is an insertion gap in the original list, as in Flutter's
  /// reorder callback and Core's sidebar drop handling.
  Future<void> reorderSidebarLinks({
    required String siteUrl,
    required SidebarSection section,
    required int oldIndex,
    required int newIndex,
  }) => _customSidebar.reorder(
    siteUrl: siteUrl,
    section: section,
    oldIndex: oldIndex,
    newIndex: newIndex,
  );

  bool canMoveSidebarLink({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) => _customSidebar.canMove(
    siteUrl: siteUrl,
    source: source,
    target: target,
    oldIndex: oldIndex,
    newIndex: newIndex,
  );

  Future<void> moveSidebarLink({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) => _customSidebar.move(
    siteUrl: siteUrl,
    source: source,
    target: target,
    oldIndex: oldIndex,
    newIndex: newIndex,
  );

  List<SidebarSection> sidebarSectionsFor(DiscourseInstance instance) =>
      _customSidebar.sectionsFor(instance);

  void _onTotalsLoaded(DiscourseInstance instance, NotificationTotals totals) {
    _notifyPluginTotals(instance, totals);
  }

  void _onTotalsChanged(String siteUrl, NotificationTotals totals) {
    if (isDisposed) return;
    final instance = _instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) return;
    if (instance.notificationTotals == totals) return;
    _replaceInstance(instance, instance.copyWith(notificationTotals: totals));
    instanceStore.save(List.of(_instances)).ignore();
  }

  void _onGroupedUnreadAuthorityAdvanced(String siteUrl) {
    _currentUserReconcilerFor(siteUrl).groupedUnreadChanged();
  }

  void _onPreferencesSaved(
    String siteUrl,
    PreferenceSection section,
    UserPreferences preferences,
  ) {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user == null ||
        user.username.toLowerCase() != preferences.username.toLowerCase()) {
      return;
    }
    var updated = switch (section) {
      PreferenceSection.notifications => user.withPreferences(
        likesNotificationsDisabled: preferences.likeNotificationFrequency == 3,
      ),
      PreferenceSection.profile => user.withPreferences(
        timezone: preferences.timezone,
      ),
      PreferenceSection.interface => user.withPreferences(
        bookmarkAutoDeletePreference: preferences.bookmarkAutoDeletePreference,
      ),
      _ => user,
    };
    for (final mirror
        in _pluginSession.capabilities<PluginUserPreferenceMirror>()) {
      try {
        updated = mirror.mirrorUserPreference(updated, section, preferences);
      } catch (error, stackTrace) {
        _reportOperationalError(
          error,
          stackTrace,
          'preferences.pluginMirror',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
    if (updated == user) return;
    _replaceInstance(instance, instance.copyWith(user: updated));
    _notify();
    unawaited(_persistPreferencesMirror(List.of(_instances)));
  }

  Future<void> _persistPreferencesMirror(
    List<DiscourseInstance> instances,
  ) async {
    try {
      await instanceStore.save(instances);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'preferences.persistMirror',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  void _notifyPluginTotals(
    DiscourseInstance instance, [
    NotificationTotals? loadedTotals,
  ]) {
    final totals = loadedTotals ?? accountActivity.totalsFor(instance.url);
    if (totals == null) return;
    for (final observer
        in _pluginSession.capabilities<PluginTotalsObserver>()) {
      _observePluginLifecycle(
        Future.sync(
          () => observer.pluginTotalsLoaded(
            instance.url,
            totals,
            selected: currentInstance?.url == instance.url,
          ),
        ),
        'plugins.session.totalsLoaded',
      );
    }
  }

  NotificationFeed notificationsFor(String siteUrl) =>
      accountActivity.notificationsFor(siteUrl);

  Future<void> loadNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadNotifications(instance);
  }

  Future<void> markAllNotificationsRead(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) return;
    final lease = lifecycle.capture(siteUrl);
    final credential = await AccountRequestSession(
      siteUrl,
      lease,
    ).keyCredentials(credentials);
    if (!lease.isCurrent || credential.apiKey == null) return;
    final types = await _siteNotificationTypesFor(
      instance,
      credential.apiKey!,
      lease: lease,
      requestCredentials: credential,
    );
    if (!lease.isCurrent) return;
    await accountActivity.markAllNotificationsRead(instance, types);
  }

  NotificationFeed replyNotificationsFor(String siteUrl) =>
      accountActivity.replyNotificationsFor(siteUrl);

  Future<void> loadReplyNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadReplyNotifications(instance);
    }
  }

  NotificationFeed likeNotificationsFor(String siteUrl) =>
      accountActivity.likeNotificationsFor(siteUrl);

  Future<void> loadLikeNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadLikeNotifications(instance);
    }
  }

  static PluginNotificationFeedId _messageNotificationFeedId(String siteUrl) =>
      PluginNotificationFeedId(
        owner: const PluginId('core'),
        name: 'message-notifications:$siteUrl',
      );

  Listenable messageNotificationsListenable(String siteUrl) => accountActivity
      .pluginNotificationsListenable(_messageNotificationFeedId(siteUrl));

  NotificationFeed messageNotificationsFor(String siteUrl) => accountActivity
      .pluginNotificationsFor(_messageNotificationFeedId(siteUrl), siteUrl);

  Future<void> loadMessageNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null) return;
    // Core uses the same session-owned typed cache as contributed feeds.
    await accountActivity.loadPluginNotifications(
      instance,
      PluginNotificationFeedSource(
        id: _messageNotificationFeedId(siteUrl),
        filterByTypes: const [
          NotificationTypeName('private_message'),
          NotificationTypeName('group_message_summary'),
        ],
        reconnectMessage: appL10n.reconnectToToSeeNotifications(instance.host),
        failureMessage: appL10n.couldnTLoadNotificationsFrom(instance.host),
        emptyMessage: appL10n.nothingNew,
      ),
    );
  }

  int likeNotificationUnreadCount(String siteUrl) =>
      _groupedUnreadCountOf(siteUrl, plugins.registry.likeNotificationTypes);

  /// The menu counts unread rows even after opening the bell marks them seen.
  int allNotificationUnreadCount(String siteUrl) =>
      _groupedUnreadNotificationCountsFor(siteUrl)?.totalExcluding(const []) ??
      accountActivity.totalsFor(siteUrl)?.coreBadge ??
      0;

  // The Replies, Messages and Bookmarks tabs count unread notifications of
  // their own types, as Discourse's menu does. The seen-scoped
  // `new_personal_messages_notifications_count` is not a Messages count: the
  // Notifications tab's non-silent fetch bumps the seen marker, and core then
  // publishes it as zero while those notifications are still unread.
  int replyNotificationUnreadCount(String siteUrl) =>
      _groupedUnreadCountOf(siteUrl, userMenuReplyNotificationTypes);

  int messageNotificationUnreadCount(String siteUrl) {
    final counts = _groupedUnreadNotificationCountsFor(siteUrl);
    return counts?.count(CoreNotificationTypes.privateMessage) ?? 0;
  }

  int bookmarkReminderUnreadCount(String siteUrl) {
    final counts = _groupedUnreadNotificationCountsFor(siteUrl);
    return counts?.count(CoreNotificationTypes.bookmarkReminder) ?? 0;
  }

  int _groupedUnreadCountOf(
    String siteUrl,
    Iterable<NotificationTypeName> types,
  ) {
    final counts = _groupedUnreadNotificationCountsFor(siteUrl);
    if (counts == null) return 0;
    final names = types.toSet();
    return _registeredNotificationTypes
        .where((type) => names.contains(NotificationTypeName(type.wireName)))
        .fold(0, (total, type) => total + counts.count(type));
  }

  NotificationFeed otherNotificationsFor(String siteUrl) =>
      accountActivity.otherNotificationsFor(siteUrl);

  Future<void> loadOtherNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadOtherNotifications(
        instance,
        (apiKey) => _otherNotificationTypesFor(instance, apiKey),
      );
    }
  }

  int otherNotificationUnreadCount(
    String siteUrl, {
    List<PluginUserMenuSection>? pluginSections,
  }) {
    final instance = _instanceAt(siteUrl);
    final counts = _groupedUnreadNotificationCountsFor(siteUrl);
    if (counts == null) return 0;

    final claimedNames = _claimedUserMenuNotificationTypes(
      pluginSections ?? _pluginUserMenuSectionsFor(instance),
    );
    final claimedIds = <NotificationTypeId>{
      for (final definition in _registeredNotificationTypes)
        if (claimedNames.contains(NotificationTypeName(definition.wireName)))
          NotificationTypeId(definition.wireId),
    };
    return counts.totalExcluding(claimedIds);
  }

  NotificationTypeCounts? _groupedUnreadNotificationCountsFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    final live = accountActivity.totalsFor(siteUrl)?.groupedUnreadNotifications;
    final counts = live?.isAvailable == true
        ? live!
        : instance?.user?.groupedUnreadNotifications;
    return counts?.isAvailable == true ? counts : null;
  }

  Iterable<NotificationWireType> get _registeredNotificationTypes sync* {
    yield* CoreNotificationTypes.values;
    for (final type in plugins.registry.notificationTypes) {
      yield type.wireType;
    }
  }

  final Map<String, List<NotificationWireType>> _siteNotificationTypes = {};
  final Map<String, Future<List<NotificationWireType>>>
  _siteNotificationTypeRequests = {};

  Set<NotificationTypeName> _claimedUserMenuNotificationTypes(
    Iterable<PluginUserMenuSection> pluginSections,
  ) => {
    ...userMenuDedicatedNotificationTypes,
    ...plugins.registry.likeNotificationTypes,
    for (final section in pluginSections) ...section.notificationTypes,
  };

  List<PluginUserMenuSection> _pluginUserMenuSectionsFor(
    DiscourseInstance? instance,
  ) {
    final user = instance?.user;
    if (instance == null || user == null) return const [];
    return plugins.registry.userMenuSections(
      PluginUserMenuContext(
        siteUrl: instance.url,
        user: user,
        totals: accountActivity.totalsFor(instance.url),
      ),
    );
  }

  Future<List<NotificationTypeName>> _otherNotificationTypesFor(
    DiscourseInstance instance,
    String apiKey,
  ) async {
    final siteTypes = await _siteNotificationTypesFor(instance, apiKey);
    final claimed = _claimedUserMenuNotificationTypes(
      _pluginUserMenuSectionsFor(instance),
    );
    return List.unmodifiable([
      for (final type in siteTypes)
        if (!claimed.contains(NotificationTypeName(type.wireName)))
          NotificationTypeName(type.wireName),
    ]);
  }

  Future<List<NotificationWireType>> _siteNotificationTypesFor(
    DiscourseInstance instance,
    String apiKey, {
    SiteLease? lease,
    AccountRequestCredentials? requestCredentials,
  }) {
    final cached = _siteNotificationTypes[instance.url];
    if (cached != null) return Future.value(cached);
    final active = _siteNotificationTypeRequests[instance.url];
    if (active != null) return active;

    final requestLease = lease ?? lifecycle.capture(instance.url);
    final credentialFuture = requestCredentials == null
        ? AccountRequestSession(
            instance.url,
            requestLease,
          ).keyCredentials(credentials)
        : Future<AccountRequestCredentials>.value(requestCredentials);
    late final Future<List<NotificationWireType>> request;
    request = credentialFuture
        .then(
          (credential) => credential.run(
            () => api.site.siteNotificationTypes(
              siteUrl: instance.url,
              apiKey: credential.apiKey!,
            ),
          ),
        )
        .then((types) {
          final immutable = List<NotificationWireType>.unmodifiable(types);
          requestLease.commit(
            () => _siteNotificationTypes[instance.url] = immutable,
          );
          return immutable;
        })
        .whenComplete(() {
          if (identical(_siteNotificationTypeRequests[instance.url], request)) {
            final _ = _siteNotificationTypeRequests.remove(instance.url);
          }
        });
    _siteNotificationTypeRequests[instance.url] = request;
    return request;
  }

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) =>
      accountActivity.pluginNotificationsListenable(id);

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => accountActivity.pluginNotificationsFor(id, siteUrl);

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = plugins.registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadPluginNotifications(instance, registered!);
    }
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = plugins.registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    if (registered!.dismissal == null) {
      throw StateError(
        'Notification feed ${source.id.id} does not support dismissal.',
      );
    }
    final instance = _instanceAt(siteUrl);
    if (instance == null) {
      throw StateError('No forum is registered for $siteUrl.');
    }
    await accountActivity.dismissPluginNotifications(instance, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => readNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      siteLink(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      openNotificationUrl(url);

  void readNotification(String siteUrl, DiscourseNotification notification) {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      accountActivity.readNotification(instance, notification);
    }
  }

  BookmarkFeed bookmarksFor(String siteUrl) =>
      accountActivity.bookmarksFor(siteUrl);

  Future<void> loadBookmarks(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadBookmarks(instance);
  }

  Future<void> loadBookmarkList(
    String siteUrl, {
    bool refresh = false,
    bool loadMore = false,
  }) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadBookmarkList(
        instance,
        refresh: refresh,
        loadMore: loadMore,
      );
    }
  }

  Future<void> loadUserActivity(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadUserActivity(instance);
  }

  final Map<String, TopicTrackingReconciler> _topicTrackingBySite = {};
  final Map<
    String,
    ({
      SiteLease lease,
      TopicTrackingReconciler tracking,
      Future<void> Function(TopicTrackingSnapshot) load,
    })
  >
  _topicTrackingRetries = {};
  bool _liveChangeNotifyPending = false;

  TopicTrackingReconciler _trackingFor(String siteUrl) =>
      _topicTrackingBySite.putIfAbsent(siteUrl, () {
        final lease = lifecycle.capture(siteUrl);
        return TopicTrackingReconciler(
          isCurrent: () => !isDisposed && lease.isCurrent,
          clock: _clock,
        );
      });
  final Map<String, TopicComposerCapabilities> _topicComposerCapabilities = {};
  final Map<String, SitePostActionCatalog> _postActionCatalogs = {};

  List<PostFlagType> postFlagTypesFor(String siteUrl) =>
      _postActionCatalogs[siteUrl]?.postFlags ?? const [];

  List<PostFlagType> availablePostFlagTypes(String siteUrl, Post post) {
    if (post.hidden || post.isDeleted || post.actedFlagSummaries.isNotEmpty) {
      return const [];
    }
    final available = [
      for (final type in postFlagTypesFor(siteUrl))
        if (type.enabled && type.appliesToPost && post.canFlagWith(type.id))
          type,
    ];
    final notifyUser = available.indexWhere(
      (type) => type.nameKey == 'notify_user',
    );
    if (notifyUser > 0) {
      final type = available.removeAt(notifyUser);
      available.insert(0, type);
    }
    return List.unmodifiable(available);
  }

  List<PostFlagType> availableTopicFlagTypes(
    String siteUrl,
    TopicDetail topic,
  ) {
    final catalog =
        _postActionCatalogs[siteUrl]?.topicFlags ?? const <PostFlagType>[];
    return List.unmodifiable([
      for (final type in catalog)
        if (type.enabled && type.appliesToTopic && topic.canFlagWith(type.id))
          type,
    ]);
  }

  String? get currentFeedId => focusedTabContext.currentFeedId;

  final _unreadTopicFeed = UnreadTopicFeed();

  bool get currentFeedIsUnread => focusedTabContext.currentFeedIsUnread;

  TopicFeed? get currentFeed => focusedTabContext.currentFeed;

  TopicListMode? get currentTopicListMode =>
      focusedTabContext.currentTopicListMode;

  /// The current document owns its source list even when another panel shows
  /// a different feed.
  ForumTab? get topicListTab => focusedTabContext.topicListTab;

  ContentRoute? get topicListContent => focusedTabContext.topicListContent;

  void closeTopicListReader() => focusedTabContext.closeTopicListReader();

  /// Returns from a conversation to its source, including direct topic links.
  void closeTopic() {
    if (mobileNavigationEnabled) {
      if (currentContent?.isTopic == true) handleBack();
      return;
    }
    final active = activeTab;
    if (active == null || !active.currentContent.isTopic) return;
    if (_readerClosesTab(active)) {
      closeTab(active.id);
      return;
    }
    _workspace.replaceActiveTab(_closeTopicRoute(active));
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance?) _hydrateActiveTab(instance);
  }

  // Ordinary clicks push a topic over its list in the same tab, so closing
  // the reader returns to that list. The tab itself closes only when it holds
  // nothing but the conversation, or when it reads beside its source list
  // shown in the other panel.
  bool _readerClosesTab(ForumTab tab) {
    if (!desktopTopicTabs || !tab.currentContent.isTopic) return false;
    final sourceIndex = tab.contentStack.lastIndexWhere(
      (route) => !route.isTopic,
    );
    if (sourceIndex < 0) return true;
    final source = tab.contentStack[sourceIndex];
    final other = currentWorkspace?.selectedTabIn(
      tab.panel == ForumPanel.main ? ForumPanel.secondary : ForumPanel.main,
    );
    return other != null &&
        other.id != tab.id &&
        other.currentContent.sameDestinationAs(source);
  }

  ForumTab _closeTopicRoute(ForumTab tab) {
    final parentIndex = tab.contentStack.lastIndexWhere(
      (route) => !route.isTopic,
    );
    return tab.navigate(
      rootDestinationId: parentIndex < 0 ? 'latest' : tab.rootDestinationId,
      contentStack: parentIndex < 0
          ? [ContentRoute.topicList(TopicListMode.latest)]
          : tab.contentStack.take(parentIndex + 1).toList(),
    );
  }

  /// New's counts for the topic list on screen, scoped to its category and
  /// tags. `replies` counts the unread topics in every mode, the forum-wide
  /// legacy list included, so the feed menu's Unread shows it too.
  ({int all, int topics, int replies}) get topicListNewCounts =>
      focusedTabContext.topicListNewCounts;

  ({int all, int topics, int replies}) get _forumNewCounts {
    final instance = currentInstance;
    final totals = currentTotals;
    if (instance?.user?.unifiedNewEnabled == true) {
      final tracking = _topicTrackingBySite[instance!.url];
      if (tracking == null || !tracking.hasSnapshot) {
        // Core's totals give a unified-New account one combined count and no
        // unread one, so the subsets and Unread wait for the snapshot.
        return (all: totals?.topicTrackingNew ?? 0, topics: 0, replies: 0);
      }
      final counts = tracking.newActivityCounts;
      final trackedTotal = counts.newTopics + counts.newReplies;
      return (
        all: trackedTotal,
        topics: counts.newTopics,
        replies: counts.newReplies,
      );
    }

    final topics = totals?.topicTrackingNew ?? 0;
    return (
      all: topics,
      topics: topics,
      replies: totals?.topicTrackingUnread ?? 0,
    );
  }

  int get newTopicCount => _forumNewCounts.topics;

  int get newReplyCount => _forumNewCounts.replies;

  int get newActivityCount => _forumNewCounts.all;

  TopicListMode get defaultTopTopicListMode {
    final siteUrl = currentInstance?.url;
    return TopicListMode.top(
      siteUrl == null ? TopPeriod.yearly : _defaultTopPeriodFor(siteUrl),
    );
  }

  TopPeriod _defaultTopPeriodFor(String siteUrl) =>
      TopPeriod.fromQueryValue(siteConfigFor(siteUrl).topPageDefaultPeriod);

  bool get canCreateTopicHere => focusedTabContext.canCreateTopicHere;

  bool get canCreateTopicFromList => focusedTabContext.canCreateTopicFromList;

  bool get canCreateTopicFromSidebar =>
      currentInstance?.user?.canCreateTopic == true;

  CategoryFeed categoryFeedFor(String siteUrl) =>
      _taxonomy.categoryFeedFor(siteUrl);

  /// Per-category unread topic counts from the loaded account snapshot.
  /// Null means tracking is not ready; sparse live arrivals are not a total.
  Map<int, int>? categoryUnreadTopicCountsFor(String siteUrl) {
    if (currentUserFor(siteUrl) == null ||
        _topicTrackingBySite[siteUrl]?.hasSnapshot != true) {
      return null;
    }
    final tracking = _topicTrackingBySite[siteUrl];
    if (tracking == null) return null;
    final counts = <int, int>{};
    for (final topic in tracking.topics) {
      if (topic.isUnread && topic.categoryId != null) {
        counts.update(
          topic.categoryId!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return counts;
  }

  List<TopicCategory> topicComposerCategories(String siteUrl) =>
      _taxonomy.categoriesFor(siteUrl);

  bool sidebarNavigationLoadingFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      return false;
    }
    final feed = categoryFeedFor(siteUrl);
    return !feed.loaded && feed.error == null;
  }

  ContentRoute? get sidebarFilterRoute => focusedTabContext.sidebarFilterRoute;

  TopicCategory? get sidebarCategoryBase =>
      focusedTabContext.sidebarCategoryBase;

  String? get sidebarTagName {
    final route = sidebarFilterRoute;
    final site = currentInstance?.url;
    return route == null || site == null
        ? null
        : _topicListFilterTagNames(site, route).firstOrNull;
  }

  String? get sidebarFilterDestinationId {
    final route = sidebarFilterRoute;
    if (route == null) return null;
    final tag = sidebarTagName;
    if (tag != null) {
      final section = tagSidebarSectionFor(currentInstance!.url);
      return section?.destinations
          .where((item) => item.label.toLowerCase() == tag.toLowerCase())
          .firstOrNull
          ?.id;
    }
    if (route.categoryId case final id?) return 'category-$id';
    return route.topicFilterQuery.isEmpty ? 'latest' : null;
  }

  void _showMobileScopeList() {
    if (!mobileNavigationEnabled) return;
    if (mobileNavigation.tab != MobileTab.topics ||
        mobileNavigation.panelOwner != null) {
      mobileNavigation.selectTab(MobileTab.topics);
    }
    _mobilePane = MobilePane.content;
  }

  void changeSidebarScope({int? categoryId, String? tag}) {
    final site = currentInstance?.url;
    if (site == null) return;
    final source = sidebarFilterRoute;
    final route = _topicListFilterRoute(
      siteUrl: site,
      category: categoryFor(categoryId),
      tagName: tag,
      mode: TopicListMode.fromRoute(source) ?? TopicListMode.latest,
    ).withTopicListQueryFrom(source);
    _showMobileScopeList();
    _replaceTopicListContent(route, keepTopicOpen: false);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    unawaited(loadFeed(route.id));
  }

  bool selectSidebarScopeDestination(SidebarDestination destination) {
    final source = sidebarFilterRoute;
    if (destination.id.startsWith('category-')) {
      final id = int.tryParse(destination.id.substring('category-'.length));
      if (id == null) return false;
      changeSidebarScope(
        categoryId: source?.categoryId == id ? null : id,
        tag: sidebarTagName,
      );
      return true;
    }
    if (destination.icon == DIcons.tag &&
        destination.feedPath != null &&
        destination.id != 'all-tags') {
      if (ContentRoute.fromDestination(destination).isMessages) return false;
      final tag = destination.label;
      changeSidebarScope(
        categoryId: source?.categoryId,
        tag: sidebarTagName?.toLowerCase() == tag.toLowerCase() ? null : tag,
      );
      return true;
    }
    return false;
  }

  SidebarSection? categorySidebarSectionFor(String siteUrl) =>
      _taxonomy.categorySidebarSectionFor(siteUrl);

  SidebarSection? tagSidebarSectionFor(String siteUrl) =>
      _taxonomy.tagSidebarSectionFor(siteUrl);

  TagDirectoryFeed tagDirectoryFeedFor(String siteUrl) =>
      _taxonomy.tagDirectoryFeedFor(siteUrl);

  TopicComposerCapabilities topicComposerCapabilities(String siteUrl) =>
      _topicComposerCapabilities[siteUrl] ?? const TopicComposerCapabilities();

  Future<TopicComposerCapabilities> prepareTopicTagEditor(
    String siteUrl,
  ) async {
    await _ensureTopicComposerCapabilities(siteUrl);
    return topicComposerCapabilities(siteUrl);
  }

  TopicCategory? categoryFor(int? categoryId, {String? siteUrl}) {
    final sourceSite = siteUrl ?? currentInstance?.url;
    if (sourceSite == null || categoryId == null) return null;
    return store.read<TopicCategory>(sourceSite, categoryId);
  }

  String topicCategoryPathLabel(TopicCategory category, {String? siteUrl}) {
    return category_path.topicCategoryPathLabel(
      category,
      categoryFor: (id) => categoryFor(id, siteUrl: siteUrl),
    );
  }

  Ref<Topic> topicRef(String siteUrl, int topicId) =>
      store.ref<Topic>(siteUrl, topicId);

  Ref<TopicCategory> categoryRef(String siteUrl, int categoryId) =>
      store.ref<TopicCategory>(siteUrl, categoryId);

  Ref<Post> postRef(String siteUrl, int postId) =>
      store.ref<Post>(siteUrl, postId);

  String? _feedPath(
    String feedId,
    DiscourseInstance instance, {
    ShellTabContext? context,
  }) {
    final document = context ?? focusedTabContext;
    // A split list can navigate independently while the reader stays active.
    // Resolve its current route before consulting the reader's older stack.
    final routes = [
      ?document.topicListContent,
      ...document.contentStack.reversed,
    ];
    for (final route in routes) {
      if (route.id != feedId) continue;
      if (route.isSearchList) return route.feedPath;
      if (route.isMessages) {
        final username = instance.user?.username;
        if (username == null) return null;
        final path = route.messageListMode.feedPathFor(
          username,
          groupName: route.messageGroupName,
        );
        return route.topicListSearch.isEmpty
            ? path
            : Uri.parse(path)
                  .replace(queryParameters: {'search': route.topicListSearch})
                  .toString();
      }
      if (route.isAdvancedTopicFilter) return route.topicFilterRequestPath;
      if (route.feedPath != null) return route.feedPath;
      if (route.destination case FeedDestination(mode: final mode?)) {
        return mode.feedPath ?? '/latest.json';
      }
    }

    final username = instance.user?.username;
    return switch (feedId) {
      'latest' => '/latest.json',
      'filter' => Uri(
        path: '/filter.json',
        queryParameters: switch (topicFeeds.filterQueryFor(instance.url)) {
          final query when query.isNotEmpty => {'q': query},
          _ => null,
        },
      ).toString(),
      'messages' when username != null =>
        '/topics/private-messages/${Uri.encodeComponent(username)}.json',
      _ => null,
    };
  }

  void selectMessageInbox(String? groupName, {bool keepTopicOpen = false}) =>
      focusedTabContext.selectMessageInbox(
        groupName,
        keepTopicOpen: keepTopicOpen,
      );

  void selectMessageListMode(
    MessageListMode mode, {
    bool keepTopicOpen = false,
  }) {
    final route = topicListContent ?? currentContent;
    if (currentInstance?.user == null || route?.isMessages != true) return;
    final group = route!.messageGroupName;
    if (group != null && !mode.supportsGroup) return;
    final replacement = ContentRoute.messages(groupName: group, mode: mode);
    if (route.sameDestinationAs(replacement)) return;
    _replaceTopicListContent(replacement, keepTopicOpen: keepTopicOpen);
    _syncTopicChannels();
    _notify();
    unawaited(loadFeed(replacement.id));
  }

  final Set<(String, Object)> _dismissingNew = {};

  bool get dismissingNewTopics => _dismissingNew.contains((
    currentInstance?.url ?? '',
    lifecycle.capture(currentInstance?.url ?? '').session,
  ));

  bool get canDismissNewTopics => focusedTabContext.canDismissNewTopics;

  // reset-new looks `tag_name` up case-sensitively and, finding nothing,
  // drops the tag: the dismissal widens to every new topic in the category,
  // or on the whole forum. The list matched its tags case-insensitively, so
  // the only safe name is the exact one its own topics carry, and a list none
  // of whose topics carries it offers no dismissal.

  Future<String?> dismissNewTopics() => focusedTabContext.dismissNewTopics();

  Future<void> loadFeed(
    String destinationId, {
    bool force = false,
    ShellTabContext? context,
  }) async {
    if (context != null &&
        (!identical(context.shell, this) || !context.isCurrent)) {
      return;
    }
    final instance = currentInstance;
    if (instance == null) return;

    // Lookup has already established that an anonymous request cannot read
    // this forum. The shell shows its sign-in action until connecting gives
    // this request a user API key.
    if (instance.loginRequired && !instance.isConnected) return;

    final path = _feedPath(destinationId, instance, context: context);
    if (path == null) return;
    unawaited(
      _taxonomy.ensureScopedSidebarTags(
        instance.url,
        (context ?? focusedTabContext).sidebarFilterRoute?.categoryId,
      ),
    );
    await topicFeeds.load(
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: _trackers[instance.url]?.incoming,
      force: force,
    );
  }

  String filterQueryFor(String siteUrl) => topicFeeds.filterQueryFor(siteUrl);

  Future<List<TopicFilterOption>> loadTopicFilterOptions(String siteUrl) =>
      _filterLookup(
        siteUrl,
        'topics.filter.options',
        (apiKey, clientId) async => (await api.topicFeeds.topicList(
          siteUrl: siteUrl,
          path: '/filter.json',
          apiKey: apiKey,
          clientId: clientId,
        )).filterOptions,
      );

  String topicListFilterEditorQuery(ContentRoute route) => [
    route.topicFilterQuery,
    if (route.categoryId != null) 'category:${route.categoryId}',
    if (_topicListFilterTagNames(currentInstance!.url, route) case final tags
        when tags.isNotEmpty)
      'tag:${topicFilterScopeValue(tags.join('+'))}',
  ].where((part) => part.isNotEmpty).join(' ');

  Future<void> applyTopicListFilterQuery(String query) =>
      focusedTabContext.applyTopicListFilterQuery(query);

  Future<void> submitTopicFilter(String query) async {
    final instance = currentInstance;
    if (instance == null) return;
    final source = topicListContent;
    final tags = _topicListFilterTagNames(instance.url, source);
    final route = query.trim().isEmpty
        ? ContentRoute.filteredTopicList(
            TopicListMode.latest,
            categoryId: source?.categoryId,
            tags: tags,
          )
        : ContentRoute.topicFilter(
            query,
            categoryId: source?.categoryId,
            tags: tags,
          );
    _replaceTopicListContent(
      route,
      keepTopicOpen: currentContent?.isTopic == true,
    );
    _syncTopicChannels();
    _notify();
    await loadFeed(route.id);
  }

  List<TopicCategory> filterCategoriesFor(String siteUrl) =>
      _taxonomy.categoriesFor(siteUrl);

  List<SidebarTag> topicListFilterTagsFor(String siteUrl) =>
      _taxonomy.topicListFilterTagsFor(siteUrl);

  Future<List<TopicCategory>> searchFilterCategories({
    required String siteUrl,
    required String term,
  }) => _taxonomy.searchFilterCategories(siteUrl: siteUrl, term: term);

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
  }) => _taxonomy.searchFilterTags(
    siteUrl: siteUrl,
    term: term,
    categoryId: categoryId,
  );

  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.tagGroups',
    (apiKey, clientId) => api.lookups.searchFilterTagGroups(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.groups',
    (apiKey, clientId) => apiKey == null
        ? Future.value(const [])
        : api.lookups.searchFilterGroups(
            siteUrl: siteUrl,
            term: term,
            apiKey: apiKey,
            clientId: clientId,
          ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterUsers({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.users',
    (apiKey, clientId) async => [
      for (final user in await api.lookups.searchUsers(
        siteUrl: siteUrl,
        term: term,
        apiKey: apiKey,
        clientId: clientId,
      ))
        TopicFilterLookupValue(name: user.username, description: user.name),
    ],
  );

  Future<List<T>> _filterLookup<T>(
    String siteUrl,
    String operation,
    Future<List<T>> Function(String? apiKey, String? clientId) lookup,
  ) async {
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(credentials);
      if (!lease.isCurrent) return const [];
      final found = await credential.run(
        () => lookup(credential.apiKey, credential.clientId),
      );
      return !isDisposed && lease.isCurrent ? found : const [];
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          operation,
          degraded: false,
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }
  }

  int feedScrollRow(String destinationId, {String? tabId}) {
    final instance = currentInstance;
    if (instance == null) return 0;
    final anchor =
        (tabId == null ? topicListTab : currentWorkspace?.tabById(tabId))
            ?.anchors[destinationId];
    if (anchor?.kind == 'feed') return anchor!.itemId;
    return 0;
  }

  void saveFeedScrollRow(String destinationId, int row, {String? tabId}) {
    final instance = currentInstance;
    final tab = tabId == null ? topicListTab : currentWorkspace?.tabById(tabId);
    if (instance == null || tab == null) return;
    topicFeeds.saveScrollRow(instance.url, destinationId, row);
    final previous = tab.anchors[destinationId];
    if (previous?.kind == 'feed' && previous?.itemId == row) return;
    _workspace.replaceTab(
      instance.url,
      tab.copyWith(
        anchors: {
          ...tab.anchors,
          destinationId: ForumTabAnchor(kind: 'feed', itemId: row),
        },
      ),
      persist: false,
    );
    _workspace.schedulePersistAnchors();
  }

  int? topicScrollPostNumber(int topicId, {String? tabId}) {
    final tab = tabId == null ? activeTab : currentWorkspace?.tabById(tabId);
    final route = tab?.currentContent;
    if (tab == null || route?.topicId != topicId) return null;
    final anchor = tab.anchors[route!.id];
    if (anchor?.kind == 'topic') return anchor!.itemId;
    return route.postNumber;
  }

  double topicScrollPostOffset(int topicId, {String? tabId}) {
    final tab = tabId == null ? activeTab : currentWorkspace?.tabById(tabId);
    final route = tab?.currentContent;
    if (tab == null || route?.topicId != topicId) return 0;
    final anchor = tab.anchors[route!.id];
    return anchor?.kind == 'topic' ? anchor!.offset : 0;
  }

  void saveTopicScrollPost(
    int topicId,
    int postNumber, {
    double viewportOffset = 0,
    String? tabId,
  }) {
    final tab = tabId == null ? activeTab : currentWorkspace?.tabById(tabId);
    final route = tab?.currentContent;
    if (tab == null || route?.topicId != topicId) return;
    final previous = tab.anchors[route!.id];
    if (previous?.kind == 'topic' &&
        previous?.itemId == postNumber &&
        previous?.offset == viewportOffset) {
      return;
    }
    _workspace.replaceTab(
      currentInstance!.url,
      tab.copyWith(
        anchors: {
          ...tab.anchors,
          route.id: ForumTabAnchor(
            kind: 'topic',
            itemId: postNumber,
            offset: viewportOffset,
          ),
        },
      ),
      persist: false,
    );
    _workspace.schedulePersistAnchors();
  }

  final Map<String, SiteTracker> _trackers = {};
  final Set<String> _trackersStarting = {};
  final Map<String, Future<void>> _trackerStartRequests = {};
  // Each captured lease identifies both one write and its account lifetime.
  final Map<String, SiteLease> _userStatusWrites = {};
  final Map<String, bool> _optimisticHidePresence = {};
  final Map<String, Object> _hidePresenceWrites = {};
  final Map<String, String> _hidePresenceErrors = {};
  final Map<String, CurrentUserReconciler> _currentUserReconcilers = {};

  CurrentUserReconciler _currentUserReconcilerFor(String siteUrl) {
    final current = _currentUserReconcilers[siteUrl];
    if (current != null && current.isCurrent) return current;
    current?.retire();
    return _currentUserReconcilers[siteUrl] = CurrentUserReconciler(
      lease: lifecycle.capture(siteUrl),
      models: plugins.models,
    );
  }

  final Map<String, Timer> _pluginNotificationFeedRefreshTimers = {};

  final Set<String> _sessionUsersRefreshed = {};

  final Map<String, Future<DiscourseUser?>> _sessionUserRequests = {};

  bool _foreground = true;

  /// When the app left the foreground; null while it is in it.
  DateTime? _backgroundedAt;

  /// Core keeps only the last `message_bus_max_backlog_size` (100) messages of
  /// each channel, and `/new` and `/unread` are site-wide channels filtered
  /// per reader, so a tracker stopped for long resumes past messages no poll
  /// can replay. Core's web client never stops: it polls a hidden tab every
  /// `background_polling_interval` (60 s) and trusts that poll's backlog. An
  /// absence shorter than that is left to the resume poll likewise; a longer
  /// one re-reads the tracking snapshot.
  static const _topicTrackingResyncAfter = Duration(seconds: 60);

  int incomingCount(String destinationId) {
    final instance = currentInstance;
    if (instance == null) return 0;
    return _trackers[instance.url]?.incoming.count(destinationId) ?? 0;
  }

  Future<void> showIncoming(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final tracker = _trackers[instance.url];
    final path = _feedPath(destinationId, instance);
    if (tracker == null || path == null) return;
    await topicFeeds.showIncoming(
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: tracker.incoming,
    );
  }

  bool _admitsIncomingTopic(String siteUrl, Object? data) =>
      _trackingFor(siteUrl).admitsIncoming(
        data,
        user: _instanceAt(siteUrl)?.user,
        config: siteConfigFor(siteUrl),
      );

  /// What a loaded list announces, read the way core's `trackIncoming` reads
  /// the list `findTopicList` found: Latest, New and Unseen by name, a
  /// category or tag link as its default list, the category from the path
  /// and the tags as the server resolved them.
  IncomingTopicsFilter? _incomingTopicsFilter(String path, TopicList list) {
    final scope = ContentRoute(
      destination: FeedDestination.fromPath(
        key: 'topic-list-filter-$path',
        path: path,
      ),
      title: '',
      icon: DIcons.list,
    );
    final categoryId = scope.categoryId;
    final tagged = scope.tagNames.isNotEmpty;
    final defaultList = switch (Uri.tryParse(path)?.pathSegments) {
      ['c', ...] => categoryId != null,
      ['tag', ...] || ['tags', 'c', ...] => tagged,
      _ => false,
    };
    final mode = scope.isAdvancedTopicFilter
        ? null
        : TopicListMode.fromRoute(scope);
    // New – replies announces nothing. Core counts a new topic there too, as
    // the subset is only a query parameter, and then asks the replies subset
    // for it, which never returns one.
    final (String, bool)? kind = switch (mode) {
      TopicListMode.latest => ('latest', true),
      TopicListMode.newActivity || TopicListMode.newTopics => ('new', false),
      TopicListMode.unseen => ('unseen', false),
      null when defaultList => ('latest', true),
      _ => null,
    };
    if (kind == null) return null;
    final (served, countsBumps) = kind;
    // A category link is its default view, which is Latest unless the site
    // names another; sites that do not say are taken to be Latest.
    if (list.filter case final resolved? when resolved != served) return null;
    // Without tagging, or for `/tag/none`, the server names no tag, and a
    // list that cannot be matched to its topics announces none of them.
    if (tagged && list.tagIds.isEmpty) return null;
    final tagIds = tagged ? list.tagIds.toSet() : const <int>{};
    return countsBumps
        ? IncomingTopicsFilter.latest(categoryId: categoryId, tagIds: tagIds)
        : IncomingTopicsFilter.created(categoryId: categoryId, tagIds: tagIds);
  }

  /// Gives the site's tracker every list loaded so far, including those that
  /// finished loading before its connection opened.
  void _trackIncomingLists(String siteUrl) {
    _trackers[siteUrl]?.incoming.track(
      topicFeeds.incomingFiltersFor(siteUrl),
      parentCategoryOf: (categoryId) =>
          categoryFor(categoryId, siteUrl: siteUrl)?.parentCategoryId,
    );
  }

  void _syncTracking() {
    final instance = currentInstance;
    final retainedSiteUrls = _pluginBackgroundSiteUrls;

    for (final entry in _trackers.entries) {
      if (entry.key != instance?.url) entry.value.unwatchTopic();
      final site = _instanceAt(entry.key);
      // An anonymous tracker outlives its forum turning private, and then
      // every poll it makes is refused.
      final refused = site != null && site.loginRequired && !site.isConnected;
      final selectedAndVisible = _foreground && entry.key == instance?.url;
      final connectedAndVisible = _foreground && (site?.isConnected ?? false);
      if (refused) {
        entry.value.stop();
      } else if (selectedAndVisible ||
          connectedAndVisible ||
          retainedSiteUrls.contains(entry.key)) {
        entry.value.start();
      } else {
        entry.value.stop();
      }
    }

    for (final candidate in _instances) {
      final selected = candidate.url == instance?.url;
      final retained = retainedSiteUrls.contains(candidate.url);
      if (!_foreground && !retained) continue;
      if (!selected && !candidate.isConnected && !retained) continue;

      // Core never starts MessageBus for an anonymous reader on a private site.
      // Such a poll can only be refused, and retrying that refusal adds traffic
      // without a channel the reader is allowed to consume.
      if (candidate.loginRequired && !candidate.isConnected) continue;

      final tracker = _trackers[candidate.url];
      if (tracker == null) {
        unawaited(_ensureTrackerStarted(candidate));
      } else {
        tracker.start();
      }
    }

    if (_foreground && instance != null) {
      final selected = instance;
      final tracker = _trackers[selected.url];
      if (tracker != null) _syncTopicWatch(selected.url, tracker);
    }
  }

  void _syncTopicChannels() {
    final instance = currentInstance;
    if (instance == null) return;
    final tracker = _trackers[instance.url];
    if (tracker == null) return;
    _syncTopicWatch(instance.url, tracker);
  }

  void _syncTopicWatch(String siteUrl, SiteTracker tracker) {
    // Every panel's selected document is on screen, so each keeps its topic
    // live. Without panels (touch layouts, phones) only the active tab is.
    final visible = desktopPanelsEnabled
        ? [
            for (final panel in ForumPanel.values)
              selectedTabIn(panel)?.currentContent,
          ]
        : [currentContent];
    final routes = <int, ContentRoute>{
      for (final route in visible.nonNulls) ?route.topicId: route,
    };
    if (routes.isEmpty) {
      tracker.unwatchTopic();
      return;
    }
    final channelsByTopic = {
      for (final topicId in routes.keys)
        topicId: [
          '/topic/$topicId',
          ...plugins.registry.topicChannels(topicId),
        ],
    };
    final lease = lifecycle.capture(siteUrl);
    tracker.watchTopic(
      routes.keys.first,
      channelsByTopic.values.expand((channels) => channels).toSet().toList(),
      (channel, data) {
        if (isDisposed ||
            !lease.isCurrent ||
            !identical(_trackers[siteUrl], tracker)) {
          return;
        }
        for (final entry in channelsByTopic.entries) {
          if (!entry.value.contains(channel)) continue;
          final topicId = entry.key;
          final coreChannel = '/topic/$topicId';
          if (channel == coreChannel) {
            _applyTopicNotificationMessage(siteUrl, topicId, data, lease);
            _applyTopicStatsMessage(siteUrl, topicId, data, lease);
          }
          final core = channel == coreChannel
              ? _coreTopicMessageInvalidation(siteUrl, data)
              : _noCoreTopicInvalidation;
          if (core.stream ||
              plugins.registry.staleTopic(topicId, channel, data)) {
            unawaited(
              _topicData
                  .forSite(siteUrl)
                  .refresh(topicId, slug: routes[topicId]?.slug ?? ''),
            );
          }
          final stale = plugins.registry.stalePosts(channel, data);
          if (stale.isNotEmpty) {
            _topicData.forSite(siteUrl).invalidatePosts(topicId, stale);
          }
          if (core.post case final id?) {
            _topicData.forSite(siteUrl).invalidatePosts(topicId, {
              id,
            }, deletion: core.deletion);
          }
        }
      },
      // Each visible conversation resumes from its own HTTP snapshot cursor.
      lastIds: {
        for (final topicId in routes.keys)
          '/topic/$topicId': store
              .read<TopicDetail>(siteUrl, topicId)
              ?.messageBusLastId,
      },
    );
  }

  /// `Post#publish_change_to_clients!` types, each naming one post by `id`.
  static const _corePostMessageTypes = {
    'revised',
    'rebaked',
    'acted',
    'liked',
    'unliked',
    'deleted',
    'destroyed',
    'recovered',
  };

  static const ({bool stream, int? post, bool deletion})
  _noCoreTopicInvalidation = (stream: false, post: null, deletion: false);

  /// Whether a core `/topic/{id}` message changes the stream, or only the one
  /// post it names. A named post is re-read only while held, so an edit, like
  /// or deletion reaches a reader who is looking at it, including one whose
  /// cached topic is replayed from `messageBusLastId`. `deletion` marks the
  /// messages after which a re-read that omits the post means it is gone.
  ({bool stream, int? post, bool deletion}) _coreTopicMessageInvalidation(
    String siteUrl,
    Object? data,
  ) {
    if (data is! Map) return _noCoreTopicInvalidation;
    final type = data['type'];
    // As on the web client, a reload replaces the message's per-post handling.
    if (type == 'created' || data['reload_topic'] == true) {
      return (stream: true, post: null, deletion: false);
    }
    final postId = _corePostMessageTypes.contains(type)
        ? liveRefreshId(data['id'])
        : null;
    if (postId == null) return _noCoreTopicInvalidation;
    // A reader who could not see the deleted post no longer holds it, and its
    // recovery has to put it back at its place in the stream.
    if (type == 'recovered' && store.read<Post>(siteUrl, postId) == null) {
      return (stream: true, post: null, deletion: false);
    }
    return (
      stream: false,
      post: postId,
      deletion: type == 'deleted' || type == 'destroyed',
    );
  }

  void _applyTopicStatsMessage(
    String siteUrl,
    int topicId,
    Object? data,
    SiteLease lease,
  ) {
    if (!lease.isCurrent || isDisposed) return;
    if (data is! Map || data['type'] != 'stats') return;
    int? total(Object? value) => value is int && value >= 0 ? value : null;
    _topicData
        .forLease(siteUrl, lease)
        ?.acceptTotals(
          topicId,
          likeCount: total(data['like_count']),
          postsCount: total(data['posts_count']),
        );
  }

  void _acceptLiveNotificationState(
    String siteUrl,
    Object? data,
    SiteLease lease,
  ) {
    // This is called only from the tracker's lifecycle-bound commit closure.
    // Advancing here, rather than in the raw MessageBus callback, prevents a
    // retired account generation from invalidating current feeds or counts.
    final groupedCounts = data is Map
        ? NotificationTypeCounts.fromWire(data['grouped_unread_notifications'])
        : NotificationTypeCounts.unavailable;
    if (groupedCounts.isAvailable) {
      _onGroupedUnreadAuthorityAdvanced(siteUrl);
    }
    accountActivity.applyLiveNotificationState(siteUrl, data);
    if (!accountActivity.hasTrackedPluginNotifications(siteUrl)) return;

    _pluginNotificationFeedRefreshTimers.remove(siteUrl)?.cancel();
    late final Timer timer;
    timer = Timer(pluginNotificationFeedRefreshDebounce, () {
      if (!identical(_pluginNotificationFeedRefreshTimers[siteUrl], timer)) {
        return;
      }
      _pluginNotificationFeedRefreshTimers.remove(siteUrl);
      if (isDisposed || !lease.isCurrent) return;
      final instance = _instanceAt(siteUrl);
      if (instance?.isConnected != true) return;
      accountActivity.refreshLoadedPluginNotifications(instance!).ignore();
    });
    _pluginNotificationFeedRefreshTimers[siteUrl] = timer;
  }

  Future<void> _ensureTrackerStarted(DiscourseInstance instance) {
    final active = _trackerStartRequests[instance.url];
    if (active != null) return active;

    late final Future<void> request;
    request = _startTracking(instance).whenComplete(() {
      if (identical(_trackerStartRequests[instance.url], request)) {
        final removed = _trackerStartRequests.remove(instance.url);
        assert(identical(removed, request));
      }
    });
    _trackerStartRequests[instance.url] = request;
    return request;
  }

  Future<void> _startTracking(DiscourseInstance instance) async {
    final siteUrl = instance.url;
    if (instance.loginRequired && !instance.isConnected) return;
    if (_trackers.containsKey(siteUrl) || !_trackersStarting.add(siteUrl)) {
      return;
    }
    final lease = lifecycle.capture(siteUrl);

    final String? apiKey;
    final String? clientId;
    final AccountRequestCredentials requestCredentials;
    try {
      // The persisted account state, not a credential that may have failed
      // to delete, decides whether this session may open private channels.
      final requestSession = AccountRequestSession(siteUrl, lease);
      requestCredentials = instance.isConnected
          ? await requestSession.credentials(credentials)
          : requestSession.anonymousCredentials();
      apiKey = requestCredentials.apiKey;
      // An anonymous bus sends no client id, and a signed-out forum must not
      // raise the platform's notification prompt by reading one.
      clientId = apiKey == null ? null : requestCredentials.clientId;
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'messageBus.readCredentials');
      lease.commit(() => _trackersStarting.remove(siteUrl));
      return;
    }

    if (isDisposed || !lease.isCurrent) return;

    final currentUserOwner = _currentUserReconcilerFor(siteUrl);
    final userSnapshot = currentUserOwner.beginSnapshot();
    final bootstrapTrackingOwner = apiKey == null || clientId == null
        ? null
        : _trackingFor(siteUrl);
    final bootstrapTicket = bootstrapTrackingOwner?.beginBootstrap();
    final bootstrap = apiKey == null || clientId == null
        ? null
        : await _messageBusBootstrap(
            siteUrl: siteUrl,
            lease: lease,
            requestCredentials: requestCredentials,
          );
    final bootstrapUser = bootstrap?.currentUser;
    final freshBootstrapUser = bootstrapUser == null
        ? null
        : _acceptFreshCurrentUserSnapshot(
            siteUrl,
            bootstrapUser,
            lease,
            userSnapshot,
          );

    final userId = apiKey == null
        ? null
        : freshBootstrapUser?.id ??
              await _accountId(siteUrl, apiKey: apiKey, lease: lease);
    final initialLastIds =
        bootstrap?.initialLastIds(userId: userId) ?? const {};

    lease.commit(() {
      _trackersStarting.remove(siteUrl);
      final current = _instanceAt(siteUrl);
      if (isDisposed || current == null) {
        if (bootstrapTicket != null) {
          bootstrapTrackingOwner?.cancelBootstrap(bootstrapTicket);
        }
        return;
      }

      // A site that is neither visible nor retained by a plugin lease gets no
      // tracker, subscriptions or plugin attachments; _syncTracking builds
      // them once it qualifies.
      final selectedAndVisible = _foreground && currentInstance?.url == siteUrl;
      final connectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!selectedAndVisible &&
          !connectedAndVisible &&
          !_backgroundRetention.retains(siteUrl)) {
        if (bootstrapTicket != null) {
          bootstrapTrackingOwner?.cancelBootstrap(bootstrapTicket);
        }
        return;
      }

      void commit(SiteMutation mutation) {
        if (!isDisposed) lease.commit(mutation);
      }

      final bootstrapState = bootstrap?.currentUserState;
      if (bootstrapState != null) {
        _acceptLiveNotificationState(siteUrl, bootstrapState, lease);
        accountActivity.applyReviewableCounts(siteUrl, bootstrapState);
      }

      final trackingUsername = apiKey == null
          ? null
          : freshBootstrapUser?.username ?? current.user?.username;
      final tracking = _trackingFor(siteUrl);
      final currentBootstrapTicket = identical(tracking, bootstrapTrackingOwner)
          ? bootstrapTicket
          : tracking.beginBootstrap();
      final bootstrapTracking = bootstrap?.topicTrackingState;
      if (trackingUsername != null &&
          userId != null &&
          bootstrapTracking != null &&
          currentBootstrapTicket != null &&
          currentUserOwner.categoryPreferencesAreCurrent(userSnapshot) &&
          bootstrap!.hasCompleteTopicTrackingSnapshot(userId) &&
          tracking.completeBootstrap(
            currentBootstrapTicket,
            bootstrapTracking,
          )) {
        _topicTrackingRetries.remove(siteUrl);
        if (currentInstance?.url == siteUrl) _notify();
      } else if (currentBootstrapTicket != null) {
        tracking.cancelBootstrap(currentBootstrapTicket);
      }
      final loadTicket = trackingUsername == null || tracking.hasSnapshot
          ? null
          : tracking.beginSnapshot();
      final shouldLoadTopicTracking = loadTicket != null;
      if (shouldLoadTopicTracking) {
        _topicTrackingRetries.remove(siteUrl);
      }

      final SiteTracker tracker;
      try {
        tracker = trackers(
          siteUrl: siteUrl,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          initialLastIds: initialLastIds,
          shouldLongPoll: () =>
              _foreground || _backgroundRetention.retains(siteUrl),
          onIncomingTopics: () => commit(() {
            if (currentInstance?.url == siteUrl) _notifyLiveChange();
          }),
          // A superseded account's tracker must not judge by, or leave hints
          // in, the filter its successor now owns at the same URL.
          admitIncoming: (data) =>
              !isDisposed &&
              lease.isCurrent &&
              _admitsIncomingTopic(siteUrl, data),
          onNotifications: (data) =>
              commit(() => _acceptLiveNotificationState(siteUrl, data, lease)),
          onReviewableCounts: (data) => commit(
            () => accountActivity.applyReviewableCounts(siteUrl, data),
          ),
        );
      } catch (error, stackTrace) {
        if (loadTicket != null) tracking.cancelSnapshot(loadTicket);
        _reportOperationalError(error, stackTrace, 'messageBus.start');
        return;
      }
      _trackers[siteUrl] = tracker;
      _trackIncomingLists(siteUrl);
      if (apiKey != null && clientId != null) {
        if (userId != null) {
          try {
            tracker.watchTopicTrackingState(
              userId,
              (data) => commit(() => _applyTopicTrackingMessage(siteUrl, data)),
              lastIds: initialLastIds,
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeTopicTracking',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
        if (shouldLoadTopicTracking) {
          unawaited(
            _loadTopicTrackingState(
              siteUrl: siteUrl,
              username: trackingUsername!,
              lease: lease,
              tracking: tracking,
              ticket: loadTicket,
              requestCredentials: requestCredentials,
            ),
          );
        }
        try {
          tracker.watchPluginChannel(
            '/user-status',
            (data) => commit(() => _applyUserStatusMessage(siteUrl, data)),
            lastId:
                bootstrap?.currentUser?.status?.messageBusLastId ??
                _instanceAt(siteUrl)?.user?.status?.messageBusLastId,
          );
        } catch (error, stackTrace) {
          _reportOperationalError(
            error,
            stackTrace,
            'messageBus.subscribeUserStatus',
            severity: DiagnosticSeverity.warning,
          );
        }
        try {
          tracker.watchPluginChannel(
            '/refresh-sidebar-sections',
            (_) => commit(
              () => _customSidebar.invalidate(siteUrl, account: lease),
            ),
          );
        } catch (error, stackTrace) {
          _reportOperationalError(
            error,
            stackTrace,
            'messageBus.subscribeSidebarSections',
            severity: DiagnosticSeverity.warning,
          );
        }
        if (userId != null) {
          try {
            tracker.watchPluginChannel(
              '/user-drafts/$userId',
              (data) => commit(() => _applyUserDraftsMessage(siteUrl, data)),
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeUserDrafts',
              severity: DiagnosticSeverity.warning,
            );
          }
          try {
            final user = _instanceAt(siteUrl)?.user;
            tracker.watchPluginChannel(
              '/do-not-disturb/$userId',
              (data) => commit(() => doNotDisturb.applyMessage(siteUrl, data)),
              lastId:
                  bootstrap?.currentUser?.doNotDisturbChannelPosition ??
                  user?.doNotDisturbChannelPosition,
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeDoNotDisturb',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
      }
      for (final owned
          in _pluginSession.ownedCapabilities<PluginTrackerAttachment>()) {
        try {
          owned.capability.attachPluginTracker(
            siteUrl,
            tracker.pluginLiveChannels(
              plugins.liveChannelScopesFor(owned.owner),
            ),
          );
        } catch (error, stackTrace) {
          _reportOperationalError(
            error,
            stackTrace,
            'plugins.attachTracker.${owned.owner.value}',
            severity: DiagnosticSeverity.warning,
          );
        }
      }
      final stillSelectedAndVisible =
          _foreground && currentInstance?.url == siteUrl;
      final stillConnectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (stillSelectedAndVisible) _syncTopicWatch(siteUrl, tracker);
      // Last, so the first poll carries every channel registered above.
      if (stillSelectedAndVisible ||
          stillConnectedAndVisible ||
          _backgroundRetention.retains(siteUrl)) {
        tracker.start();
      }
    });
  }

  Future<SiteMessageBusBootstrap?> _messageBusBootstrap({
    required String siteUrl,
    required SiteLease lease,
    required AccountRequestCredentials requestCredentials,
  }) async {
    try {
      final bootstrap = await RequestIntent.background().run(
        () => requestCredentials.run(
          () => api.site.messageBusBootstrap(
            siteUrl: siteUrl,
            apiKey: requestCredentials.apiKey!,
            clientId: requestCredentials.clientId,
          ),
        ),
      );
      if (isDisposed || !lease.isCurrent) return null;
      if (bootstrap != null) {
        _serverPluginNames[siteUrl] = bootstrap.serverPluginNames;
        _notify();
      }
      return bootstrap;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        // The endpoint is the ordinary application document, so older and
        // customized sites may not expose every preload entry. Existing JSON
        // snapshots remain the compatibility path.
        _reportOperationalError(
          error,
          stackTrace,
          'messageBus.preload',
          severity: DiagnosticSeverity.warning,
        );
      }
      return null;
    }
  }

  final Map<String, Set<String>> _serverPluginNames = {};

  bool supportsComposerColors(String siteUrl) =>
      _serverPluginNames[siteUrl]?.contains('discourse-bbcode-color') ?? false;

  Future<void> _loadTopicTrackingState({
    required String siteUrl,
    required String username,
    required SiteLease lease,
    required TopicTrackingReconciler tracking,
    required TopicTrackingSnapshot ticket,
    Future<void> Function()? refreshCategoryPreferences,
    AccountRequestCredentials? requestCredentials,
  }) async {
    bool ownsLoad() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_topicTrackingBySite[siteUrl], tracking) &&
        tracking.owns(ticket);
    AccountRequestCredentials? heldCredentials = requestCredentials;
    try {
      if (!ownsLoad()) return;
      if (refreshCategoryPreferences != null) {
        await refreshCategoryPreferences();
        if (!ownsLoad() || !tracking.preferencesReady(ticket)) return;
      }
      final credential =
          heldCredentials ??
          await AccountRequestSession(siteUrl, lease).credentials(credentials);
      heldCredentials = credential;
      if (!ownsLoad()) return;
      if (credential.apiKey == null) {
        tracking.cancelSnapshot(ticket);
        return;
      }
      final snapshot = await RequestIntent.background().run(
        () => credential.run(
          () => api.site.topicTrackingState(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            username: username,
            clientId: credential.clientId,
          ),
        ),
      );
      if (!ownsLoad()) return;
      final currentUsername = _instanceAt(siteUrl)?.user?.username;
      if (currentUsername?.toLowerCase() != username.toLowerCase()) return;
      lease.commit(() {
        if (ownsLoad() && tracking.completeSnapshot(ticket, snapshot)) {
          _topicTrackingRetries.remove(siteUrl);
          if (currentInstance?.url == siteUrl) _notify();
        }
      });
    } catch (error, stackTrace) {
      if (ownsLoad()) {
        _reportOperationalError(
          error,
          stackTrace,
          'topicTracking.load',
          severity: DiagnosticSeverity.warning,
        );
        tracking.failSnapshot(ticket);
        _topicTrackingRetries[siteUrl] = (
          lease: lease,
          tracking: tracking,
          load: (nextTicket) => _loadTopicTrackingState(
            siteUrl: siteUrl,
            username: username,
            lease: lease,
            tracking: tracking,
            ticket: nextTicket,
            refreshCategoryPreferences: refreshCategoryPreferences,
            requestCredentials: heldCredentials,
          ),
        );
      }
    } finally {
      if (ownsLoad()) tracking.cancelSnapshot(ticket);
    }
  }

  void _applyTopicTrackingMessage(String siteUrl, Object? data) {
    // A message proves the site reachable again. A snapshot whose load failed
    // is fetched before this message is buffered, so the replay covers it.
    _retryTopicTrackingLoad(siteUrl);
    final tracking = _trackingFor(siteUrl);
    final changed = tracking.accept(
      data,
      user: _instanceAt(siteUrl)?.user,
      config: siteConfigFor(siteUrl),
    );
    if (changed == null) return;
    _applyTopicDismissal(siteUrl, data, tracking);
    if (changed && currentInstance?.url == siteUrl) {
      _notifyLiveChange();
    }
  }

  /// Core refreshes loaded list rows from tracking state once a dismissal
  /// changes it (`updateTopics`). Every list here reads one store record per
  /// topic, so the record takes the dismissal; a list that is not reloaded,
  /// or is served from its cache, would otherwise keep every marker. The
  /// message is applied whether or not tracking holds the topic: it is the
  /// server's record of the dismissal.
  void _applyTopicDismissal(
    String siteUrl,
    Object? data,
    TopicTrackingReconciler tracking,
  ) {
    if (data is! Map) return;
    final type = data['message_type'];
    if (type != 'dismiss_new' && type != 'dismiss_new_posts') return;
    for (final value in jsonArray(jsonObject(data['payload'])['topic_ids'])) {
      final topicId = jsonIntOrNull(value);
      if (topicId == null) continue;
      store.update<Topic>(siteUrl, topicId, (row) {
        // A dismissed new topic is seen but stays unvisited: core records the
        // dismissal apart from any read position.
        if (type == 'dismiss_new') {
          return row.seen ? row : row.copyWith(seen: true);
        }
        // Core moves only an existing read position, to the highest post.
        if (row.lastReadPostNumber == null) return row;
        final tracked = tracking.topic(topicId)?.highestPostNumber ?? 0;
        return _readThrough(
          row,
          tracked > row.highestPostNumber ? tracked : row.highestPostNumber,
        );
      });
    }
  }

  /// A list response sent before a dismissal, or before a read elsewhere,
  /// must not restore markers tracking state has since cleared. Only a state
  /// that has passed the row's own is projected: a dismissed topic is never
  /// new again, and a read position covering the row's highest post leaves
  /// nothing unread in it. A row reporting a reply since then carries a
  /// highest post beyond that position, so it keeps its count.
  Topic _projectTopicTracking(String siteUrl, Topic incoming) {
    final tracked = _topicTrackingBySite[siteUrl]?.topic(incoming.id);
    if (tracked == null) return incoming;
    var row = incoming;
    if (!row.listReadStateKnown &&
        row.lastReadPostNumber == null &&
        tracked.isNew &&
        row.seen) {
      row = row.copyWith(seen: false);
    }
    if (tracked.isSeen && !row.seen) row = row.copyWith(seen: true);
    final position = tracked.lastReadPostNumber;
    final held = row.lastReadPostNumber;
    // A sparse row's missing highest post is no proof that it is read.
    if (position != null &&
        held != null &&
        position > held &&
        row.highestPostNumber > 0 &&
        position >= row.highestPostNumber) {
      row = _readThrough(row, position);
    }
    return row;
  }

  static Topic _readThrough(Topic row, int position) {
    final read = row.copyWith(
      lastReadPostNumber: position > (row.lastReadPostNumber ?? 0)
          ? position
          : null,
      highestPostNumber: position > row.highestPostNumber ? position : null,
      unreadPosts: 0,
      newPosts: 0,
    );
    return read == row ? row : read;
  }

  /// One poll answer can carry a backlog of messages, delivered in one
  /// synchronous run: tracking rows, `/latest` and `/new` arrivals, `/topic`
  /// stats. Each message applies its state at once; the facade notifies once
  /// for the run, as every shell selector would otherwise re-select per
  /// message. The notification carries no state, so a disposal or a lease
  /// change before it runs leaves nothing to undo.
  void _notifyLiveChange() {
    if (_liveChangeNotifyPending) return;
    _liveChangeNotifyPending = true;
    scheduleMicrotask(() {
      _liveChangeNotifyPending = false;
      if (!isDisposed) _notify();
    });
  }

  /// Category and tag badges stay dark until a snapshot lands, because the bus
  /// alone cannot seed them. A load that failed is retried once the site is
  /// reachable or looked at again: on a tracking message, on foreground, and
  /// on selection. The retry keeps the failed load's account and lease, so a
  /// site tracked again since then owns its own load instead.
  void _retryTopicTrackingLoad(String siteUrl) {
    final retry = _topicTrackingRetries.remove(siteUrl);
    if (retry == null ||
        isDisposed ||
        !retry.lease.isCurrent ||
        !identical(_topicTrackingBySite[siteUrl], retry.tracking)) {
      return;
    }
    final ticket = retry.tracking.beginSnapshot();
    if (ticket != null) unawaited(retry.load(ticket));
  }

  /// Re-reads a held snapshot after an absence the bus backlog may not
  /// cover. A load already in flight serves as this resume's read. The
  /// buffer opens before the request, as for any load, so what the resume
  /// poll delivers meanwhile reaches the new snapshot too, and
  /// [TopicTrackingReconciler] ignores a message it has passed.
  void _resyncTopicTracking(String siteUrl) {
    final username = _instanceAt(siteUrl)?.user?.username;
    final tracking = _topicTrackingBySite[siteUrl];
    if (username == null || tracking?.hasSnapshot != true) return;
    final ticket = tracking!.beginSnapshot();
    if (ticket == null) return;
    _topicTrackingRetries.remove(siteUrl);
    final lease = lifecycle.capture(siteUrl);
    bool ownsResync() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_topicTrackingBySite[siteUrl], tracking) &&
        tracking.owns(ticket);
    unawaited(() async {
      try {
        final requestCredentials = await AccountRequestSession(
          siteUrl,
          lease,
        ).credentials(credentials);
        if (!ownsResync()) return;
        if (requestCredentials.apiKey == null) {
          tracking.cancelSnapshot(ticket);
          return;
        }
        await _loadTopicTrackingState(
          siteUrl: siteUrl,
          username: username,
          lease: lease,
          tracking: tracking,
          ticket: ticket,
          requestCredentials: requestCredentials,
        );
      } catch (error, stackTrace) {
        if (ownsResync()) {
          _reportOperationalError(
            error,
            stackTrace,
            'topicTracking.readCredentials',
            severity: DiagnosticSeverity.warning,
          );
          tracking.cancelSnapshot(ticket);
        }
      }
    }());
  }

  Future<int?> _accountId(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  }) async {
    if (!lease.isCurrent) return null;
    final held = _instanceAt(siteUrl);
    if (held == null) return null;
    final storedId = held.user?.id;
    if (storedId != null) return storedId;

    final user = await _sessionUser(siteUrl, apiKey, lease: lease);
    if (!lease.isCurrent) return null;
    // A stored id is stable enough to keep this account's private counters
    // connected after a failed refresh, but its capabilities remain unknown.
    return user?.id ?? _instanceAt(siteUrl)?.user?.id;
  }

  Future<DiscourseUser?> _sessionUser(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
    bool force = false,
  }) {
    final held = _instanceAt(siteUrl);
    if (held == null) return Future.value();
    if (!force && _sessionUsersRefreshed.contains(siteUrl)) {
      return Future.value(held.user);
    }

    final active = _sessionUserRequests[siteUrl];
    final session = lease ?? lifecycle.capture(siteUrl);
    if (active != null) {
      if (!force) return active;
      return () async {
        await active;
        if (!session.isCurrent) return null;
        return _sessionUser(siteUrl, apiKey, lease: session, force: true);
      }();
    }

    final currentUserOwner = _currentUserReconcilerFor(siteUrl);
    final userSnapshot = currentUserOwner.beginSnapshot();
    late final Future<DiscourseUser?> request;
    request = _readSessionUser(siteUrl, apiKey, session, userSnapshot)
        .whenComplete(() {
          if (identical(_sessionUserRequests[siteUrl], request)) {
            final removed = _sessionUserRequests.remove(siteUrl);
            assert(identical(removed, request));
          }
        });
    _sessionUserRequests[siteUrl] = request;
    return request;
  }

  Future<DiscourseUser?> _readSessionUser(
    String siteUrl,
    String apiKey,
    SiteLease lease,
    CurrentUserSnapshot userSnapshot,
  ) async {
    if (!lease.isCurrent || _connectingSiteUrl == siteUrl) return null;

    final DiscourseUser responseUser;
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (credential.apiKey == null) return null;
      responseUser = await credential.run(
        () =>
            api.site.currentUser(siteUrl: siteUrl, apiKey: credential.apiKey!),
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return null;
      _reportOperationalError(
        error,
        stackTrace,
        'messageBus.resolveAccount',
        severity: DiagnosticSeverity.warning,
      );
      if (error is ApiKeyRejectedException) {
        await _expireRejectedAccount(siteUrl, apiKey, lease);
        return null;
      }
      lease.commit(() {
        if (_instanceAt(siteUrl)?.user?.hidePresence == null &&
            !_hidePresenceWrites.containsKey(siteUrl)) {
          _hidePresenceErrors[siteUrl] =
              appL10n.couldnTLoadThePresenceSettingTryAgain;
          _notify();
        }
      });
      return null;
    }
    return _acceptFreshCurrentUserSnapshot(
      siteUrl,
      responseUser,
      lease,
      userSnapshot,
    );
  }

  /// Every request carrying a key the site refuses fails the same way, so the
  /// forum is signed out and offers Sign in instead of keeping an account
  /// that nothing can be done with. That includes a suspended account, whose
  /// key the site would accept again once the suspension ends: the web client
  /// shows such an account signed out too, and signing in works again then.
  Future<void> _expireRejectedAccount(
    String siteUrl,
    String apiKey,
    SiteLease lease,
  ) async {
    final host = _instanceAt(siteUrl)?.host;
    if (host == null) return;
    _offerSignInAgain(
      siteUrl,
      await _accountSessions.expireRejectedKey(
        siteUrl,
        apiKey: apiKey,
        lease: lease,
      ),
      appL10n.noLongerAcceptsThisSignInSignInAgainToContinue((host).toString()),
    );
  }

  /// A signed-in forum whose key storage holds no key reads anonymously and
  /// has every write refused while it still shows the account, so it is signed
  /// out the way a refused key is. Only the account refresh decides this, not
  /// each request that finds no key.
  Future<void> _expireMissingAccount(String siteUrl, SiteLease lease) async {
    final host = _instanceAt(siteUrl)?.host;
    if (host == null) return;
    _offerSignInAgain(
      siteUrl,
      await _accountSessions.expireMissingKey(siteUrl, lease: lease),
      appL10n.theSignInForIsNoLongerSavedOnThisDevice((host).toString()),
    );
  }

  void _offerSignInAgain(
    String siteUrl,
    AccountDisconnectionResult result,
    String message,
  ) {
    if (isDisposed ||
        result.outcome != AccountDisconnectionOutcome.disconnected) {
      return;
    }
    result.lease?.commit(() {
      _connectErrors[siteUrl] = message;
      _notify();
    });
  }

  DiscourseUser? _acceptFreshCurrentUserSnapshot(
    String siteUrl,
    DiscourseUser responseUser,
    SiteLease lease,
    CurrentUserSnapshot userSnapshot,
  ) {
    if (isDisposed || !lease.isCurrent || _connectingSiteUrl == siteUrl) {
      return null;
    }
    final user = _acceptDoNotDisturbSnapshot(siteUrl, responseUser);

    var changed = false;
    DiscourseUser? committedUser;
    final accepted = lease.commit(() {
      final fresh = _instanceAt(siteUrl);
      if (fresh == null) return;
      final previousUser = fresh.user;
      final reconciliation = _currentUserReconcilerFor(
        siteUrl,
      ).reconcile(userSnapshot, previous: previousUser, incoming: user);
      if (reconciliation == null) return;
      final accountChanged = reconciliation.accountChanged;
      final reconciledUser = reconciliation.user;
      committedUser = reconciledUser;
      _sessionUsersRefreshed.add(siteUrl);
      _hidePresenceErrors.remove(siteUrl);
      if (previousUser != committedUser || accountChanged) {
        changed = true;
        if (accountChanged) {
          accountActivity.forget(siteUrl);
          groups.forget(siteUrl);
          userDirectory.forget(siteUrl);
          badges.forget(siteUrl);
          _topicTrackingBySite.remove(siteUrl)?.retire();
          _topicTrackingRetries.remove(siteUrl);
        }
        _replaceInstance(
          fresh,
          fresh.copyWith(
            user: committedUser,
            clearNotificationTotals: accountChanged,
          ),
        );
      }
      if (reconciliation.seedGroupedUnreadCounts) {
        _seedGroupedUnreadNotifications(siteUrl, committedUser!);
      }
      _notify();
    });
    if (accepted && changed && lease.isCurrent) {
      instanceStore.save(List.of(_instances)).ignore();
    }
    if (accepted && lease.isCurrent) {
      for (final observer
          in _pluginSession.capabilities<PluginCurrentUserObserver>()) {
        _observePluginLifecycle(
          Future.sync(() => observer.pluginCurrentUserRefreshed(siteUrl)),
          'plugins.session.currentUserRefreshed',
        );
      }
    }
    return accepted ? committedUser : null;
  }

  void _applyUserDraftsMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?>) return;
    final count = jsonIntOrNull(data['draft_count']);
    if (count == null || count < 0) return;

    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null) return;

    _currentUserReconcilerFor(siteUrl).draftCountChanged();

    var current = instance;
    if (user.draftCount != count) {
      current = instance.copyWith(user: user.withDraftCount(count));
      _replaceInstance(instance, current);
      _notify();
      instanceStore.save(List.of(_instances)).ignore();
    }

    final feed = draftList.feedFor(siteUrl);
    if (!feed.loaded && !feed.loading) return;
    // The server can publish the count before the delete response arrives.
    // Keep the existing rows when local deletions already explain the change.
    final total = feed.totalCount;
    final pendingDeletes = feed.drafts
        .where((draft) => draftList.deleting(siteUrl, draft.key))
        .length;
    if (total != null &&
        count <= total &&
        count >= total - pendingDeletes &&
        (count < total || count < user.draftCount)) {
      return;
    }
    draftList.invalidateTotalCount(siteUrl);
    unawaited(draftList.load(current, refresh: true));
  }

  void _seedGroupedUnreadNotifications(String siteUrl, DiscourseUser user) {
    final counts = user.groupedUnreadNotifications;
    if (!counts.isAvailable) return;
    accountActivity.applyGroupedUnreadSnapshot(siteUrl, counts);
  }

  // Only the account's own status is shell state: it lives on the persisted
  // instance record. Everyone else's stays on [userStatuses].
  void _applyUserStatusMessage(String siteUrl, Object? data) {
    var ownStatusChanged = false;
    for (final MapEntry(key: userId, value: status)
        in userStatuses.applyMessage(siteUrl, data).entries) {
      ownStatusChanged =
          _applyOwnUserStatus(siteUrl, userId, status) || ownStatusChanged;
    }
    if (ownStatusChanged) {
      _notify();
      instanceStore.save(List.of(_instances)).ignore();
    }
  }

  bool _applyOwnUserStatus(String siteUrl, int userId, UserStatus? status) {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user == null ||
        user.id != userId ||
        user.status == status) {
      return false;
    }
    _replaceInstance(
      instance,
      instance.copyWith(user: user.withStatus(status)),
    );
    return true;
  }

  DiscourseUser _acceptDoNotDisturbSnapshot(
    String siteUrl,
    DiscourseUser user,
  ) {
    final until = doNotDisturb.acceptSnapshot(siteUrl, user.doNotDisturbUntil);
    return until == user.doNotDisturbUntil
        ? user
        : user.withDoNotDisturbUntil(until);
  }

  void _commitDoNotDisturb(String siteUrl, DateTime? until) {
    if (isDisposed) return;
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null || user.doNotDisturbUntil == until) {
      return;
    }
    _replaceInstance(
      instance,
      instance.copyWith(user: user.withDoNotDisturbUntil(until)),
    );
    _notify();
    instanceStore.save(List.of(_instances)).ignore();
  }

  bool? hidePresenceFor(String siteUrl) =>
      _optimisticHidePresence.containsKey(siteUrl)
      ? _optimisticHidePresence[siteUrl]
      : _instanceAt(siteUrl)?.user?.hidePresence;

  bool hidePresenceWriteInFlight(String siteUrl) =>
      _hidePresenceWrites.containsKey(siteUrl);

  String? hidePresenceErrorFor(String siteUrl) => _hidePresenceErrors[siteUrl];

  Future<void> retryHidePresence(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance?.user == null || hidePresenceFor(siteUrl) != null) return;
    final lease = lifecycle.capture(siteUrl);
    _hidePresenceErrors.remove(siteUrl);
    _notify();

    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final apiKey = credential.apiKey;
      if (apiKey == null) {
        lease.commit(() {
          _hidePresenceErrors[siteUrl] =
              appL10n.reconnectThisAccountToLoadItsPresenceSetting;
          _notify();
        });
        return;
      }
      await _sessionUser(siteUrl, apiKey, lease: lease);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'presence.read',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _hidePresenceErrors[siteUrl] =
            appL10n.couldnTLoadThePresenceSettingTryAgain;
        _notify();
      });
    }
  }

  Future<void> toggleHidePresence(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    final held = hidePresenceFor(siteUrl);
    if (instance == null || user == null || held == null) return;
    if (_hidePresenceWrites.containsKey(siteUrl)) return;

    final desired = !held;
    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    _hidePresenceWrites[siteUrl] = request;
    _optimisticHidePresence[siteUrl] = desired;
    _hidePresenceErrors.remove(siteUrl);
    _currentUserReconcilerFor(siteUrl).presenceWriteStarted();
    _notify();

    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_hidePresenceWrites[siteUrl], request);

    try {
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!isCurrent()) return;
      if (credential.failure case final failure?) {
        _finishHidePresenceWrite(
          siteUrl,
          request,
          lease,
          error: _hidePresenceError(failure),
        );
        return;
      }
      if (!isCurrent()) return;
      await credential.request!.run(
        () => api.site.updateHidePresence(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          username: user.username,
          hidePresence: desired,
          clientId: credential.request!.clientId,
        ),
      );
      if (!isCurrent()) return;
      _finishHidePresenceWrite(siteUrl, request, lease, confirmed: desired);
    } on WriteException catch (error) {
      _finishHidePresenceWrite(
        siteUrl,
        request,
        lease,
        error: _hidePresenceError(error),
      );
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportOperationalError(error, stackTrace, 'presence.update');
      }
      _finishHidePresenceWrite(
        siteUrl,
        request,
        lease,
        error: appL10n.couldnTUpdatePresenceCheckTheConnectionAndTryAgain,
      );
    }
  }

  void _finishHidePresenceWrite(
    String siteUrl,
    Object request,
    SiteLease lease, {
    bool? confirmed,
    String? error,
  }) {
    if (isDisposed ||
        !lease.isCurrent ||
        !identical(_hidePresenceWrites[siteUrl], request)) {
      return;
    }
    lease.commit(() {
      _hidePresenceWrites.remove(siteUrl);
      _optimisticHidePresence.remove(siteUrl);
      _currentUserReconcilerFor(siteUrl).presenceWriteSettled();

      if (error != null) {
        _hidePresenceErrors[siteUrl] = error;
      } else {
        _hidePresenceErrors.remove(siteUrl);
        final instance = _instanceAt(siteUrl);
        final user = instance?.user;
        if (instance != null && user != null && confirmed != null) {
          _replaceInstance(
            instance,
            instance.copyWith(user: user.withHidePresence(confirmed)),
          );
          instanceStore.save(List.of(_instances)).ignore();
        }
      }
      _notify();
    });
  }

  String _hidePresenceError(WriteException error) {
    if (error.errors.isNotEmpty) return error.errors.join('\n');
    return switch (error.failure) {
      WriteFailure.validation => appL10n.theSiteDidnTAcceptThatPresenceSetting,
      WriteFailure.rateLimited => switch (error.retryAfter) {
        final wait? => appL10n.tooFastTryChangingPresenceAgainInS(
          (wait.inSeconds).toString(),
        ),
        null => appL10n.tooFastTryChangingPresenceAgainInAMoment,
      },
      WriteFailure.forbidden =>
        appL10n.presenceCouldNotBeChangedReconnectThisAccountAndTryAgain,
      WriteFailure.conflict =>
        appL10n.presenceChangedSomewhereElseTryAgainToUseThisSetting,
      WriteFailure.unreachable =>
        appL10n.couldnTUpdatePresenceCheckTheConnectionAndTryAgain,
    };
  }

  bool userStatusWriteInFlight(String siteUrl) =>
      _userStatusWrites[siteUrl]?.isCurrent ?? false;

  Future<String?> setUserStatus(
    String siteUrl, {
    required String description,
    required String emoji,
    DateTime? endsAt,
    bool? pauseNotifications,
  }) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user?.id == null ||
        !instance.config.userStatusEnabled) {
      return appL10n.customStatusIsNotAvailableForThisAccount;
    }
    if (userStatusWriteInFlight(siteUrl)) {
      return appL10n.anotherStatusChangeIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    _userStatusWrites[siteUrl] = lease;
    bool ownsWrite() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_userStatusWrites[siteUrl], lease);
    _notify();
    try {
      if (!ownsWrite()) return null;
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!ownsWrite()) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!ownsWrite()) return null;
      if (endsAt != null && !endsAt.isAfter(_clock())) {
        return appL10n.chooseATimeInTheFuture;
      }
      await credential.request!.run(
        () => api.site.setUserStatus(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          description: description,
          emoji: emoji,
          endsAt: endsAt,
          clientId: clientId,
        ),
      );
      if (!ownsWrite()) return null;
      final status = UserStatus(
        description: description.trim(),
        emoji: emoji
            .trim()
            .replaceFirst(RegExp(r'^:'), '')
            .replaceFirst(RegExp(r':$'), ''),
        endsAt: endsAt?.toUtc(),
      );
      lease.commit(() {
        userStatuses.record(siteUrl, user!.id!, status);
        _applyOwnUserStatus(siteUrl, user.id!, status);
        _notify();
        instanceStore.save(List.of(_instances)).ignore();
      });
      if (!ownsWrite()) return null;
      if (pauseNotifications case final pause?) {
        final now = _clock();
        // The status is saved. If it expired during the request, there is no
        // remaining time to pause and no failure to report for that write.
        if (pause && endsAt != null && !endsAt.isAfter(now)) return null;
        final error = pause
            ? await doNotDisturb.pause(
                siteUrl,
                doNotDisturbDurationUntil(
                  endsAt ?? eternalDoNotDisturbUntil,
                  now: now,
                ),
              )
            : await doNotDisturb.resume(siteUrl);
        if (!ownsWrite()) return null;
        if (error != null) return error;
      }
      return null;
    } on WriteException catch (error) {
      if (!ownsWrite()) return null;
      return error.message;
    } catch (error, stackTrace) {
      if (!ownsWrite()) return null;
      _reportOperationalError(error, stackTrace, 'userStatus.set');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_userStatusWrites[siteUrl], lease)) {
        _userStatusWrites.remove(siteUrl);
        if (lease.isCurrent && !isDisposed) _notify();
      }
    }
  }

  Future<String?> clearUserStatus(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user?.id == null ||
        !instance.config.userStatusEnabled) {
      return appL10n.customStatusIsNotAvailableForThisAccount;
    }
    if (userStatusWriteInFlight(siteUrl)) {
      return appL10n.anotherStatusChangeIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    _userStatusWrites[siteUrl] = lease;
    bool ownsWrite() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_userStatusWrites[siteUrl], lease);
    _notify();
    try {
      if (!ownsWrite()) return null;
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!ownsWrite()) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!ownsWrite()) return null;
      await credential.request!.run(
        () => api.site.clearUserStatus(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          clientId: clientId,
        ),
      );
      if (!ownsWrite()) return null;
      lease.commit(() {
        userStatuses.record(siteUrl, user!.id!, null);
        _applyOwnUserStatus(siteUrl, user.id!, null);
        _notify();
        instanceStore.save(List.of(_instances)).ignore();
      });
      if (!ownsWrite()) return null;
      final doNotDisturbError = await doNotDisturb.resume(siteUrl);
      if (!ownsWrite()) return null;
      if (doNotDisturbError != null) return doNotDisturbError;
      return null;
    } on WriteException catch (error) {
      if (!ownsWrite()) return null;
      return error.message;
    } catch (error, stackTrace) {
      if (!ownsWrite()) return null;
      _reportOperationalError(error, stackTrace, 'userStatus.clear');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_userStatusWrites[siteUrl], lease)) {
        _userStatusWrites.remove(siteUrl);
        if (lease.isCurrent && !isDisposed) _notify();
      }
    }
  }

  void _disposeTracking(String siteUrl) {
    final tracker = _trackers.remove(siteUrl);
    tracker?.dispose().ignore();
  }

  /// Writes what a quit would otherwise lose — a tab selection or anchor
  /// still inside its debounce, and each composer's pending draft — and
  /// completes once it is on this device. A desktop quit ends the process
  /// without a lifecycle change, so [setForeground] never runs for it. The
  /// quit may still be cancelled, so nothing is paced down here, and the
  /// sites' copies of the drafts are left to finish on their own.
  Future<void> flushForExit() async {
    if (isDisposed) return;
    _workspace.flushAnchors();
    _workspace.flushSelection();
    for (final composer in _composers) {
      unawaited(composer.flushDraftOnBackground());
    }
    await Future.wait([
      _workspace.writesSettled,
      _composerDrafts.localWritesSettled(),
      destinationBookmarks.flush(),
    ]);
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) _topicData.validatePrefetch();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = foreground ? null : _clock();
    // The OS may suspend the process before a debounce timer fires again.
    if (!foreground) {
      _workspace.flushAnchors();
      for (final composer in _composers) {
        unawaited(composer.flushDraftOnBackground());
      }
    }
    _observePluginLifecycle(
      _pluginSession.setForeground(foreground),
      'plugins.session.setForeground',
    );
    _syncTracking();
    if (!foreground) return;
    doNotDisturb.checkExpirations();

    final resyncTracking =
        backgroundedAt != null &&
        _clock().difference(backgroundedAt) >= _topicTrackingResyncAfter;
    final instance = currentInstance;
    final retainedSiteUrls = _pluginBackgroundSiteUrls;
    for (final entry in _trackers.entries) {
      final selected = entry.key == instance?.url;
      final connected = _instanceAt(entry.key)?.isConnected ?? false;
      if (selected || connected || retainedSiteUrls.contains(entry.key)) {
        entry.value.pollNow();
        _retryTopicTrackingLoad(entry.key);
        if (resyncTracking) _resyncTopicTracking(entry.key);
      }
    }
    // A reader with one forum never reselects it, so returning to the app is
    // its recovery point. Held values answer without a request.
    if (instance != null && (!instance.loginRequired || instance.isConnected)) {
      unawaited(_presentation.warmConfig(instance.url));
      unawaited(_presentation.warmCustomEmojis(instance.url));
      unawaited(_presentation.warmEmojiCatalog(instance.url));
    }
  }

  late final BookmarkTransactions _bookmarks = BookmarkTransactions(
    api: api.bookmarks,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceAt: _instanceAt,
    siteContextFor: bookmarkSiteContextFor,
    pluginStrategies: () =>
        _pluginSession.capabilities<PluginBookmarkTargetStrategy>(),
    topicData: (siteUrl, lease) => _topicData.forLease(siteUrl, lease),
    checklistWriting: (siteUrl, postId) =>
        _postChecklistWrites.containsKey(_postKey(siteUrl, postId)),
    topicSlug: (siteUrl, topicId) {
      final route = currentContent;
      return route?.topicId == topicId
          ? route?.slug ?? ''
          : store.read<Topic>(siteUrl, topicId)?.slug ?? '';
    },
    changes: this,
    changed: _notify,
    refreshMenu: (instance) =>
        accountActivity.loadBookmarks(instance, force: true),
    refreshList: (instance) =>
        accountActivity.refreshLoadedBookmarkList(instance),
    report: (error, stackTrace, operation) =>
        _reportOperationalError(error, stackTrace, operation),
  );

  late final TopicDataOwner _topicData = TopicDataOwner(
    content: api.topicContent,
    feeds: api.topicFeeds,
    models: api.models,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    changed: _notify,
    liveChanged: (siteUrl) {
      if (currentInstance?.url == siteUrl) _notifyLiveChange();
    },
    published: (siteUrl, detail) {
      final changed = _retitle(siteUrl, detail.id, detail.title);
      _armTopicPostHighlightIfLoaded();
      return changed;
    },
    prepareCategories: (siteUrl, ids) async {
      final instance = _instanceAt(siteUrl);
      if (instance != null) await _taxonomy.ensureCategoryIds(instance, ids);
    },
    report: _reportOperationalError,
    loadTimeout: topicLoadTimeout,
    bookmarkReads: (siteUrl, lease) => _bookmarks.forLease(siteUrl, lease)!,
  );
  final Map<String, _QueuedTopicNotification> _topicNotificationWrites = {};
  final Map<String, Future<void>> _topicNotificationTails = {};
  final Map<String, _QueuedCategoryNotification> _categoryNotificationWrites =
      {};
  final Map<String, Future<void>> _categoryNotificationTails = {};
  final Map<String, Future<void>> _categoryNotificationSiteTails = {};
  final Map<String, CategoryNotificationLevel> _categoryNotificationConfirmed =
      {};
  final Set<String> _topicPinWrites = {};
  final Set<String> _topicStatusWrites = {};
  final Set<String> _topicDeletionWrites = {};
  final Map<String, Object> _topicJumpRuns = {};
  final _topicNavigationRevisions = <String?, int>{};
  final _topicListRevealRequests = StreamController<int>.broadcast(sync: true);

  _TopicPostHighlight? _topicPostHighlight;
  Timer? _topicPostHighlightTimer;
  bool _topicPostHighlightVisible = false;

  static const _topicPostHighlightDuration = Duration(milliseconds: 2200);

  static String _topicKey(String siteUrl, int topicId) => '$siteUrl#$topicId';

  static String _categoryKey(String siteUrl, int categoryId) =>
      '$siteUrl^$categoryId';

  TopicDetail? get currentTopic => focusedTabContext.currentTopic;

  bool get currentTopicSummary => focusedTabContext.currentTopicSummary;

  bool get currentTopicSummaryLoading =>
      focusedTabContext.currentTopicSummaryLoading;

  List<int> get currentTopicStreamIds =>
      focusedTabContext.currentTopicStreamIds;

  List<int> get currentPostIds => focusedTabContext.currentPostIds;

  /// The loaded, contiguous run of the open topic's stream, with its bounds.
  ///
  /// The viewport snapshot and the paging flags ask on every shell
  /// notification, so the run is found once per change of its inputs:
  /// finding it reads the store once per loaded post, and every read touches
  /// the store's recency order.

  static const _PostWindow _emptyPostWindow = (
    stream: [],
    range: null,
    ids: [],
  );
  final _postWindowCaches = <(String, String?), _PostWindow>{};
  final _postWindowCacheKeys =
      <(String, String?), (String, TopicDetail, List<int>, int?, int)>{};

  /// Where the topic's saved reading position falls in the loaded window,
  /// counting the "earlier" row that precedes the window when there is one.
  ///
  /// The viewport snapshot asks on every shell notification, and the answer
  /// moves only with the window, the target and that row, so it is kept
  /// against them: resolving it reads the store once per post up to the
  /// target. A window is a new list whenever its inputs change, so its
  /// identity stands for them.
  int? initialPostIndexFor(
    String siteUrl,
    List<int> postIds,
    int target, {
    required bool hasEarlier,
  }) {
    final cached = _initialPostIndexCache;
    if (cached != null &&
        identical(cached.postIds, postIds) &&
        cached.siteUrl == siteUrl &&
        cached.target == target &&
        cached.hasEarlier == hasEarlier) {
      return cached.index;
    }
    int? index;
    for (var i = 0; i < postIds.length; i++) {
      final post = store.read<Post>(siteUrl, postIds[i]);
      // If the named post has since been deleted, reveal the next visible
      // one rather than dropping the reader at the start of the window.
      if (post != null && post.postNumber >= target) {
        index = i + (hasEarlier ? 1 : 0);
        break;
      }
    }
    _initialPostIndexCache = (
      siteUrl: siteUrl,
      postIds: postIds,
      target: target,
      hasEarlier: hasEarlier,
      index: index,
    );
    return index;
  }

  ({
    String siteUrl,
    List<int> postIds,
    int target,
    bool hasEarlier,
    int? index,
  })?
  _initialPostIndexCache;

  List<int> _pendingPostIds(String siteUrl, _PostWindow window, int limit) {
    final stream = window.stream;
    final range = window.range;
    final start = range == null ? 0 : range.$2 + 1;
    final pending = <int>[];
    // One page plus a lookahead tells the caller whether to resolve the
    // final recommendations. Do not scan and allocate the entire unread tail
    // on the UI isolate every time the reader approaches a page boundary.
    for (var index = start; index < stream.length; index++) {
      final id = stream[index];
      if (store.containsRecord<Post>(siteUrl, id)) continue;
      pending.add(id);
      if (pending.length == limit) break;
    }
    return pending;
  }

  /// Whether the stream continues past the loaded window.
  ///
  /// The window is the longest contiguous run of loaded posts, so the post
  /// after it is unloaded by construction, and with no window at all every
  /// post of the stream is still to come.
  bool get currentTopicHasMore => focusedTabContext.currentTopicHasMore;

  bool get currentTopicHasEarlier => focusedTabContext.currentTopicHasEarlier;

  bool get currentTopicLoading => focusedTabContext.currentTopicLoading;

  ({
    String siteUrl,
    int topicId,
    String label,
    ContentRoute route,
    String? tabId,
    int revision,
  })?
  _pendingTopicProperty;
  final _topicPropertyRequests = ChangeNotifier();
  Listenable get topicPropertyRequests => _topicPropertyRequests;

  /// Opens a property once its header is mounted, including after a cold load.
  void requestTopicProperty({
    required String siteUrl,
    required int topicId,
    required String label,
  }) {
    final route = currentContent;
    if (currentInstance?.url != siteUrl || route?.topicId != topicId) return;
    _pendingTopicProperty = (
      siteUrl: siteUrl,
      topicId: topicId,
      label: label,
      route: route!,
      tabId: activeTab?.id,
      revision: topicNavigationRevision,
    );
    _topicPropertyRequests.notifyListeners();
  }

  bool consumeTopicProperty(String siteUrl, int topicId, String label) {
    final request = _pendingTopicProperty;
    if (request == null ||
        request.siteUrl != siteUrl ||
        request.topicId != topicId ||
        request.label != label) {
      return false;
    }
    _pendingTopicProperty = null;
    return true;
  }

  TabOpenResult openTopic(Topic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.lastUnreadPostNumber,
  );

  /// Requests to reveal a topic after list navigation; never replayed.
  Stream<int> get topicListRevealRequests => _topicListRevealRequests.stream;

  TabOpenResult openTopicFromList(Topic topic, {bool revealInList = false}) =>
      focusedTabContext.openTopicFromList(topic, revealInList: revealInList);

  void openSummaryTopic(UserSummaryTopic topic, {int? postNumber}) =>
      _openTopic(
        topic.id,
        topic.slug,
        topic.title,
        postNumber: postNumber != null && postNumber > 0 ? postNumber : null,
      );

  void openFeaturedTopic(CategoryFeaturedTopic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.firstUnreadPostNumber,
  );

  void openCategory(TopicCategory category, {String? siteUrl}) {
    final targetSiteUrl = siteUrl ?? currentInstance?.url;
    if (targetSiteUrl == null) return;
    final index = _instances.indexWhere(
      (instance) => instance.url == targetSiteUrl,
    );
    if (index < 0) return;
    if (index != _instanceIndex || _rootMode != ShellRootMode.forum) {
      selectInstance(index);
    }
    if (currentInstance?.url != targetSiteUrl) return;

    store.put(targetSiteUrl, category);
    final categories = _taxonomy.categoriesFor(targetSiteUrl);
    final byId = <int, TopicCategory>{
      for (final item in categories) item.id: item,
      category.id: category,
    };
    final route = ContentRoute.fromDestination(
      buildCategoryDestination(category, categoriesById: byId),
    );
    if (route.sameDestinationAs(currentContent)) {
      showPluginContent();
      return;
    }
    pushContent(route);
    unawaited(loadFeed(route.id));
  }

  void openTag(SidebarTag tag) {
    final instance = currentInstance;
    if (instance == null) return;
    final destination = buildTagDestination(
      tag,
      username: instance.user?.username,
    );
    if (destination == null) return;
    final route = ContentRoute.fromDestination(destination);
    if (route.sameDestinationAs(currentContent)) return;
    pushContent(route);
    unawaited(loadFeed(route.id));
  }

  Future<bool> openTopicTag(
    TopicTag tag, {
    required String siteUrl,
    bool privateMessage = false,
    bool newTab = false,
    ForumPanel? panel,
  }) async {
    var resolvedTag = _topicTagWithKnownIdentity(siteUrl, tag);
    final isPrivateMessage =
        privateMessage ||
        resolvedTag.pmOnly ||
        _isKnownPrivateMessageOnlyTag(siteUrl, resolvedTag);
    if (!isPrivateMessage &&
        resolvedTag.id == null &&
        int.tryParse(resolvedTag.name.trim()) != null) {
      final source = (
        rootMode: _rootMode,
        instanceUrl: currentInstance?.url,
        tabId: activeTabId,
        destinationIdentity: currentContent?.destination.identity,
        stackDepth: contentStack.length,
        mobilePane: _mobilePane,
      );
      final lease = lifecycle.capture(siteUrl);
      final found = await searchHashtags(
        siteUrl: siteUrl,
        term: resolvedTag.name,
      );
      if (!lease.isCurrent ||
          isDisposed ||
          _rootMode != source.rootMode ||
          currentInstance?.url != source.instanceUrl ||
          activeTabId != source.tabId ||
          currentContent?.destination.identity != source.destinationIdentity ||
          contentStack.length != source.stackDepth ||
          _mobilePane != source.mobilePane) {
        return false;
      }
      final normalizedName = resolvedTag.name.trim().toLowerCase();
      final match = found.where((candidate) {
        if (candidate.type != 'tag' || candidate.id <= 0) return false;
        return candidate.slug.trim().toLowerCase() == normalizedName ||
            candidate.text.trim().toLowerCase() == normalizedName;
      }).firstOrNull;
      if (match == null) return false;
      resolvedTag = _topicTagWithIdentity(
        resolvedTag,
        id: match.id,
        slug: match.slug,
      );
    }

    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return false;

    final instance = _instances[index];
    final destination = buildTopicTagDestination(
      resolvedTag,
      username: instance.user?.username,
      privateMessage: isPrivateMessage,
    );
    if (destination == null) return false;

    final requestedPanel =
        panel ??
        (desktopPanelsEnabled && HardwareKeyboard.instance.isShiftPressed
            ? ForumPanel.secondary
            : null);

    if (newTab && forumTabsEnabled) {
      return openContentInNewTab(
            ContentRoute.fromDestination(destination),
            siteUrl: siteUrl,
            panel: requestedPanel ?? activeTab?.panel,
            select: false,
          ) ==
          TabOpenResult.opened;
    }

    if (index != _instanceIndex || _rootMode != ShellRootMode.forum) {
      selectInstance(index);
    }
    if (currentInstance?.url != siteUrl) return false;

    final route = ContentRoute.fromDestination(destination);
    if (desktopPanelsEnabled && requestedPanel != null) {
      return openContentInPanel(route, panel: requestedPanel) ==
          TabOpenResult.opened;
    }
    if (route.sameDestinationAs(currentContent)) {
      showPluginContent();
      return true;
    }
    pushContent(route);
    unawaited(loadFeed(route.id));
    return true;
  }

  TopicTag _topicTagWithKnownIdentity(String siteUrl, TopicTag topicTag) {
    if (topicTag.id case final id? when id > 0) return topicTag;
    final known = _taxonomy.knownTopicTag(siteUrl, topicTag);
    if (known == null) return topicTag;
    return _topicTagWithIdentity(
      topicTag,
      id: known.id,
      slug: known.slug,
      pmOnly: topicTag.pmOnly || known.pmOnly,
    );
  }

  TopicTag _topicTagWithIdentity(
    TopicTag tag, {
    required int id,
    required String slug,
    bool? pmOnly,
  }) => TopicTag(
    id: id,
    name: tag.name,
    slug: slug,
    pmOnly: pmOnly ?? tag.pmOnly,
    count: tag.count,
    disabled: tag.disabled,
    disabledReason: tag.disabledReason,
  );

  bool _isKnownPrivateMessageOnlyTag(String siteUrl, TopicTag topicTag) =>
      _taxonomy.knownTopicTag(siteUrl, topicTag)?.pmOnly == true;

  void openSearchResult(SearchPostHit hit, {String words = ''}) {
    search.clear();
    if (currentContent?.topicId == hit.topicId) {
      search.setPageWords(
        currentInstance!.url,
        activeTabId,
        'topic-${hit.topicId}',
        words,
      );
      openTopicPost(
        siteUrl: currentInstance!.url,
        topicId: hit.topicId,
        postNumber: hit.postNumber,
        highlight: true,
      );
      return;
    }
    _openTopic(
      hit.topicId,
      hit.topicSlug,
      hit.topicTitle,
      postNumber: hit.postNumber,
      resetScrollPosition: true,
    );
    final site = currentInstance?.url;
    if (site != null) {
      search.setPageWords(site, activeTabId, 'topic-${hit.topicId}', words);
      _requestTopicPostHighlight(
        siteUrl: site,
        topicId: hit.topicId,
        postNumber: hit.postNumber,
      );
    }
  }

  /// The shared field applies to the focused list and preserves its mode.
  void applySearchToList(
    String words,
    List<GlobalSearchCondition> conditions, {
    bool clearFilters = false,
  }) {
    final site = currentInstance?.url;
    if (site == null) return;
    final source = currentContent;
    final keepMessages =
        source?.isMessages == true &&
        !conditions.any(
          (condition) =>
              condition.filterId == 'privateMessages' &&
              condition.text == 'all',
        );
    final mode = currentTopicListMode ?? TopicListMode.latest;
    var base = !clearFilters && keepMessages
        ? ContentRoute.messages(
            groupName: source?.messageGroupName,
            mode: source!.messageListMode,
          )
        : ContentRoute.topicList(mode);
    if (!clearFilters &&
        source?.isMessages != true &&
        source?.isSearchList != true &&
        source?.isAdvancedTopicFilter != true) {
      base = base.withTopicListQueryFrom(source);
    }
    ContentRoute route;
    if (conditions.isEmpty) {
      route = base.withTopicListSearch(words);
    } else if (source?.isMessages != true &&
        conditions.every(
          (condition) =>
              condition.filterId == 'category' &&
                  condition.operator == 'any' &&
                  condition.value.length == 1 &&
                  int.tryParse(condition.text) != null ||
              condition.filterId == 'tags' &&
                  (condition.operator == 'all' ||
                      condition.operator == 'any' &&
                          condition.value.length == 1),
        )) {
      final category = conditions
          .where((condition) => condition.filterId == 'category')
          .firstOrNull;
      final tags = conditions
          .where((condition) => condition.filterId == 'tags')
          .firstOrNull;
      route = ContentRoute.filteredTopicList(
        mode,
        categoryId: category == null ? null : int.parse(category.text),
        tags: tags?.value ?? const [],
      ).withTopicListQueryFrom(base).withTopicListSearch(words);
    } else {
      final expression = [
        words,
        if (keepMessages) 'in:personal',
        if (keepMessages && source?.messageGroupName != null)
          'group_messages:${source!.messageGroupName}',
        for (final condition in conditions)
          globalSearchConditionToken(
            condition,
            capabilities: globalSearch.capabilities,
            username: globalSearch.capabilities.username,
          ),
      ].where((part) => part.isNotEmpty).join(' ');
      route = ContentRoute.searchList(
        expression,
        groupName: source?.messageGroupName,
        messageMode: keepMessages ? MessageListMode.inbox : null,
      );
    }
    _publishTopicListSearchRoute(site, route, words);
  }

  void _publishTopicListSearchRoute(
    String siteUrl,
    ContentRoute route,
    String words,
  ) {
    _replaceTopicListContent(route, keepTopicOpen: false);
    search.setPageWords(siteUrl, activeTabId, route.id, words);
    _syncTopicChannels();
    _notify();
    unawaited(loadFeed(route.id));
  }

  void clearSearchWords() {
    final route = currentContent;
    if (route == null || !route.isTopicList) return;
    if (route.isSearchList) {
      final expression = parseGlobalSearchExpression(
        Uri.parse(route.feedPath!).queryParameters['q'] ?? '',
        GlobalSearchScope.forum,
        globalSearch.capabilities,
      );
      final conditions = [
        ...expression.conditions,
        if (expression.order case final order? when order != 'relevance')
          GlobalSearchCondition(filterId: 'order', value: [order]),
      ];
      applySearchToList('', conditions, clearFilters: conditions.isEmpty);
    } else if (route.isAdvancedTopicFilter) {
      applySearchToList('', const []);
    } else {
      final site = currentInstance?.url;
      if (site == null) return;
      _publishTopicListSearchRoute(site, route.withTopicListSearch(''), '');
    }
  }

  void openUserActivityItem(UserActivityItem item) => _openTopic(
    item.topicId,
    item.slug,
    item.title,
    postNumber: item.postNumber,
  );

  TabOpenResult _openTopic(
    int topicId,
    String slug,
    String title, {
    int? postNumber,
    bool force = false,
    bool replace = false,
    bool resetScrollPosition = false,
    ShellTabContext? context,
  }) {
    // A fast double tap on a row pushes the same topic twice — the fetch is
    // deduped below, but the second route still costs a back tap.
    final document = context ?? focusedTabContext;
    if (!identical(document.shell, this) || !document.isCurrent) {
      return TabOpenResult.unsupported;
    }
    if (currentInstance == null) return TabOpenResult.unsupported;
    if (document.currentContent?.topicId == topicId) {
      return TabOpenResult.opened;
    }
    final source = document.currentContent;
    final sourceWords =
        source?.isTopicList == true &&
            topicFeeds
                    .feedFor(currentInstance!.url, source!.id)
                    ?.topicIds
                    .contains(topicId) ==
                true
        ? search.wordsFor(currentInstance!.url, document.tabId, source.id)
        : '';
    SurfaceOpeningTrace.mark('topic.request');
    if (currentInstance case final instance?) {
      _topicData.forSite(instance.url).clearSummary(topicId);
    }
    final route = ContentRoute.topic(
      topicId: topicId,
      slug: slug,
      title: title,
      postNumber: postNumber,
    );
    // An explicit post destination supersedes the last reading position from
    // an earlier visit to this topic in the same tab.
    final tab = document.tab;
    if (resetScrollPosition &&
        tab != null &&
        tab.anchors.containsKey(route.id)) {
      _workspace.replaceTab(
        document.siteUrl!,
        tab.copyWith(
          anchors: Map<String, ForumTabAnchor>.of(tab.anchors)
            ..remove(route.id),
        ),
        persist: false,
      );
    }
    String? destinationTabId;
    if (context != null && document.tabId != activeTabId) {
      if (!replace &&
          desktopPanelsEnabled &&
          tab?.panel != ForumPanel.secondary) {
        final result = openContentInPanel(
          route,
          panel: ForumPanel.secondary,
          context: document,
        );
        if (result != TabOpenResult.opened) return result;
        destinationTabId = selectedTabIn(ForumPanel.secondary)?.id;
      } else {
        final sourceTab = document.tab!;
        final replacement = replace
            ? sourceTab.navigate(
                contentStack: [
                  ...sourceTab.contentStack.take(
                    sourceTab.contentStack.length - 1,
                  ),
                  route,
                ],
              )
            : sourceTab.push(route);
        _workspace.consumeHomepage(replacement.id);
        _workspace.replaceTab(document.siteUrl!, replacement);
        _setForumContentRoot();
        _mobilePane = MobilePane.content;
        _syncTopicChannels();
        _notify();
        destinationTabId = replacement.id;
      }
    } else {
      if (replace) {
        replaceCurrentContent(route);
      } else {
        pushContent(route);
      }
      destinationTabId = activeTabId;
    }
    if (sourceWords.isNotEmpty) {
      search.setPageWords(
        currentInstance!.url,
        destinationTabId,
        route.id,
        sourceWords,
      );
    }
    unawaited(
      tabContext(
        destinationTabId,
      ).loadTopic(topicId, slug, force: force, postNumber: postNumber),
    );
    return TabOpenResult.opened;
  }

  String absoluteUrl(String url, {String? siteUrl}) =>
      resolveSiteUrl(url, siteUrl ?? currentInstance?.url);

  /// [path], a root path this app builds, on [siteUrl] or the current forum;
  /// see [resolveSiteRootPath]. Without a forum it is returned as it is.
  String siteLink(String path, {String? siteUrl}) {
    final site = siteUrl ?? currentInstance?.url;
    return site == null ? path : resolveSiteRootPath(site, path);
  }

  /// Builds a topic-list action without waiting for the topic request.
  BookmarkLinkAction? cachedTopicBookmarkLink(String url) {
    final target = Uri.tryParse(url);
    if (target == null || !{'http', 'https'}.contains(target.scheme)) {
      return null;
    }
    final instance = mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (site) => site.url,
    )?.forum;
    if (instance == null || !instance.isConnected || instance.user == null) {
      return null;
    }
    final siteUrl = instance.url;
    final link = TopicLink.parse(url, siteUrl: siteUrl);
    if (link == null || link.postNumber != null) return null;
    final topic = store.read<Topic>(siteUrl, link.topicId);
    if (topic == null ||
        bookmarkWriteInFlight(
          siteUrl: siteUrl,
          topicId: link.topicId,
          targetType: BookmarkTargetType.topic,
          targetId: link.topicId,
        )) {
      return null;
    }
    final detail = store.read<TopicDetail>(siteUrl, link.topicId);
    if (topic.bookmarked && detail == null) {
      // The list's flag also includes post bookmarks, so it cannot tell us
      // whether this topic bookmark exists or supply its deletion ID.
      final resolution = resolveBookmarkLink(url);
      return BookmarkLinkAction(
        bookmark: null,
        resolution: resolution,
        invoke: () async {
          final action = await resolution;
          return action == null
              ? BookmarkWriteResult.refused(appL10n.bookmarkChangedRefreshMenu)
              : action.invoke();
        },
      );
    }
    return _bookmarkLinkAction(
      siteUrl: siteUrl,
      topicId: link.topicId,
      type: BookmarkTargetType.topic,
      targetId: link.topicId,
      bookmark: topic.bookmarked ? detail?.topicBookmark : null,
    );
  }

  BookmarkLinkAction _bookmarkLinkAction({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType type,
    required int targetId,
    required Bookmark? bookmark,
  }) {
    final lease = lifecycle.capture(siteUrl);
    final bookmarkCurrent = _bookmarks.forSite(siteUrl).guard(topicId);
    return BookmarkLinkAction(
      bookmark: bookmark,
      invoke: () async {
        if (!lease.isCurrent || !bookmarkCurrent()) {
          return BookmarkWriteResult.refused(
            appL10n.bookmarkChangedRefreshMenu,
          );
        }
        final host = bookmarkTarget(type);
        return bookmark == null
            ? host.createBookmark(
                siteUrl: siteUrl,
                topicId: topicId,
                targetId: targetId,
              )
            : host.deleteBookmark(
                siteUrl: siteUrl,
                topicId: topicId,
                bookmark: bookmark,
              );
      },
    );
  }

  /// Resolves the clicked link without selecting its forum, tab, or topic.
  Future<BookmarkLinkAction?> resolveBookmarkLink(
    String url, {
    Bookmark? targetBookmark,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null || !{'http', 'https'}.contains(target.scheme)) {
      return null;
    }
    final instance = mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (site) => site.url,
    )?.forum;
    if (instance == null || !instance.isConnected || instance.user == null) {
      return null;
    }
    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    try {
      final link = TopicLink.parse(url, siteUrl: siteUrl);
      if (link == null) {
        for (final resolver
            in _pluginSession.capabilities<PluginBookmarkLinkResolver>()) {
          final action = await resolver.resolveBookmarkLink(siteUrl, url);
          if (!lease.isCurrent) return null;
          if (action != null) return action;
        }
        return null;
      }
      if (targetBookmark != null && targetBookmark.coreTargetType == null) {
        return null;
      }
      final bookmarkCurrent = _bookmarks.forSite(siteUrl).guard(link.topicId);
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (credential.apiKey == null || !lease.isCurrent) return null;
      final payload = await credential.run(
        () => api.topicContent.topic(
          siteUrl: siteUrl,
          slug: link.slug,
          id: link.topicId,
          postNumber: link.postNumber,
          apiKey: credential.apiKey,
        ),
      );
      if (!lease.isCurrent ||
          payload.detail.id != link.topicId ||
          !bookmarkCurrent()) {
        return null;
      }
      final topicTarget =
          targetBookmark?.coreTargetType == BookmarkTargetType.topic ||
          (targetBookmark == null && link.postNumber == null);
      final post = topicTarget
          ? null
          : payload.posts
                .where(
                  (post) => targetBookmark?.bookmarkableId != null
                      ? post.id == targetBookmark!.bookmarkableId
                      : post.postNumber == link.postNumber,
                )
                .firstOrNull;
      if (!topicTarget && (post == null || post.isDeleted || post.hidden)) {
        return null;
      }
      if (topicTarget &&
          targetBookmark?.bookmarkableId != null &&
          targetBookmark!.bookmarkableId != link.topicId) {
        return null;
      }
      final type = topicTarget
          ? BookmarkTargetType.topic
          : BookmarkTargetType.post;
      final targetId = topicTarget ? link.topicId : post!.id;
      final bookmark = topicTarget
          ? payload.detail.topicBookmark
          : post!.bookmark;
      if (bookmarkWriteInFlight(
        siteUrl: siteUrl,
        topicId: link.topicId,
        targetType: type,
        targetId: targetId,
      )) {
        return null;
      }
      return _bookmarkLinkAction(
        siteUrl: siteUrl,
        topicId: link.topicId,
        type: type,
        targetId: targetId,
        bookmark: bookmark,
      );
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'bookmark.resolveLink',
          severity: DiagnosticSeverity.warning,
        );
      }
      return null;
    }
  }

  bool openTopicUrl(String url) => _openTopicUrl(url);

  TabOpenResult openLinkInNewTab(
    String url, {
    String? title,
    ForumPanel? panel,
    int? index,
  }) {
    final destination = _routeForLink(url, title: title);
    if (destination == null) return TabOpenResult.unsupported;
    return openContentInNewTab(
      destination.route,
      siteUrl: destination.siteUrl,
      panel: panel,
      index: index,
      select: false,
      source: currentInstance?.url == destination.siteUrl ? activeTab : null,
    );
  }

  TabOpenResult openLinkInPanel(
    String url, {
    String? title,
    required ForumPanel panel,
  }) {
    final destination = _routeForLink(url, title: title);
    if (destination == null) return TabOpenResult.unsupported;
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    if (index != _instanceIndex) selectInstance(index);
    return openContentInPanel(
      destination.route,
      panel: panel,
      resetScrollPosition: destination.route.postNumber != null,
    );
  }

  ({ContentRoute route, String siteUrl})? _routeForLink(
    String url, {
    String? title,
  }) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return null;
    final instance = mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (site) => site.url,
    )?.forum;
    if (instance == null) return null;

    final ContentRoute? decoded;
    if (const {'', '/'}.contains(instance.pathWithin(target)) &&
        !target.hasQuery &&
        !target.hasFragment) {
      decoded = _homepageFor(instance);
    } else {
      decoded = ContentRouteCodec.fromUrl(
        absolute,
        instance: instance,
        config: siteConfigFor(instance.url),
        defaultTopPeriod: _defaultTopPeriodFor(instance.url),
        title: title,
      );
    }
    if (decoded == null) return null;
    final category = categoryFor(decoded.categoryId, siteUrl: instance.url);
    final route =
        (category == null
                ? decoded
                : decoded.withDisplay(color: Color(category.colorValue)))
            .resolveCategoryLink(filterCategoriesFor(instance.url));
    return (route: route, siteUrl: instance.url);
  }

  bool openBadgeUrl(String url, {String? title, bool refresh = false}) {
    final destination = _routeForLink(url, title: title);
    if (destination == null ||
        destination.route.destination is! BadgeDestination) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    final instance = _instances[index];
    final route = (destination.route.destination as BadgeDestination).route;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.badgeRoute != route) {
      pushContent(destination.route);
    } else if (rootChanged) {
      _notify();
    }
    unawaited(badges.load(instance, route, refresh: refresh));
    return true;
  }

  bool openGroupUrl(String url) {
    final destination = _routeForLink(url);
    if (destination == null ||
        destination.route.destination is! GroupDestination) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    final route = (destination.route.destination as GroupDestination).route;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.groupRoute == route) {
      if (rootChanged) _notify();
      return true;
    }

    final content = destination.route;
    pushContent(content);
    if (content.feedPath != null) unawaited(loadFeed(content.id));
    return true;
  }

  bool _openTopicUrl(String url, {bool refresh = false}) {
    final destination = _routeForLink(url);
    if (destination == null ||
        destination.route.destination is! TopicDestination) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    final link = destination.route.destination as TopicDestination;

    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();

    // Posts link to the topic they are already in — every cross-post quote
    // does — and stacking a second copy of it only costs the user a back tap,
    // so a link naming a post moves the open reader to it instead, and a bare
    // topic link leaves the reading position alone. A notification is
    // different: it reports a change that happened after the post may have
    // entered the store, so its target has to be read again.
    if (currentContent?.topicId == link.topicId) {
      final postNumber = refresh ? link.postNumber ?? 1 : link.postNumber;
      if (postNumber != null) {
        openCurrentTopicPost(postNumber, loadAroundPost: refresh);
      } else if (rootChanged) {
        _notify();
      }
      return true;
    }

    _openTopic(
      link.topicId,
      link.slug ?? '',
      destination.route.title,
      postNumber: link.postNumber,
      force: refresh,
      resetScrollPosition: link.postNumber != null,
    );
    return true;
  }

  void openCurrentTopicPost(int postNumber, {bool loadAroundPost = false}) {
    final target = _targetCurrentTopicPost(postNumber);
    if (target == null) return;
    unawaited(
      loadTopic(
        target.topicId,
        target.slug,
        force: loadAroundPost,
        postNumber: postNumber,
      ),
    );
  }

  ({int topicId, String slug})? _targetCurrentTopicPost(
    int postNumber, {
    ShellTabContext? context,
    int? topicId,
  }) {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent) return null;
    final route = document.currentContent;
    if (topicId != null && route?.topicId != topicId) return null;
    final tab = document.tab;
    if (route?.topicId case final topicId? when tab != null && postNumber > 0) {
      final anchors = Map<String, ForumTabAnchor>.of(tab.anchors)
        ..remove(route!.id);
      final targeted = ContentRoute(
        destination: TopicDestination(
          topicId: topicId,
          slug: route.slug,
          postNumber: postNumber,
          legacyKey: route.id,
          retainedFeedPath: route.feedPath,
        ),
        title: route.title,
        icon: route.icon,
        subtitle: route.subtitle,
        color: route.color,
      );
      _topicNavigationRevisions[tab.id] = document.topicNavigationRevision + 1;
      _workspace.replaceTab(
        document.siteUrl!,
        tab.copyWith(
          contentStack: [
            ...tab.contentStack.take(tab.contentStack.length - 1),
            targeted,
          ],
          anchors: anchors,
        ),
      );
      _notify();
      return (topicId: topicId, slug: route.slug ?? '');
    }
    return null;
  }

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {
    if (postNumber <= 0) return;
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    _setForumContentRoot();
    if (highlight) {
      _requestTopicPostHighlight(
        siteUrl: siteUrl,
        topicId: topicId,
        postNumber: postNumber,
      );
    } else {
      _clearTopicPostHighlight(notify: false);
    }
    if (currentContent?.topicId == topicId) {
      openCurrentTopicPost(postNumber, loadAroundPost: true);
      return;
    }
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final row = store.read<Topic>(siteUrl, topicId);
    _openTopic(
      topicId,
      row?.slug ?? '',
      detail?.title ?? row?.title ?? appL10n.topic,
      postNumber: postNumber,
    );
  }

  bool isTopicPostHighlighted(String siteUrl, int topicId, int postNumber) {
    final highlight = _topicPostHighlight;
    return _topicPostHighlightVisible &&
        highlight?.tabId == activeTabId &&
        highlight?.siteUrl == siteUrl &&
        highlight?.topicId == topicId &&
        highlight?.postNumber == postNumber;
  }

  void _requestTopicPostHighlight({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) {
    _topicPostHighlightTimer?.cancel();
    _topicPostHighlight = (
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      tabId: activeTabId,
    );
    _topicPostHighlightVisible = false;
    // Do not let a failed target load leave a latent highlight that appears
    // during unrelated navigation much later.
    _topicPostHighlightTimer = Timer(
      topicLoadTimeout,
      _clearTopicPostHighlight,
    );
    _armTopicPostHighlightIfLoaded();
  }

  void _armTopicPostHighlightIfLoaded() {
    final highlight = _topicPostHighlight;
    if (highlight == null || _topicPostHighlightVisible) return;
    final topic = store.read<TopicDetail>(highlight.siteUrl, highlight.topicId);
    final targetLoaded = topic?.stream.any(
      (postId) =>
          store.read<Post>(highlight.siteUrl, postId)?.postNumber ==
          highlight.postNumber,
    );
    if (targetLoaded != true) return;

    _topicPostHighlightVisible = true;
    _topicPostHighlightTimer?.cancel();
    _topicPostHighlightTimer = Timer(
      _topicPostHighlightDuration,
      _clearTopicPostHighlight,
    );
  }

  void _clearTopicPostHighlight({bool notify = true}) {
    final changed = _topicPostHighlight != null;
    _topicPostHighlightTimer?.cancel();
    _topicPostHighlightTimer = null;
    _topicPostHighlight = null;
    _topicPostHighlightVisible = false;
    if (changed && notify && !isDisposed) _notify();
  }

  int get topicNavigationRevision => focusedTabContext.topicNavigationRevision;

  /// Opens the post at progress position [index], counted from one: its place
  /// in the stream, or in a mega topic, whose stream is only the run read so
  /// far, its post number (TopicViewportSnapshot.progressTotal).
  Future<bool> jumpToCurrentTopicIndex(int index) async {
    final instance = currentInstance;
    final route = currentContent;
    final topic = currentTopic;
    final tabId = activeTabId;
    final navigationRevision = topicNavigationRevision;
    if (instance == null ||
        route?.topicId == null ||
        topic == null ||
        tabId == null ||
        currentTopicStreamIds.isEmpty) {
      return false;
    }
    if (topic.isMegaTopic && !currentTopicSummary) {
      // Read around the number, as the web client's timeline jumps: a held
      // post opens at once, and a number no post has opens the one after.
      openCurrentTopicPost(math.max(index, 1));
      return true;
    }

    final stream = currentTopicStreamIds;
    final boundedIndex = index.clamp(1, stream.length);
    final targetId = stream[boundedIndex - 1];
    final key = _topicKey(instance.url, topic.id);
    final token = Object();
    final lease = lifecycle.capture(instance.url);
    _topicJumpRuns[key] = token;

    bool isCurrent() =>
        identical(_topicJumpRuns[key], token) &&
        lease.isCurrent &&
        !isDisposed &&
        topicNavigationRevision == navigationRevision &&
        activeTabId == tabId &&
        currentInstance?.url == instance.url &&
        currentContent?.topicId == topic.id;

    try {
      var target = store.read<Post>(instance.url, targetId);
      final loadAroundPost = target == null;
      if (target == null) {
        target = await _topicData
            .forLease(instance.url, lease)
            ?.ensurePost(topic.id, targetId, isInterested: isCurrent);
        if (target == null) return false;
      }
      if (!isCurrent()) return false;
      openCurrentTopicPost(target.postNumber, loadAroundPost: loadAroundPost);
      return true;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.jumpToIndex',
          severity: DiagnosticSeverity.warning,
        );
      }
      return false;
    } finally {
      if (identical(_topicJumpRuns[key], token)) {
        final _ = _topicJumpRuns.remove(key);
      }
    }
  }

  bool openCorePageUrl(String url) {
    final destination = _routeForLink(url);
    if (destination == null) return false;
    final route = destination.route;
    final page = ContentPageContract.resolve(route);
    final supported = switch (page.coreUrl) {
      CoreUrlPolicy.direct => true,
      CoreUrlPolicy.registeredHomepage =>
        plugins.registry.homepage(route.id) != null,
      CoreUrlPolicy.specialized => false,
    };
    if (!supported) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    if (index < 0) return false;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (route.sameDestinationAs(currentContent)) {
      _workspace.consumeHomepage(activeTabId);
      if (rootChanged) _notify();
      return true;
    }
    pushContent(route);
    unawaited(_loadPage(focusedTabContext, route, page.urlLoad));
    return true;
  }

  bool openListUrl(String url, {String? title}) {
    final destination = _routeForLink(url, title: title);
    if (destination == null || !destination.route.isTaxonomyList) return false;
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );

    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();

    final route = destination.route;

    if (route.sameDestinationAs(currentContent)) {
      if (rootChanged) _notify();
      return true;
    }

    pushContent(route);
    // In the same turn as the push, so the main region never draws a route
    // whose feed does not exist yet — that is the placeholder screen, and it
    // would flash in before the list arrived.
    unawaited(loadFeed(route.id));
    return true;
  }

  /// Starts a speculative load after a short pointer dwell. The row releases
  /// its interest on exit/removal; a real topic load adopts the response first.
  void Function() hoverTopic(String siteUrl, Topic topic) =>
      prefetchTopic(siteUrl, topic);

  void Function() prefetchTopic(
    String siteUrl,
    Topic topic, {
    TopicPrefetchIntent intent = TopicPrefetchIntent.hover,
    bool Function()? isInterested,
  }) {
    final instance = currentInstance;
    if (isDisposed ||
        !_foreground ||
        instance == null ||
        instance.url != siteUrl ||
        rootMode != ShellRootMode.forum ||
        (instance.loginRequired && !instance.isConnected) ||
        readingTopicId == topic.id) {
      return () {};
    }
    final origin = (
      activeTabId,
      currentContent?.destination.identity,
      topicListContent?.destination.identity,
    );
    final postNumber = topic.lastUnreadPostNumber;
    return _topicData
        .forSite(siteUrl)
        .prefetch(
          topic,
          intent: intent,
          isInterested: () =>
              !isDisposed &&
              (isInterested?.call() ?? true) &&
              _foreground &&
              currentInstance?.url == siteUrl &&
              rootMode == ShellRootMode.forum &&
              ((
                        activeTabId,
                        currentContent?.destination.identity,
                        topicListContent?.destination.identity,
                      ) ==
                      origin ||
                  (currentContent?.topicId == topic.id &&
                      currentContent?.postNumber == postNumber)),
        );
  }

  Future<void> loadTopic(
    int topicId,
    String slug, {
    bool force = false,
    int? postNumber,
    ShellTabContext? context,
  }) => DiagnosticsSink.runOperation(
    'topic.load',
    () => _loadTopic(
      topicId,
      slug,
      force: force,
      postNumber: postNumber,
      context: context ?? focusedTabContext,
    ),
  );

  Future<void> _loadTopic(
    int topicId,
    String slug, {
    required bool force,
    int? postNumber,
    required ShellTabContext context,
  }) async {
    if (!identical(context.shell, this) || !context.isCurrent) return;
    final instance = currentInstance;
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      return;
    }
    final requested =
        postNumber ?? topicScrollPostNumber(topicId, tabId: context.tabId);
    final data = _topicData.forSite(instance.url);
    unawaited(
      RequestIntent.background().run(
        () => _presentation.ensureConfig(instance.url),
      ),
    );
    unawaited(
      RequestIntent.background().run(
        () => _presentation.ensureCustomEmojis(instance.url),
      ),
    );
    unawaited(
      RequestIntent.background().run(
        () => _taxonomy.ensureCategoriesFor(
          instance,
          categoryId: store
              .read<TopicDetail>(instance.url, topicId)
              ?.categoryId,
        ),
      ),
    );
    await data.open(
      topicId,
      slug: slug,
      postNumber: requested,
      force: force,
      opening: TopicOpening(
        received: (detail) =>
            _ensureMessageListParent(instance.url, context.tabId, detail),
        canResume: () =>
            context.isCurrent &&
            context.currentContent?.topicId == topicId &&
            topicScrollPostNumber(topicId, tabId: context.tabId) == null,
        resume: (number) {
          final target = _targetCurrentTopicPost(
            number,
            context: context,
            topicId: topicId,
          );
          return target == null
              ? null
              : (slug: target.slug, postNumber: number);
        },
      ),
    );
  }

  void _ensureMessageListParent(
    String siteUrl,
    String? tabId,
    TopicDetail detail,
  ) {
    if (!detail.privateMessage) return;
    final workspace = _workspace.forSite(siteUrl);
    final tab = workspace?.tabs.where((tab) => tab.id == tabId).firstOrNull;
    if (workspace == null ||
        tab == null ||
        tab.currentContent.topicId != detail.id) {
      return;
    }
    final parent = tab.contentStack.reversed
        .where((route) => !route.isTopic)
        .firstOrNull;
    if (parent?.isMessages == true ||
        (parent?.destination is ExtensionDestination &&
            plugins.registry.plugins
                .whereType<PrivateMessageSourcePlugin>()
                .any((plugin) => plugin.ownsPrivateMessageSource(parent!)))) {
      return;
    }

    final messages = ContentRoute.messages();
    _workspace.put(
      workspace.copyWith(
        tabs: [
          for (final candidate in workspace.tabs)
            if (candidate.id == tab.id)
              tab.copyWith(
                rootDestinationId: messages.id,
                contentStack: [messages, tab.currentContent],
                // A PM discovered after loading still returns to its inbox,
                // while retaining visits before it and any forward history.
                backHistory: [
                  ...tab.backHistory.skip(
                    tab.backHistory.length == ForumTab.maximumHistoryEntries
                        ? 1
                        : 0,
                  ),
                  ForumTabLocation(
                    rootDestinationId: messages.id,
                    contentStack: [messages],
                  ),
                ],
              )
            else
              candidate,
        ],
      ),
    );
    if (currentInstance?.url == siteUrl && activeTabId == tabId) {
      unawaited(loadFeed(messages.id));
    }
  }

  /// Whether any route of the topic changed.
  bool _retitle(String siteUrl, int topicId, String title) {
    if (title.isEmpty) return false;
    return _rewriteTopicRoutes(siteUrl, topicId, (route) {
      if (route.title == title) return route;
      return route.withDisplay(title: title);
    });
  }

  void _updateTopicRouteMetadata(
    String siteUrl,
    int topicId,
    String fallbackTitle,
    int? categoryId,
  ) {
    // Category writes carry their opening title. A newer rename can finish
    // before that response, so routes follow the title the store now holds.
    final title =
        store.read<TopicDetail>(siteUrl, topicId)?.title ??
        store.read<Topic>(siteUrl, topicId)?.title ??
        fallbackTitle;
    final category = categoryFor(categoryId, siteUrl: siteUrl);
    _rewriteTopicRoutes(siteUrl, topicId, (route) {
      return ContentRoute(
        destination: route.destination,
        title: title,
        icon: route.icon,
        subtitle: route.subtitle,
        color: category == null ? null : Color(category.colorValue),
      );
    });
  }

  bool _rewriteTopicRoutes(
    String siteUrl,
    int topicId,
    ContentRoute Function(ContentRoute route) rewrite,
  ) => _rewriteContentRoutes(
    siteUrl,
    (route) => route.topicId == topicId ? rewrite(route) : route,
  );

  bool _rewriteContentRoutes(
    String siteUrl,
    ContentRoute Function(ContentRoute route) rewrite,
  ) {
    final workspace = _workspace.forSite(siteUrl);
    if (workspace == null) return false;
    var changed = false;
    final tabs = <ForumTab>[];
    for (final tab in workspace.tabs) {
      final updated = tab.rewriteRoutes(rewrite);
      changed = changed || !identical(updated, tab);
      tabs.add(updated);
    }
    if (changed) _workspace.put(workspace.copyWith(tabs: tabs));
    return changed;
  }

  Future<void> expandPostGap({
    required int anchorPostId,
    required bool before,
  }) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;
    await _topicData
        .forSite(instance.url)
        .expandGap(topicId, anchorPostId: anchorPostId, before: before);
  }

  Future<bool> updateTopicNotificationLevel(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
  ) {
    if (isDisposed || topicId <= 0) return Future.value(false);
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return Future.value(false);

    final key = _topicKey(siteUrl, topicId);
    if (held.notificationLevel == level &&
        !_topicNotificationTails.containsKey(key)) {
      return Future.value(true);
    }
    final tracking = _trackingFor(siteUrl);
    final choice = tracking.chooseNotificationLevel(
      topicId,
      level,
      confirmed: held.notificationLevel,
    );
    final write = _QueuedTopicNotification(
      siteUrl: siteUrl,
      topicId: topicId,
      level: level,
      lease: lifecycle.capture(siteUrl),
      tracking: tracking,
      choice: choice,
    );
    _topicNotificationWrites[key] = write;
    final previousTail = _topicNotificationTails[key] ?? Future.value();
    late final Future<void> tail;
    tail = previousTail
        .catchError((_) {
          // Every write settles internally. Keep one unexpected failure from
          // stranding later selections in the queue.
        })
        .then((_) => _performTopicNotificationWrite(key, write))
        .whenComplete(() {
          if (!identical(_topicNotificationTails[key], tail)) return;
          final _ = _topicNotificationTails.remove(key);
          _topicNotificationWrites.remove(key);
          write.tracking.releaseNotificationChoice(write.choice);
        });
    _topicNotificationTails[key] = tail;
    unawaited(tail);
    // Store and shell listeners can synchronously replace this selection or
    // account. Own the lease and queue slot before either can run.
    _projectTopicNotificationLevel(key, write, level);
    return write.result.future;
  }

  bool _isLatestTopicNotification(String key, _QueuedTopicNotification write) =>
      identical(_topicNotificationWrites[key], write) &&
      identical(_topicTrackingBySite[write.siteUrl], write.tracking) &&
      write.lease.isCurrent &&
      !isDisposed;

  Future<void> _performTopicNotificationWrite(
    String key,
    _QueuedTopicNotification write,
  ) async {
    bool isLatest() => _isLatestTopicNotification(key, write);

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    try {
      final credential = await _credentialForWrite(
        write.siteUrl,
        lease: write.lease,
        withClientId: true,
      );
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.failure != null) {
        _rollbackTopicNotification(key, write);
        write.complete(false);
        return;
      }
      final clientId = credential.request!.clientId;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      await credential.request!.run(
        () => api.topicMutations.updateTopicNotificationLevel(
          siteUrl: write.siteUrl,
          apiKey: credential.apiKey!,
          topicId: write.topicId,
          notificationLevel: write.level,
          clientId: clientId,
        ),
      );
      if (!write.lease.isCurrent || isDisposed) {
        write.complete(false);
        return;
      }
      final visible = write.tracking.settleNotificationLevel(
        write.choice,
        succeeded: true,
      );
      if (visible != null) _projectTopicNotificationLevel(key, write, visible);
      write.complete(true);
    } catch (error, stackTrace) {
      if (write.lease.isCurrent && !isDisposed) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.updateNotificationLevel',
          severity: DiagnosticSeverity.warning,
        );
        if (isLatest()) _rollbackTopicNotification(key, write);
      }
      write.complete(false);
    }
  }

  void _rollbackTopicNotification(String key, _QueuedTopicNotification write) {
    final visible = write.tracking.settleNotificationLevel(
      write.choice,
      succeeded: false,
    );
    if (visible != null) _projectTopicNotificationLevel(key, write, visible);
  }

  void _projectTopicNotificationLevel(
    String key,
    _QueuedTopicNotification write,
    TopicNotificationLevel level,
  ) {
    if (!_isLatestTopicNotification(key, write)) return;
    _setTopicNotificationLevel(
      write.siteUrl,
      write.topicId,
      level,
      write.lease,
    );
  }

  void _applyTopicNotificationMessage(
    String siteUrl,
    int topicId,
    Object? data,
    SiteLease lease,
  ) {
    if (data is! Map) return;
    final value = data['notification_level_change'];
    if (value is! int || value < 0 || value > 3) return;
    final level = TopicNotificationLevel.fromJson(value);
    final visible = _trackingFor(
      siteUrl,
    ).observeNotificationLevel(topicId, level);
    _setTopicNotificationLevel(siteUrl, topicId, visible, lease);
  }

  void _setTopicNotificationLevel(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
    SiteLease lease,
  ) {
    if (!lease.isCurrent || isDisposed) return;
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (topic) => topic.withNotificationLevel(level),
    );
    if (lease.isCurrent && !isDisposed && currentInstance?.url == siteUrl) {
      _notify();
    }
  }

  Future<bool> updateCategoryNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
  ) {
    if (isDisposed || categoryId <= 0) return Future.value(false);
    final held = store.read<TopicCategory>(siteUrl, categoryId);
    if (held == null) return Future.value(false);

    final key = _categoryKey(siteUrl, categoryId);
    if (held.notificationLevel == level &&
        !_categoryNotificationTails.containsKey(key)) {
      return Future.value(true);
    }
    _categoryNotificationConfirmed.putIfAbsent(
      key,
      () => held.notificationLevel,
    );
    final write = _QueuedCategoryNotification(
      siteUrl: siteUrl,
      categoryId: categoryId,
      level: level,
      lease: lifecycle.capture(siteUrl),
    );
    _categoryNotificationWrites[key] = write;
    // The response includes a site-wide inherited mute list. Serialize category
    // writes across the account so an older response cannot undo another edit.
    final previousTail =
        _categoryNotificationSiteTails[siteUrl] ?? Future.value();
    late final Future<void> tail;
    tail = previousTail
        .catchError((_) {
          // Every write settles internally. Keep one unexpected failure from
          // stranding later selections in the queue.
        })
        .then((_) => _performCategoryNotificationWrite(key, write))
        .whenComplete(() {
          if (identical(_categoryNotificationSiteTails[siteUrl], tail)) {
            final _ = _categoryNotificationSiteTails.remove(siteUrl);
          }
          if (!identical(_categoryNotificationTails[key], tail)) return;
          final _ = _categoryNotificationTails.remove(key);
          _categoryNotificationWrites.remove(key);
          _categoryNotificationConfirmed.remove(key);
        });
    _categoryNotificationTails[key] = tail;
    _categoryNotificationSiteTails[siteUrl] = tail;
    unawaited(tail);
    // Reentrant selections must append after this write, even when they are
    // made by a listener during optimistic projection.
    _projectCategoryNotificationLevel(key, write, level);
    return write.result.future;
  }

  bool _isLatestCategoryNotification(
    String key,
    _QueuedCategoryNotification write,
  ) =>
      identical(_categoryNotificationWrites[key], write) &&
      write.lease.isCurrent &&
      !isDisposed;

  Future<void> _performCategoryNotificationWrite(
    String key,
    _QueuedCategoryNotification write,
  ) async {
    bool isLatest() => _isLatestCategoryNotification(key, write);

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    late final String apiKey;
    late final String clientId;
    late final AccountRequestCredentials requestCredentials;
    final List<int>? indirectlyMuted;
    try {
      final credential = await _credentialForWrite(
        write.siteUrl,
        lease: write.lease,
        withClientId: true,
      );
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.failure != null) {
        _rollbackCategoryNotification(key, write);
        write.complete(false);
        return;
      }
      apiKey = credential.apiKey!;
      clientId = credential.request!.clientId;
      requestCredentials = credential.request!;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      indirectlyMuted = await credential.request!.run(
        () => api.categoryMutations.updateCategoryNotificationLevel(
          siteUrl: write.siteUrl,
          apiKey: apiKey,
          categoryId: write.categoryId,
          notificationLevel: write.level,
          clientId: clientId,
        ),
      );
    } catch (error, stackTrace) {
      if (write.lease.isCurrent && !isDisposed) {
        _reportOperationalError(
          error,
          stackTrace,
          'category.updateNotificationLevel',
          severity: DiagnosticSeverity.warning,
        );
        if (isLatest()) _rollbackCategoryNotification(key, write);
      }
      write.complete(false);
      return;
    }

    if (!write.lease.isCurrent || isDisposed) {
      write.complete(false);
      return;
    }
    _categoryNotificationConfirmed[key] = write.level;
    final currentUserOwner = _currentUserReconcilerFor(write.siteUrl);
    final categoryTicket = currentUserOwner.categoryPreferencesChanged();
    final user = _instanceAt(write.siteUrl)?.user;
    if (user != null) {
      List<int>? membership(List<int>? ids, CategoryNotificationLevel level) =>
          ids == null
          ? null
          : List.unmodifiable({
              for (final id in ids)
                if (id != write.categoryId) id,
              if (write.level == level) write.categoryId,
            });
      _commitCategoryNotificationPreferences(
        write.siteUrl,
        user.withCategoryNotificationPreferences(
          trackedCategoryIds: membership(
            user.trackedCategoryIds,
            CategoryNotificationLevel.tracking,
          ),
          watchedCategoryIds: membership(
            user.watchedCategoryIds,
            CategoryNotificationLevel.watching,
          ),
          watchedFirstPostCategoryIds: membership(
            user.watchedFirstPostCategoryIds,
            CategoryNotificationLevel.watchingFirstPost,
          ),
          mutedCategoryIds: membership(
            user.mutedCategoryIds,
            CategoryNotificationLevel.muted,
          ),
          indirectlyMutedCategoryIds:
              indirectlyMuted ?? user.indirectlyMutedCategoryIds,
        ),
      );
    }
    _projectCategoryNotificationLevel(key, write, write.level);
    // Persistence and refresh failures cannot turn a committed POST into a
    // failed write, nor delay the next optimistic choice in the write queue.
    write.complete(true);
    if (!write.lease.isCurrent || isDisposed) return;
    final username = _instanceAt(write.siteUrl)?.user?.username;
    if (username == null) return;
    final tracking = _trackingFor(write.siteUrl);
    final ticket = tracking.beginSnapshot(replace: true);
    if (ticket == null) return;
    _topicTrackingRetries.remove(write.siteUrl);
    unawaited(
      _loadTopicTrackingState(
        siteUrl: write.siteUrl,
        username: username,
        lease: write.lease,
        tracking: tracking,
        ticket: ticket,
        requestCredentials: requestCredentials,
        refreshCategoryPreferences:
            indirectlyMuted == null ||
                user?.followedCategoryIds == null ||
                user?.mutedCategoryIds == null
            ? () async {
                final response = await requestCredentials.run(
                  () => api.site.currentUser(
                    siteUrl: write.siteUrl,
                    apiKey: apiKey,
                    clientId: clientId,
                  ),
                );
                if (!write.lease.isCurrent || isDisposed) return;
                final held = _instanceAt(write.siteUrl)?.user;
                if (!currentUserOwner.acceptsCategoryPreferences(
                  categoryTicket,
                  previous: held,
                  incoming: response,
                )) {
                  return;
                }
                _commitCategoryNotificationPreferences(write.siteUrl, response);
              }
            : null,
      ),
    );
    _notify();
  }

  void _commitCategoryNotificationPreferences(
    String siteUrl,
    DiscourseUser preferences,
  ) {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null) return;
    final updated = user.withCategoryNotificationPreferences(
      trackedCategoryIds:
          preferences.trackedCategoryIds ?? user.trackedCategoryIds,
      watchedCategoryIds:
          preferences.watchedCategoryIds ?? user.watchedCategoryIds,
      watchedFirstPostCategoryIds:
          preferences.watchedFirstPostCategoryIds ??
          user.watchedFirstPostCategoryIds,
      mutedCategoryIds: preferences.mutedCategoryIds ?? user.mutedCategoryIds,
      indirectlyMutedCategoryIds:
          preferences.indirectlyMutedCategoryIds ??
          user.indirectlyMutedCategoryIds,
    );
    _replaceInstance(instance, instance.copyWith(user: updated));
    _taxonomy.invalidateCategorySidebar(siteUrl);
    instanceStore.save(List.of(_instances)).ignore();
  }

  void _rollbackCategoryNotification(
    String key,
    _QueuedCategoryNotification write,
  ) {
    final confirmed = _categoryNotificationConfirmed[key];
    if (confirmed == null) return;
    _projectCategoryNotificationLevel(key, write, confirmed);
  }

  void _projectCategoryNotificationLevel(
    String key,
    _QueuedCategoryNotification write,
    CategoryNotificationLevel level,
  ) {
    if (!_isLatestCategoryNotification(key, write)) return;
    _taxonomy.projectNotificationLevel(
      write.siteUrl,
      write.categoryId,
      level,
      write.lease,
    );
  }

  bool topicPinWriteInFlight(String siteUrl, int topicId) =>
      _topicPinWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> updateTopicPinPreference(
    String siteUrl,
    int topicId,
    bool pinned,
  ) async {
    if (isDisposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.hasPinPreference) {
      return appL10n.thisTopicDoesNotOfferAPinPreference;
    }
    if (held.pinned == pinned) return null;

    final key = _topicKey(siteUrl, topicId);
    if (!_topicPinWrites.add(key)) {
      return appL10n.anotherPinChangeIsStillFinishing;
    }
    final heldRow = store.read<Topic>(siteUrl, topicId);
    final lease = lifecycle.capture(siteUrl);

    void project(bool nextPinned, bool nextUnpinned) {
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned, unpinned: nextUnpinned),
        );
        store.update<Topic>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned),
        );
        _notify();
      });
    }

    void rollback() {
      lease.commit(() {
        // Undo only this write's own guess, and only where it still stands.
        // Reading, status writes and re-reads move the same records while the
        // request is out; the tap-time copies would rewind them.
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.pinned == pinned && topic.unpinned == !pinned
              ? topic.copyWith(pinned: held.pinned, unpinned: held.unpinned)
              : topic,
        );
        if (heldRow != null) {
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.pinned == pinned
                ? topic.copyWith(pinned: heldRow.pinned)
                : topic,
          );
        }
        _notify();
      });
    }

    project(pinned, !pinned);
    try {
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) {
        rollback();
        return failure.message;
      }
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || isDisposed) return null;
      await credential.request!.run(
        () => api.topicMutations.updateTopicPinForUser(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          pinned: pinned,
          clientId: clientId,
        ),
      );
      return null;
    } on WriteException catch (error) {
      if (lease.isCurrent && !isDisposed) rollback();
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.updatePinPreference');
        rollback();
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicPinWrites.remove(key);
        if (!isDisposed) _notify();
      });
    }
  }

  final Set<String> _messageArchiveWrites = {};

  Future<String?> updateMessageArchived(
    String siteUrl,
    int topicId,
    bool archived,
  ) async {
    final instance = instanceFor(siteUrl);
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (isDisposed ||
        instance?.isConnected != true ||
        instance?.user?.canSendPrivateMessages != true ||
        held?.privateMessage != true) {
      return appL10n.thisMessageCanNoLongerBeMoved;
    }
    if (held!.messageArchived == archived) return null;
    final key = _topicKey(siteUrl, topicId);
    if (!_messageArchiveWrites.add(key)) {
      return appL10n.anotherInboxActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      await credential.request!.run(
        () => api.topicMutations.updateMessageArchived(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          archived: archived,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      _topicData.forLease(siteUrl, lease)?.acceptArchive(topicId, archived);
      // Core moves it for the user and each of its groups they belong to. The
      // account's message groups can predate a group's first message; the
      // topic names its groups as they are.
      _refreshMessageFolders(
        siteUrl,
        personal: MessageListMode.values,
        group: MessageListMode.values,
        groupNames: {
          ...instance!.user!.messageGroupNames,
          ...held.allowedMessageGroups,
        },
      );
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'message.updateArchived');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() => _messageArchiveWrites.remove(key));
    }
  }

  /// Re-reads the folders on [siteUrl] a message may just have entered or
  /// left: the [personal] ones, and the [group] ones of each of [groupNames],
  /// both under Messages and on the group's page, whose Inbox and Archive tabs
  /// are cached apart. A folder not yet loaded is left to load when opened.
  void _refreshMessageFolders(
    String siteUrl, {
    required Iterable<MessageListMode> personal,
    required Iterable<MessageListMode> group,
    required Iterable<String> groupNames,
  }) {
    final instance = _instanceAt(siteUrl);
    final username = instance?.user?.username;
    if (instance == null || username == null) return;
    void refresh(String destinationId, String path) {
      if (topicFeeds.feedFor(siteUrl, destinationId) == null) return;
      unawaited(
        topicFeeds.load(
          instance: instance,
          destinationId: destinationId,
          path: path,
          incoming: null,
          force: true,
        ),
      );
    }

    for (final mode in personal) {
      refresh(ContentRoute.messages(mode: mode).id, mode.feedPathFor(username));
    }
    final groupModes = [
      for (final mode in group)
        if (mode.supportsGroup) mode,
    ];
    final pageTabs = <String?>[
      if (groupModes.contains(MessageListMode.inbox)) ...[
        null,
        GroupRoute.inbox,
      ],
      if (groupModes.contains(MessageListMode.archive)) GroupRoute.archive,
    ];
    for (final name in groupNames) {
      try {
        for (final mode in groupModes) {
          refresh(
            ContentRoute.messages(groupName: name, mode: mode).id,
            mode.feedPathFor(username, groupName: name),
          );
        }
        for (final subsection in pageTabs) {
          final route = GroupRoute.detail(
            name,
            section: GroupRoute.messages,
            subsection: subsection,
          );
          refresh(route.id, route.topicFeedPath(username)!);
        }
      } on ArgumentError {
        // A recipient no group route can name has no group folders.
        continue;
      }
    }
  }

  bool topicStatusWriteInFlight(String siteUrl, int topicId) =>
      _topicStatusWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> updateTopicStatus(
    String siteUrl,
    int topicId,
    TopicStatusProperty status,
    bool enabled,
  ) async {
    if (isDisposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.canChangeStatus(status)) {
      return appL10n.thisTopicCanNoLongerBeChangedThatWay;
    }
    if (held.statusValue(status) == enabled) return null;

    final key = _topicKey(siteUrl, topicId);
    if (!_topicStatusWrites.add(key)) {
      return appL10n.anotherTopicActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || isDisposed) return null;
      await credential.request!.run(
        () => api.topicMutations.updateTopicStatus(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          status: status,
          enabled: enabled,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.withStatus(status, enabled),
        );
        if (status == TopicStatusProperty.closed) {
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.copyWith(closed: enabled),
          );
        }
        _notify();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.updateStatus');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicStatusWrites.remove(key);
        if (!isDisposed) _notify();
      });
    }
  }

  bool topicDeletionWriteInFlight(String siteUrl, int topicId) =>
      _topicDeletionWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> setTopicDeleted(
    String siteUrl,
    int topicId,
    bool deleted,
  ) async {
    if (isDisposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    final allowed = deleted
        ? held?.canDeleteTopic == true
        : held?.canRecoverTopic == true;
    if (held == null || !allowed) {
      return deleted
          ? appL10n.thisTopicCannotBeDeleted
          : appL10n.thisTopicCannotBeRecovered;
    }
    final key = _topicKey(siteUrl, topicId);
    if (!_topicDeletionWrites.add(key)) {
      return appL10n.anotherTopicActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || isDisposed) return null;
      if (deleted) {
        await credential.request!.run(
          () => api.topicMutations.deleteTopic(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            clientId: clientId,
          ),
        );
      } else {
        await credential.request!.run(
          () => api.topicMutations.recoverTopic(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            clientId: clientId,
          ),
        );
      }
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        _applyTopicDeletion(siteUrl, topicId, deleted, lease);
        _notify();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.setDeleted');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicDeletionWrites.remove(key);
        if (!isDisposed) _notify();
      });
    }
  }

  /// Applies an accepted deletion or recovery of a topic. Neither endpoint
  /// answers with the topic, so the held one takes what PostDestroyer is known
  /// to do to it, its list row follows the closed state, and it is read again
  /// for what that leaves to the server.
  void _applyTopicDeletion(
    String siteUrl,
    int topicId,
    bool deleted,
    SiteLease lease,
  ) {
    final data = _topicData.forLease(siteUrl, lease);
    if (data == null) return;
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return;
    final next = deleted
        ? held.afterDeletion(DateTime.now().toUtc())
        : held.afterRecovery();
    if (identical(next, held)) return;
    store.update<TopicDetail>(siteUrl, topicId, (_) => next);
    if (!lease.isCurrent) return;
    if (next.closed != held.closed) {
      store.update<Topic>(
        siteUrl,
        topicId,
        (row) => row.copyWith(closed: next.closed),
      );
    }
    if (!deleted) {
      // Only the server knows whether the recovered topic takes replies again.
      unawaited(data.refresh(topicId, slug: ''));
      return;
    }
    // Site settings decide whether an author's deletion withdrew or trashed
    // the topic, and a deleter may no longer be allowed to read a trashed
    // one, so it is read when next opened rather than now.
    data.refreshWhenOpened(topicId);
  }

  final Map<String, Object> _topicUnreadWrites = {};

  bool topicUnreadWriteInFlight(String siteUrl, int topicId) =>
      _topicUnreadWrites.containsKey(_topicKey(siteUrl, topicId));

  Future<String?> markTopicUnread(String siteUrl, int topicId) async {
    if (isDisposed || instanceFor(siteUrl)?.isConnected != true) return null;
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null) return null;
    final key = _topicKey(siteUrl, topicId);
    if (_topicUnreadWrites.containsKey(key)) return null;
    final operation = Object();
    _topicUnreadWrites[key] = operation;
    final lease = lifecycle.capture(siteUrl);
    final tab = activeTabId;
    final route = currentContent;
    _notify();
    try {
      // Let already-sent timings settle before resetting them. New viewport
      // observations are suppressed until this operation has left the topic.
      await _topicReads.finishPending(siteUrl, topicId);
      if (isDisposed || !lease.isCurrent) return null;
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (isDisposed || !lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      await credential.request!.run(
        () => api.pluginTransport.pluginWriteJson(
          siteUrl: siteUrl,
          path: '/t/$topicId/timings.json?last=1',
          method: 'DELETE',
          apiKey: credential.apiKey!,
          body: const {},
        ),
      );
      if (isDisposed || !lease.isCurrent) return null;
      _topicReads.forgetTopic(siteUrl, topicId);
      _trackingFor(
        siteUrl,
      ).markLastPostUnread(topicId, math.max(0, topic.highestPostNumber - 1));
      final row = store.read<Topic>(siteUrl, topicId);
      if (row != null) {
        store.put(
          siteUrl,
          row.copyWith(
            lastReadPostNumber: math.max(0, topic.highestPostNumber - 1),
            unreadPosts: 1,
          ),
        );
      }
      if (currentInstance?.url == siteUrl &&
          activeTabId == tab &&
          identical(currentContent, route) &&
          route?.topicId == topicId) {
        handleBack(canReturnToSidebar: false);
      }
      await _topicData.forLease(siteUrl, lease)?.refresh(topicId, slug: '');
      return null;
    } on WriteException catch (error) {
      return lease.isCurrent ? error.message : null;
    } catch (error, stackTrace) {
      if (!lease.isCurrent || isDisposed) return null;
      _reportOperationalError(error, stackTrace, 'topic.markUnread');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      if (identical(_topicUnreadWrites[key], operation)) {
        _topicUnreadWrites.remove(key);
        if (!isDisposed) _notify();
      }
    }
  }

  Future<void> markTopicRead(
    String siteUrl,
    int topicId,
    int postNumber, {
    required bool caughtUp,
    Iterable<int> readPostNumbers = const [],
  }) {
    if (topicUnreadWriteInFlight(siteUrl, topicId)) return Future.value();
    final lease = lifecycle.capture(siteUrl);
    final receipt = _topicReads.mark(
      siteUrl,
      topicId,
      postNumber,
      caughtUp: caughtUp,
      readPostNumbers: readPostNumbers,
    );
    // The read controller publishes locally before its request completes.
    // Update counts and visible queues from that same optimistic position.
    final position = _topicReads.lastReadPostNumberFor(siteUrl, topicId);
    if (!isDisposed && lease.isCurrent && position != null) {
      _trackingFor(siteUrl).markRead(topicId, position);
      if (currentInstance?.url == siteUrl) _notifyLiveChange();
    }
    return receipt;
  }

  Future<void> loadMorePosts({int batchSize = 20, String? tabId}) async {
    final context = tabId == null ? focusedTabContext : tabContext(tabId);
    if (!context.isCurrent) return;
    final instance = currentInstance;
    final topicId = context.currentContent?.topicId;
    if (instance == null || topicId == null) return;
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    final data = _topicData.forSite(instance.url);
    if (data.paging(topicId, newer: true)) return;
    final bounded = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = _pendingPostIds(
      instance.url,
      context._currentPostWindow(),
      bounded + 1,
    );
    if (pending.isEmpty) {
      final edge = context._currentMegaTopicEdge(newer: true);
      if (edge != null) await data.pageMega(detail, edge, newer: true);
      return;
    }
    final ids = pending.take(bounded).toList();
    await data.pageIds(
      topicId,
      ids: ids,
      newer: true,
      reachesEnd: ids.length == pending.length,
    );
  }

  Future<void> loadEarlierPosts({int batchSize = 20, String? tabId}) async {
    final context = tabId == null ? focusedTabContext : tabContext(tabId);
    if (!context.isCurrent) return;
    final instance = currentInstance;
    final topicId = context.currentContent?.topicId;
    if (instance == null || topicId == null) return;
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    final data = _topicData.forSite(instance.url);
    if (data.paging(topicId, newer: false)) return;
    final bounded = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = context._pendingEarlierPostIds(
      instance.url,
      detail,
      bounded,
    );
    if (pending.isEmpty) {
      final edge = context._currentMegaTopicEdge(newer: false);
      if (edge != null) await data.pageMega(detail, edge, newer: false);
      return;
    }
    await data.pageIds(topicId, ids: pending, newer: false);
  }

  bool get loadingMorePosts => focusedTabContext.loadingMorePosts;

  bool get loadingEarlierPosts => focusedTabContext.loadingEarlierPosts;

  Future<String?> toggleTopicSummary() async {
    final instance = currentInstance;
    final topic = currentTopic;
    if (instance == null || topic == null || !topic.hasSummary) return null;
    final success = await _topicData
        .forSite(instance.url)
        .toggleSummary(topic.id, slug: currentContent?.slug ?? '');
    return success ? null : appL10n.couldnTLoadThisTopicSSummary;
  }

  final Set<ComposerController> _composers = {};
  final Map<String, ComposerController> _selectedComposers = {};
  int _composerRevealRevision = 0;
  ComposerController? _composerRevealTarget;
  ComposerController? get composerRevealTarget => _composerRevealTarget;

  /// Explicit draft selections reveal even an already selected minimized editor.
  int get composerRevealRevision => _composerRevealRevision;
  // Creation results belong to the submitting tab, even if navigation changes
  // while the request or its reconciliation is in flight.
  final Expando<String> _composerSubmissionTabs = Expando();

  // Commands target the selected forum; async continuations keep the exact
  // composer that started them even if the user changes forums or drafts.
  ComposerController? get _composer {
    final instance = currentInstance;
    if (instance == null) return null;
    return _selectedComposers[instance.url];
  }

  void _setComposer(ComposerController composer) {
    SurfaceOpeningTrace.mark('composer.publish');
    final target = composer.target;
    _composers.add(composer);
    _selectedComposers[target.siteUrl] = composer;
  }

  bool _ownsComposer(ComposerController? composer) {
    if (composer == null) return false;
    return _composers.contains(composer);
  }

  void _removeComposer(ComposerController composer) {
    if (!_ownsComposer(composer)) return;
    final target = composer.target;
    final selected = identical(_selectedComposers[target.siteUrl], composer);
    final index = selected
        ? _composersForSite(target.siteUrl).toList().indexOf(composer)
        : -1;
    _composers.remove(composer);
    if (identical(_composerRevealTarget, composer)) {
      _composerRevealTarget = null;
    }
    if (selected) {
      final remaining = _composersForSite(target.siteUrl).toList();
      if (remaining.isEmpty) {
        _selectedComposers.remove(target.siteUrl);
      } else {
        final next = remaining[math.min(index, remaining.length - 1)];
        _selectedComposers[target.siteUrl] = next;
        _composerRevealTarget = next;
        _composerRevealRevision++;
      }
    }
    _composerDrafts.detach(composer);
  }

  Iterable<ComposerController> _composersForSite(String siteUrl) =>
      _composers.where((composer) => composer.target.siteUrl == siteUrl);

  /// Selects a retained draft without replacing its editor or history.
  void selectComposer(ComposerController composer) {
    if (!_ownsComposer(composer) ||
        composer.closing ||
        composer.isDisposed ||
        composer.target.siteUrl != currentInstance?.url) {
      return;
    }
    if (!identical(_composer, composer)) {
      _composer?.focus.unfocus();
      _composer?.titleFocus.unfocus();
    }
    _selectedComposers[composer.target.siteUrl] = composer;
    _composerRevealTarget = composer;
    _composerRevealRevision++;
    _notify();
    composer.focus.requestFocus();
  }

  /// Every open draft remains account scoped, independently of reader tabs.
  Iterable<ComposerController> get liveComposers =>
      List.unmodifiable(_composers);

  // Reported after every frame the reader moves; kept off the facade so a
  // resize or dock drag does not re-run every shell selector.
  final _readerContentBounds = FrameSafeValueNotifier<Rect?>(null);

  late final ComposerDraftCoordinator _composerDrafts =
      ComposerDraftCoordinator(
        localStore: drafts,
        persistence: api.composerPersistence,
        draftsApi: api.drafts,
        lifecycle: lifecycle,
        credentials: credentials,
        readClientId: authenticator.clientId,
        isDisposed: () => isDisposed,
        isCurrentComposer: _ownsComposer,
        readCachedDraft: (target) => target is ExistingTopicComposerTarget
            ? store.read<TopicDetail>(target.siteUrl, target.topicId)?.draft
            : null,
        readCachedSequence: (target) => target is ExistingTopicComposerTarget
            ? store
                      .read<TopicDetail>(target.siteUrl, target.topicId)
                      ?.draftSequence ??
                  0
            : 0,
        writeCachedDraft: (target, draft, sequence) {
          if (target is! ExistingTopicComposerTarget) return;
          store.update<TopicDetail>(
            target.siteUrl,
            target.topicId,
            (detail) => detail.withDraft(draft, sequence),
          );
        },
        minimumRequiredTagsFor: (siteUrl, categoryId) =>
            topicComposerCategories(siteUrl)
                .where((category) => category.id == categoryId)
                .firstOrNull
                ?.minimumRequiredTags ??
            0,
        isServerDraftKnown: (target) =>
            draftList
                .feedFor(target.siteUrl)
                .drafts
                .any((draft) => draft.key == target.draftKey) ||
            (target is ExistingTopicComposerTarget &&
                store
                        .read<TopicDetail>(target.siteUrl, target.topicId)
                        ?.draft !=
                    null),
        recordDraftDestroyed: _recordDraftDestroyed,
        onComposerClosed: (composer) {
          _removeComposer(composer);
          _notify();
        },
        reportError: _reportOperationalError,
      );

  ComposerController? get visibleComposer {
    final composer = _composer;
    final instance = currentInstance;
    if (!forumActive ||
        composer == null ||
        composer.closing ||
        instance == null) {
      return null;
    }
    if (composer.target.siteUrl != instance.url) return null;
    return composer;
  }

  /// Painted reader space, excluding the docked composer and navigation.
  void reportReaderContentBounds(Rect? bounds) {
    if (isDisposed) return;
    _readerContentBounds.value = bounds;
  }

  bool get canReplyHere => focusedTabContext.canReplyHere;

  ComposerController _buildTextComposer(
    ComposerTarget target, {
    bool persistsDraft = false,
    int minimumRequiredTags = 0,
  }) {
    SurfaceOpeningTrace.mark('composer.create');
    final config = siteConfigFor(target.siteUrl);
    final pluginPolicy = target is PluginComposerTarget ? target.policy : null;
    final draftSession = persistsDraft
        ? _composerDrafts.openSession(target)
        : null;
    ComposerPluginState readPluginState() {
      final currentUser = currentUserFor(target.siteUrl);
      final freshCurrentUser = freshCurrentUserFor(target.siteUrl);
      final editingPostId = switch (target) {
        PostEditingComposerTarget(:final editingPostId) => editingPostId,
        TaxonomyEditComposerTarget(:final firstPostId) => firstPostId,
        _ => null,
      };
      final editingPostNumber = switch (target) {
        PostEditingComposerTarget(:final editingPostNumber) =>
          editingPostNumber,
        TaxonomyEditComposerTarget() => 1,
        _ => null,
      };
      final editingPost = editingPostId == null
          ? null
          : store.read<Post>(target.siteUrl, editingPostId);
      return ComposerPluginState(
        siteSettings: siteConfigFor(target.siteUrl).plugins,
        currentUser: currentUser?.plugins ?? PluginData.none,
        freshCurrentUser: freshCurrentUser?.plugins ?? PluginData.none,
        editingPost: editingPost?.plugins ?? PluginData.none,
        accountTimezone: currentUser?.timezone,
        freshCurrentUserIsStaff: freshCurrentUser?.staff == true,
        createsTopic: target.createsTopic,
        editingPostNumber: editingPostNumber ?? editingPost?.postNumber,
      );
    }

    final initialPluginState = readPluginState();
    late final ComposerController composer;
    composer = ComposerController(
      target,
      onSaveDraft: draftSession?.save,
      onStageDraft: draftSession?.stage,
      search: _composerSearch(target),
      onEmojiAccepted: (code) => unawaited(
        emojiPickerStore.trackEmoji(
          siteUrl: target.siteUrl,
          context:
              pluginPolicy?.emojiUsageContext ?? CoreEmojiUsageContexts.topic,
          emoji: code,
        ),
      ),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      pluginHashtagPresentation: plugins.registry.pluginHashtagPresentation,
      formatQuoteContents: (block) =>
          quoteContentsFor(target, block) ?? block.contents,
      syntaxPolicies: plugins.registry.composerSyntaxPolicies(
        ComposerSyntaxPolicyContext(
          siteUrl: target.siteUrl,
          isPluginTarget: target.isPlugin,
          isEdit: target.isEdit,
          initialState: initialPluginState,
          readState: readPluginState,
          readEditor: () => composer,
        ),
      ),
      pluginStateReader: readPluginState,
      // Plugin surfaces own and dispose their composers; only topic composers
      // are registered in the shell's per-tab map.
      isCurrentComposer: () =>
          !isDisposed && (target.isPlugin || _ownsComposer(composer)),
      imageUploader: !(pluginPolicy?.uploadsEnabled ?? true)
          ? null
          : (file, {required onProgress, required abortTrigger}) =>
                _uploadComposerImage(
                  target,
                  file,
                  onProgress: onProgress,
                  abortTrigger: abortTrigger,
                ),
      prepareUpload: (file, {required abortTrigger}) =>
          ComposerMediaOptimizer().prepare(
            file,
            imageSettings: config.composerImageOptimization,
            canUpload: (filename) => config.canUploadFile(
              filename,
              staff: currentUserFor(target.siteUrl)?.staff == true,
              privateMessage: _uploadsForPrivateMessage(target),
            ),
            abortTrigger: abortTrigger,
          ),
      resolveUploadUrls: (urls) => _resolveComposerUploadUrls(target, urls),
      canUploadImage: (filename) => config.canUploadImage(
        filename,
        staff: currentUserFor(target.siteUrl)?.staff == true,
        privateMessage: _uploadsForPrivateMessage(target),
      ),
      canUploadFile: (filename) => config.canUploadFile(
        filename,
        staff: currentUserFor(target.siteUrl)?.staff == true,
        privateMessage: _uploadsForPrivateMessage(target),
      ),
      simultaneousUploads: config.simultaneousUploads,
      enableAutoGridImages: config.enableAutoGridImages,
      enableMarkdownLinkify: config.enableMarkdownLinkify,
      markdownLinkifyTlds: config.markdownLinkifyTlds,
      maxImageWidth: config.maxImageWidth,
      maxImageHeight: config.maxImageHeight,
      minimumRequiredTags: minimumRequiredTags,
    );
    if (draftSession != null) _composerDrafts.attach(draftSession, composer);
    return composer;
  }

  String? quoteContentsFor(ComposerTarget target, ComposerQuoteBlock block) {
    final topicId = block.topicId;
    final postNumber = block.postNumber;
    if (topicId == null || postNumber == null) return null;
    final topic = store.read<TopicDetail>(target.siteUrl, topicId);
    if (topic == null) return null;

    for (final id in topic.stream) {
      final post = store.read<Post>(target.siteUrl, id);
      if (post?.postNumber != postNumber) continue;
      return postQuoteContentsFromSelection(post!.cooked, block.contents);
    }
    return null;
  }

  ComposerController? buildPluginComposer(ComposerTargetRequest request) {
    final policy = plugins.registry.composerTarget(
      request,
      ComposerTargetContext(
        siteSettings: siteConfigFor(request.siteUrl).plugins,
        currentUser:
            currentUserFor(request.siteUrl)?.plugins ?? PluginData.none,
      ),
    );
    if (policy == null) return null;
    return _buildTextComposer(
      PluginComposerTarget(
        siteUrl: request.siteUrl,
        topicTitle: request.title,
        policy: policy,
        data: Map.unmodifiable(request.data),
      ),
    );
  }

  void openPrivateMessage({
    required String siteUrl,
    required String targetRecipients,
  }) => _openPrivateMessage(
    siteUrl: siteUrl,
    targetRecipients: targetRecipients,
    permitted: (user) => user.canSendPrivateMessages,
  );

  /// Opens a new message addressed to [group] alone.
  ///
  /// Core answers the group's `messageable` with
  /// `can_send_private_message?(group)` for the reader, which admits a group
  /// messageable by everyone even when the reader may not start messages in
  /// general, so that flag is the whole permission.
  void openGroupMessage({required String siteUrl, required Group group}) =>
      _openPrivateMessage(
        siteUrl: siteUrl,
        targetRecipients: group.name,
        permitted: (_) => group.messageable,
      );

  void _openPrivateMessage({
    required String siteUrl,
    required String targetRecipients,
    required bool Function(DiscourseUser user) permitted,
  }) {
    final instance = currentInstance;
    final user = instance?.user;
    final source = topicListContent;
    final route = source?.isMessages == true ? source : currentContent;
    final tabId = activeTabId;
    final feedId = currentFeedId;
    final recipients = targetRecipients
        .split(',')
        .map((recipient) => recipient.trim())
        .where((recipient) => recipient.isNotEmpty)
        .join(',');
    if (instance?.url != siteUrl ||
        user == null ||
        !permitted(user) ||
        route?.isTopic != false ||
        tabId == null ||
        feedId == null) {
      return;
    }

    // A PM may be parked behind another draft tab. Core uses one shared PM
    // key, so select that owner before applying the mature replacement path.
    final heldMessage = _composersForSite(siteUrl)
        .where(
          (held) =>
              held.target.isPrivateMessage &&
              held.canSaveDraft &&
              held.target.draftKey == ComposerDraft.newPrivateMessageDraftKey,
        )
        .firstOrNull;
    if (heldMessage != null &&
        (heldMessage.closing || _composerHasPendingOperation(heldMessage))) {
      return;
    }
    if (heldMessage != null && !identical(heldMessage, _composer)) {
      selectComposer(heldMessage);
    }
    if (!_replaceComposer()) return;
    final target = PrivateMessageComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicTitle: appL10n.newMessage,
      originFeedId: feedId,
      targetRecipients: recipients,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _setComposer(composer);
    _notify();
    _composerDrafts.startRestore(composer);
    if (recipients.isNotEmpty) composer.requestFocus();
  }

  Future<void> openNewTopic() =>
      _openNewTopic(permitted: canCreateTopicHere, revealContent: false);

  /// Installed by the presentation host to confirm discarding an active draft.
  Future<void> Function(ComposerController composer)?
  confirmComposerReplacement;

  int _lastNewDraftId = 0;

  /// A key no saved draft uses, so a fresh composer neither restores nor
  /// overwrites another draft of the same kind.
  String _newDraftKey(String base) {
    _lastNewDraftId = math.max(
      _clock().millisecondsSinceEpoch,
      _lastNewDraftId + 1,
    );
    return '${base}_$_lastNewDraftId';
  }

  Future<bool> _prepareNewTopicComposer() async {
    final existing = _composer;
    if (existing == null) return true;
    if (existing.closing || _composerHasPendingOperation(existing)) {
      return false;
    }
    if (existing.canSaveDraft && !await finishComposerDraftRestore(existing)) {
      return false;
    }
    if (!identical(_composer, existing) ||
        existing.closing ||
        _composerHasPendingOperation(existing)) {
      return false;
    }
    if (existing.canSaveDraft) return true;
    if (!existing.hasChanges &&
        !existing.metadataChanged &&
        !existing.hasUnappliedDraft) {
      return true;
    }
    final confirm = confirmComposerReplacement;
    if (confirm == null) return false;
    await confirm(existing);
    return existing.isDisposed && _composer == null;
  }

  Future<void> openNewTopicFromList() => _openNewTopic(
    permitted: canCreateTopicFromList,
    revealContent: false,
    sourceRoute: topicListContent,
  );

  Future<void> openNewTopicFromSidebar() => _openNewTopic(
    permitted: canCreateTopicFromSidebar,
    revealContent: true,
    sourceRoute: topicListContent,
  );

  Future<void> _openNewTopic({
    required bool permitted,
    required bool revealContent,
    ContentRoute? sourceRoute,
    UserDraft? listedDraft,
  }) async {
    final instance = currentInstance;
    final route = sourceRoute ?? currentContent;
    final feedId = currentFeedId;
    final tabId = activeTabId;
    if (instance == null ||
        route == null ||
        feedId == null ||
        tabId == null ||
        !permitted) {
      return;
    }
    final lease = lifecycle.capture(instance.url);
    final content = currentContent;
    if (!await _prepareNewTopicComposer() ||
        isDisposed ||
        !lease.isCurrent ||
        currentInstance?.url != instance.url ||
        activeTabId != tabId ||
        currentFeedId != feedId ||
        currentContent != content) {
      return;
    }
    final originFeedId = revealContent && !canCreateTopicHere
        ? instance.defaultDestination.id
        : feedId;
    final path = route.feedPath;
    final link = path == null
        ? null
        : ListLink.parse(path.replaceFirst(RegExp(r'\.json$'), ''));
    final categoryId = canCreateTopicHere || sourceRoute != null
        ? route.categoryId
        : null;
    var selectedCategory = categoryFor(categoryId, siteUrl: instance.url);
    final categoryNeedsLookup = categoryId != null && selectedCategory == null;
    if (selectedCategory == null &&
        categoryId != null &&
        link?.kind == ListKind.category) {
      final color = route.color?.toARGB32();
      selectedCategory = TopicCategory(
        id: categoryId,
        name: route.title,
        color: color == null
            ? '888888'
            : (color & 0x00ffffff)
                  .toRadixString(16)
                  .padLeft(6, '0')
                  .toUpperCase(),
        slug: link!.slug,
      );
    }
    if (categoryNeedsLookup && selectedCategory != null) {
      _taxonomy.mergeCategories(instance.url, [selectedCategory]);
    }
    if (!_replaceComposer()) return;
    final target = NewTopicComposerTarget(
      siteUrl: instance.url,
      tabId: tabId,
      topicTitle: appL10n.newTopic,
      draftKey:
          listedDraft?.key ?? _newDraftKey(ComposerDraft.newTopicDraftKey),
      originFeedId: originFeedId,
      initialCategoryId: categoryId,
    );
    final composer = _buildTextComposer(
      target,
      persistsDraft: true,
      minimumRequiredTags: selectedCategory?.minimumRequiredTags ?? 0,
    );
    _setComposer(composer);
    if (revealContent) _mobilePane = MobilePane.content;
    if (listedDraft == null) {
      _composerDrafts.startNewDraft(composer);
    } else {
      _composerDrafts.startRestore(composer, listedDraft: listedDraft);
    }
    final enrichment = _enrichNewTopicComposer(
      composer,
      instance: instance,
      link: link,
      categoryId: categoryId,
      placeholderCategory: categoryNeedsLookup ? selectedCategory : null,
    );
    _notify();
    await enrichment;
  }

  Future<void> _enrichNewTopicComposer(
    ComposerController composer, {
    required DiscourseInstance instance,
    required ListLink? link,
    required int? categoryId,
    required TopicCategory? placeholderCategory,
  }) async {
    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    bool isCurrent() =>
        lease.isCurrent && _ownsComposer(composer) && !composer.isDisposed;

    // Categories and capabilities refine an already usable composer. Keeping
    // them off the presentation path makes the first frame independent of the
    // network while retaining retryable failures and late-arriving metadata.
    await Future.wait<void>([
      if (!_topicComposerCapabilities.containsKey(siteUrl))
        _ensureTopicComposerCapabilities(siteUrl),
      if (_taxonomy.needsCategoryLoad(siteUrl)) loadCategories(siteUrl),
    ]);
    if (!isCurrent()) return;

    AccountRequestCredentials? requestCredentials;
    var credentialsRead = false;
    Future<AccountRequestCredentials?> readCredentials() async {
      if (credentialsRead) return requestCredentials;
      credentialsRead = true;
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!isCurrent() || credential.failure != null) return null;
      return requestCredentials = credential.request;
    }

    final loadedCategory = categoryFor(categoryId, siteUrl: siteUrl);
    final stillHasPlaceholder =
        placeholderCategory != null &&
        identical(loadedCategory, placeholderCategory);
    if (categoryId != null && (loadedCategory == null || stillHasPlaceholder)) {
      final credential = await readCredentials();
      if (!isCurrent()) return;
      if (credential != null) {
        try {
          final found = await credential.run(
            () => api.categories.findCategories(
              siteUrl: siteUrl,
              ids: [categoryId],
              apiKey: credential.apiKey!,
            ),
          );
          if (!isCurrent()) return;
          if (found.isNotEmpty) {
            _taxonomy.mergeCategories(siteUrl, found);
            _notify();
          }
        } catch (error, stackTrace) {
          if (isCurrent()) {
            _reportOperationalError(
              error,
              stackTrace,
              'composer.category',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
      }
    }
    if (!isCurrent()) return;

    final capabilities = topicComposerCapabilities(siteUrl);
    if (link?.kind == ListKind.tag && capabilities.canTagTopics) {
      final tagLink = link!;
      final credential = await readCredentials();
      if (!isCurrent()) return;
      if (credential != null) {
        try {
          final result = await credential.run(
            () => api.topicComposerQueries.searchTopicTags(
              siteUrl: siteUrl,
              apiKey: credential.apiKey!,
              term: tagLink.slug,
              categoryId: categoryId,
            ),
          );
          if (!isCurrent()) return;
          final exact = result.results.where(
            (tag) =>
                tag.id == tagLink.id ||
                tag.name.toLowerCase() == tagLink.slug.toLowerCase() ||
                tag.slug?.toLowerCase() == tagLink.slug.toLowerCase(),
          );
          if (exact.isNotEmpty && !exact.first.disabled) {
            composer.applyInitialTagsIfUntouched([exact.first]);
          }
        } catch (_) {}
      }
    }
    if (!isCurrent()) return;

    composer.setMinimumRequiredTags(
      categoryFor(composer.categoryId, siteUrl: siteUrl)?.minimumRequiredTags ??
          0,
    );
    unawaited(_applyInitialTopicTemplate(composer, isCurrent));
  }

  /// Core applies the template of the category a new topic opens in. A draft
  /// being restored outranks it: filling the field first would advance the
  /// revision the restore checks and leave it refusing a field that is no
  /// longer empty. Opening does not wait for it: a restore can be waiting on
  /// the site.
  Future<void> _applyInitialTopicTemplate(
    ComposerController composer,
    bool Function() isCurrent,
  ) async {
    final restore = _composerDrafts.restoreTaskFor(composer);
    if (restore == null) return;
    try {
      if (!await restore) return;
    } catch (_) {
      return;
    }
    if (!isCurrent()) return;
    composer.applyInitialTopicTemplateIfUntouched(
      categoryFor(
        composer.categoryId,
        siteUrl: composer.target.siteUrl,
      )?.topicTemplate,
    );
  }

  /// Whether [topic] offers continuing in a new topic, or, from a message, in
  /// a new message to the same participants.
  bool canReplyAsNewTopic(TopicDetail topic) =>
      topic.canReplyAsNewTopic &&
      (!topic.privateMessage ||
          currentInstance?.user?.canSendPrivateMessages == true);

  Future<void> openReplyAsNewTopic(String continuation) async {
    final instance = currentInstance;
    final route = currentContent;
    final detail = currentTopic;
    final tabId = activeTabId;
    if (instance == null ||
        route?.topicId == null ||
        detail == null ||
        !canReplyAsNewTopic(detail) ||
        tabId == null ||
        continuation.trim().isEmpty) {
      return;
    }

    final siteUrl = instance.url;
    final sourceTopicId = detail.id;
    // The continuation names and links the source, so a message may only be
    // continued among its own participants, never in a public topic.
    final privateMessage = detail.privateMessage;
    final lease = lifecycle.capture(siteUrl);
    bool sourceIsCurrent() {
      final current = currentTopic;
      return lease.isCurrent &&
          activeTabId == tabId &&
          currentInstance?.url == siteUrl &&
          currentContent?.topicId == sourceTopicId &&
          current != null &&
          current.privateMessage == privateMessage &&
          canReplyAsNewTopic(current);
    }

    if (!privateMessage) {
      await Future.wait<void>([
        loadCategories(siteUrl),
        _ensureTopicComposerCapabilities(siteUrl),
      ]);
      if (!sourceIsCurrent()) return;
    }
    if (!await _prepareNewTopicComposer() || !sourceIsCurrent()) return;

    final ComposerTarget target;
    var minimumRequiredTags = 0;
    if (privateMessage) {
      final source = currentTopic!;
      final username = currentInstance?.user?.username.toLowerCase();
      // The site adds the author to every message it creates, and naming them
      // would also hold them to their own message preferences. A message only
      // the author is left in still has to name someone.
      final others = [
        for (final name in source.allowedMessageUsers)
          if (name.toLowerCase() != username) name,
        ...source.allowedMessageGroups,
      ];
      target = PrivateMessageComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicTitle: appL10n.newMessage,
        originTopicId: sourceTopicId,
        draftKey: _newDraftKey(ComposerDraft.newPrivateMessageDraftKey),
        targetRecipients: (others.isEmpty ? source.allowedMessageUsers : others)
            .join(','),
      );
    } else {
      final category = topicComposerCategories(siteUrl)
          .where((item) => item.id == detail.categoryId && item.canCreateTopic)
          .firstOrNull;
      minimumRequiredTags = category?.minimumRequiredTags ?? 0;
      target = NewTopicComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicTitle: appL10n.newTopic,
        originTopicId: sourceTopicId,
        draftKey: _newDraftKey(ComposerDraft.newTopicDraftKey),
        initialCategoryId: category?.id,
      );
    }
    if (!_replaceComposer()) return;
    final composer = _buildTextComposer(
      target,
      persistsDraft: true,
      minimumRequiredTags: minimumRequiredTags,
    );
    _setComposer(composer);
    _notify();
    _composerDrafts.startNewDraft(composer);
    if (!lease.isCurrent ||
        !_ownsComposer(composer) ||
        activeTabId != tabId ||
        currentContent?.topicId != sourceTopicId) {
      return;
    }
    if (!composer.text.text.contains(continuation.trim())) {
      composer.prependBlock(continuation);
    }
    composer.focus.requestFocus();
  }

  Future<OpenComposerResult> openNewTopicFromPlugin(
    OpenNewTopicComposerRequest request,
  ) async {
    final siteUrl = request.siteUrl;
    final sourceRouteId = request.sourceRouteId;
    final route = currentContent;
    final tabId = activeTabId;
    final feedId = currentFeedId;
    bool sourceIsCurrent() => request.sourceStillCurrent?.call() ?? true;

    if (!forumActive || route?.id != sourceRouteId || !sourceIsCurrent()) {
      return OpenComposerResult.sourceChanged;
    }
    if (request.seed.raw.trim().isEmpty ||
        currentInstance?.url != siteUrl ||
        currentInstance?.user == null ||
        tabId == null ||
        feedId == null) {
      return OpenComposerResult.unavailable;
    }

    final lease = lifecycle.capture(siteUrl);
    await Future.wait<void>([
      loadCategories(siteUrl),
      _ensureTopicComposerCapabilities(siteUrl),
    ]);
    if (!forumActive ||
        !lease.isCurrent ||
        currentInstance?.url != siteUrl ||
        route?.sameDestinationAs(currentContent) != true ||
        !sourceIsCurrent() ||
        activeTabId != tabId ||
        currentFeedId != feedId) {
      return OpenComposerResult.sourceChanged;
    }

    final category = request.initialCategoryId == null
        ? null
        : topicComposerCategories(siteUrl)
              .where(
                (item) =>
                    item.id == request.initialCategoryId && item.canCreateTopic,
              )
              .firstOrNull;
    var composer = visibleComposer;
    final reusable =
        composer != null &&
        composer.target.isNewTopic &&
        composer.target.siteUrl == siteUrl &&
        composer.target.originFeedId == feedId;
    if (!reusable) {
      if (!await _prepareNewTopicComposer()) {
        return OpenComposerResult.unavailable;
      }
      if (!forumActive ||
          !lease.isCurrent ||
          currentInstance?.url != siteUrl ||
          route?.sameDestinationAs(currentContent) != true ||
          !sourceIsCurrent() ||
          activeTabId != tabId ||
          currentFeedId != feedId) {
        return OpenComposerResult.sourceChanged;
      }
      if (!_replaceComposer()) return OpenComposerResult.unavailable;
      final target = NewTopicComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicTitle: appL10n.newTopic,
        originFeedId: feedId,
        draftKey: _newDraftKey(ComposerDraft.newTopicDraftKey),
        initialCategoryId: category?.id,
      );
      composer = _buildTextComposer(
        target,
        persistsDraft: true,
        minimumRequiredTags: category?.minimumRequiredTags ?? 0,
      );
      _setComposer(composer);
      _notify();
      _composerDrafts.startNewDraft(composer);
    }

    try {
      await _composerDrafts.restoreTaskFor(composer);
    } catch (_) {}
    if (!forumActive ||
        !lease.isCurrent ||
        !_ownsComposer(composer) ||
        route?.sameDestinationAs(currentContent) != true ||
        !sourceIsCurrent() ||
        activeTabId != tabId) {
      return OpenComposerResult.sourceChanged;
    }
    switch (request.seed.placement) {
      case ComposerSeedPlacement.block:
        if (!composer.insertBlock(
          expectedValue: composer.value,
          markdown: request.seed.raw,
        )) {
          return OpenComposerResult.sourceChanged;
        }
    }
    composer.requestFocus();
    return OpenComposerResult.opened;
  }

  Future<TopicTagSearch> searchComposerTags(
    ComposerController composer,
    String term,
  ) async {
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);
    final held = await _credentialForWrite(target.siteUrl, lease: lease);
    if (!lease.isCurrent || !_ownsComposer(composer)) {
      return const TopicTagSearch();
    }
    if (held.failure case final failure?) {
      throw failure;
    }
    return held.request!.run(
      () => api.topicComposerQueries.searchTopicTags(
        siteUrl: target.siteUrl,
        apiKey: held.apiKey!,
        term: term,
        categoryId: composer.categoryId,
        selectedTagIds: composer.tags.map((tag) => tag.id).whereType<int>(),
        // Core rejects a page larger than the site's own setting outright, so
        // the site sets this and the client only caps what it will render.
        limit: siteConfigFor(
          target.siteUrl,
        ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
      ),
    );
  }

  Future<TopicTagSearch> searchTopicTagsForEditor({
    required String siteUrl,
    required int? categoryId,
    required Iterable<TopicTag> selectedTags,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final held = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return const TopicTagSearch();
    if (held.failure case final failure?) throw failure;
    return held.request!.run(
      () => api.topicComposerQueries.searchTopicTags(
        siteUrl: siteUrl,
        apiKey: held.apiKey!,
        term: term,
        categoryId: categoryId,
        selectedTagIds: selectedTags.map((tag) => tag.id).whereType<int>(),
        limit: siteConfigFor(
          siteUrl,
        ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
      ),
    );
  }

  Future<List<TopicCategory>> searchTopicCategoriesForEditor({
    required String siteUrl,
    required String term,
  }) => _taxonomy.searchTopicCategoriesForEditor(siteUrl: siteUrl, term: term);

  Future<void> changeComposerCategory(
    ComposerController composer,
    int? categoryId,
  ) async {
    final categories = topicComposerCategories(composer.target.siteUrl);
    TopicCategory? find(int? id) =>
        categories.where((category) => category.id == id).firstOrNull;
    final previous = find(composer.categoryId);
    final category = find(categoryId);
    composer.setCategory(
      categoryId,
      minimumRequiredTags: category?.minimumRequiredTags ?? 0,
    );
    composer.applyTopicTemplate(
      category?.topicTemplate,
      replacing: previous?.topicTemplate,
    );
    if (composer.tags.isEmpty) return;
    final kept = <TopicTag>[];
    for (final selected in composer.tags) {
      try {
        final result = await searchComposerTags(composer, selected.name);
        if (!_ownsComposer(composer) || composer.categoryId != categoryId) {
          return;
        }
        final match = result.results
            .where(
              (tag) =>
                  tag.id == selected.id ||
                  tag.name.toLowerCase() == selected.name.toLowerCase(),
            )
            .firstOrNull;
        if (!result.isForbidden && match != null && !match.disabled) {
          kept.add(match);
        }
      } catch (_) {
        return;
      }
    }
    if (!_ownsComposer(composer) || composer.categoryId != categoryId) {
      return;
    }
    if (kept.length != composer.tags.length) {
      composer.setTags(kept);
      composer.showTagRemovalNotice(categoryName: category?.name);
    }
  }

  void openReply({
    int? replyToPostNumber,
    String? replyToUsername,
    bool? replyingToWhisper,
    UserDraft? listedDraft,
    ShellTabContext? context,
  }) {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent || !identical(document.shell, this)) return;
    final instance = currentInstance;
    final route = document.currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !document.canReplyHere) return;
    final targetsWhisper =
        replyingToWhisper ??
        _replyTargetsWhisper(replyToPostNumber, topic: document.currentTopic);

    final existing =
        _composersForSite(instance.url).where((composer) {
          final target = composer.target;
          return target is ReplyComposerTarget && target.topicId == topicId;
        }).firstOrNull ??
        _composer;
    if (existing?.discarding == true) return;
    final existingTarget = existing?.target;
    if (existing != null &&
        !existing.closing &&
        existingTarget is ReplyComposerTarget &&
        existingTarget.topicId == topicId &&
        existingTarget.siteUrl == instance.url) {
      selectComposer(existing);
      existing.retarget(
        replyToPostNumber: replyToPostNumber,
        replyToUsername: replyToUsername,
        replyingToWhisper: targetsWhisper,
      );
      existing.focus.requestFocus();
      return;
    }

    if (!_replaceComposer()) return;
    final target = ReplyComposerTarget(
      siteUrl: instance.url,
      tabId: document.tabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: document.currentTopic?.title ?? route?.title ?? '',
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper: targetsWhisper,
      privateMessageTopic: document.currentTopic?.privateMessage ?? false,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _setComposer(composer);
    _notify();

    _composerDrafts.startRestore(composer, listedDraft: listedDraft);
  }

  bool _replyTargetsWhisper(int? postNumber, {TopicDetail? topic}) {
    if (postNumber == null) return false;
    final instance = currentInstance;
    topic ??= currentTopic;
    if (instance == null || topic == null) return false;
    for (final postId in topic.stream) {
      final post = store.read<Post>(instance.url, postId);
      if (post?.postNumber == postNumber) return post!.isWhisper;
    }
    return false;
  }

  Future<void> openQuote(
    Post post,
    String quote, {
    ShellTabContext? context,
  }) async {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent || !identical(document.shell, this)) return;
    final instance = currentInstance;
    final route = document.currentContent;
    final topicId = route?.topicId;
    if (instance == null ||
        topicId == null ||
        !document.canReplyHere ||
        quote.trim().isEmpty) {
      return;
    }

    var composer = _composer;
    final target = composer?.target;
    final reusesOpenReply =
        target is ReplyComposerTarget &&
        target.topicId == topicId &&
        target.siteUrl == instance.url;

    if (!reusesOpenReply) {
      openReply(
        context: document,
        replyToPostNumber: post.postNumber == 1 ? null : post.postNumber,
        replyToUsername: post.postNumber == 1 ? null : post.username,
        replyingToWhisper: post.postNumber != 1 && post.isWhisper,
      );
      composer = _composer;
    }
    if (composer == null) return;

    final restore = _ownsComposer(composer)
        ? _composerDrafts.restoreTaskFor(composer)
        : null;
    if (restore != null) {
      try {
        await restore;
      } catch (_) {}
    }

    if (isDisposed ||
        !_ownsComposer(composer) ||
        currentInstance?.url != instance.url ||
        !document.isCurrent ||
        !identical(document.currentContent, route)) {
      return;
    }
    if (!composer.insertBlock(expectedValue: composer.value, markdown: quote)) {
      return;
    }
    composer.focus.requestFocus();
  }

  void openEdit(Post post, {String? focusText, ShellTabContext? context}) {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent || !identical(document.shell, this)) return;
    final instance = currentInstance;
    final route = document.currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !post.canEdit) return;
    unawaited(_ensureTopicComposerCapabilities(instance.url));

    if (!_replaceComposer()) return;
    final detail = document.currentTopic;
    final editsTopic = post.postNumber == 1 && detail?.canEdit == true;
    // The site's original_title must use its stored title, before route text.
    final title = detail?.title ?? route?.title ?? '';
    final target = editsTopic
        ? TopicEditComposerTarget(
            siteUrl: instance.url,
            tabId: document.tabId,
            topicId: topicId,
            slug: route?.slug ?? '',
            topicTitle: title,
            editingPostId: post.id,
            initialCategoryId: detail?.categoryId,
            initialTags: detail?.tags ?? const [],
            privateMessageTopic: detail?.privateMessage ?? false,
          )
        : PostEditComposerTarget(
            siteUrl: instance.url,
            tabId: document.tabId,
            topicId: topicId,
            slug: route?.slug ?? '',
            topicTitle: title,
            editingPostId: post.id,
            editingPostNumber: post.postNumber,
            privateMessageTopic: detail?.privateMessage ?? false,
          );
    // No `onSaveDraft`: Discourse files a topic's drafts under one key, so
    // saving here would overwrite an unfinished reply with the text of a post
    // that is already published.
    final composer = _buildTextComposer(
      target,
      minimumRequiredTags: editsTopic
          ? categoryFor(
                  detail?.categoryId,
                  siteUrl: instance.url,
                )?.minimumRequiredTags ??
                0
          : 0,
    );
    _setComposer(composer);
    _notify();

    unawaited(_loadEditBody(composer, post, focusText: focusText));
  }

  Future<String?> saveFastEdit({
    required String siteUrl,
    required int topicId,
    required Post post,
    required String selectedMarkdown,
    required String replacement,
  }) async {
    final held = store.read<Post>(siteUrl, post.id);
    if (!_fastEditContextCurrent(siteUrl, topicId, post.id) ||
        held?.canEdit != true ||
        !siteConfigFor(siteUrl).fastEditEnabled) {
      return appL10n.thisPostCanNoLongerBeEdited;
    }
    if (held!.isLocalized) {
      return appL10n.openTheFullEditorToEditLocalizedContent;
    }
    if (selectedMarkdown.isEmpty) {
      return appL10n.theSelectedTextCouldNotBeMatchedSafely;
    }

    final lease = lifecycle.capture(siteUrl);
    final releasePost = _topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(post.id);
    if (releasePost == null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent ||
          !_fastEditContextCurrent(siteUrl, topicId, post.id)) {
        return appL10n.theTopicChangedBeforeTheEditCouldBeSaved;
      }
      if (credential.failure case final failure?) return failure.message;

      final fetched = await credential.request!.run(
        () => api.topicContent.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: [post.id],
          includeRaw: true,
          apiKey: credential.apiKey!,
        ),
      );
      if (!lease.isCurrent ||
          !_fastEditContextCurrent(siteUrl, topicId, post.id)) {
        return appL10n.theTopicChangedBeforeTheEditCouldBeSaved;
      }

      Post? current;
      for (final candidate in fetched) {
        if (candidate.id == post.id) {
          current = candidate;
          break;
        }
      }
      final raw = current?.raw;
      if (raw == null) {
        return appL10n.theSelectedTextCouldNotBeMatchedSafely;
      }
      final match = _uniqueTextMatch(raw, selectedMarkdown);
      if (match == null) {
        return appL10n.theSelectedTextCouldNotBeMatchedSafely;
      }
      final nextRaw = raw.replaceRange(match.start, match.end, replacement);
      if (nextRaw == raw) return null;

      final updated = await credential.request!.run(
        () => api.composerPersistence.updatePost(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          postId: post.id,
          raw: nextRaw,
          originalText: raw,
        ),
      );
      if (!lease.isCurrent ||
          !_fastEditContextCurrent(siteUrl, topicId, post.id)) {
        return appL10n.theTopicChangedBeforeTheEditCouldBeSaved;
      }
      lease.commit(() {
        _topicData
            .forLease(siteUrl, lease)
            ?.acceptEditedPost(updated, raw: nextRaw);
        _notify();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'post.fastEdit');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(releasePost);
    }
  }

  bool _fastEditContextCurrent(String siteUrl, int topicId, int postId) =>
      !isDisposed &&
      currentInstance?.url == siteUrl &&
      currentContent?.topicId == topicId &&
      currentTopic?.stream.contains(postId) == true;

  static ({int start, int end})? _uniqueTextMatch(
    String source,
    String selected,
  ) {
    final start = source.indexOf(selected);
    if (start < 0 || source.indexOf(selected, start + 1) >= 0) return null;
    return (start: start, end: start + selected.length);
  }

  Future<String?> saveTopicTitle({
    required String siteUrl,
    required int topicId,
    required String title,
    String? originalTitle,
  }) async {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail?.canEdit != true) {
      return appL10n.thisTopicCanNoLongerBeEdited;
    }
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) return appL10n.aTopicTitleIsRequired;
    if (nextTitle == detail!.title.trim()) return null;

    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheTitleSaved;
    if (credential.failure case final failure?) return failure.message;

    final TopicUpdate update;
    try {
      update = await credential.request!.run(
        () => api.topicMutations.updateTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          title: nextTitle,
          originalTitle: originalTitle ?? detail.title,
        ),
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'topic.editTitle');
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheTitleSaved;

    final stored = update.title ?? nextTitle;
    lease.commit(() {
      store.update<TopicDetail>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(title: stored),
      );
      store.update<Topic>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(title: stored),
      );
      _retitle(siteUrl, topicId, stored);
      _notify();
    });
    return null;
  }

  Future<String?> saveTopicCategory({
    required String siteUrl,
    required int topicId,
    required int categoryId,
  }) async {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail?.canEdit != true) {
      return appL10n.thisTopicCanNoLongerBeEdited;
    }
    if (detail!.categoryId == categoryId) return null;
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheCategorySaved;
    if (credential.failure case final failure?) return failure.message;

    final tags = await _tagsAllowedInCategory(
      siteUrl: siteUrl,
      credential: credential.request!,
      categoryId: categoryId,
      selected: detail.tags,
    );
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheCategorySaved;

    final TopicUpdate update;
    try {
      update = await credential.request!.run(
        () => api.topicMutations.updateTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          title: detail.title,
          originalTitle: detail.title,
          categoryId: categoryId,
          tags: tags,
          originalTags: detail.tags,
        ),
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'topic.editCategory');
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheCategorySaved;

    // The answer's title only echoes the baseline this write was accepted
    // against; its tags are the ones the site kept.
    final storedTags = update.tags ?? tags;
    lease.commit(() {
      store.update<TopicDetail>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(categoryId: categoryId, tags: storedTags),
      );
      store.update<Topic>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(categoryId: categoryId, tags: storedTags),
      );
      _updateTopicRouteMetadata(siteUrl, topicId, detail.title, categoryId);
      _notify();
    });
    return null;
  }

  Future<List<TopicTag>> _tagsAllowedInCategory({
    required String siteUrl,
    required AccountRequestCredentials credential,
    required int categoryId,
    required List<TopicTag> selected,
  }) async {
    if (selected.isEmpty) return selected;
    final kept = <TopicTag>[];
    for (final tag in selected) {
      try {
        final result = await credential.run(
          () => api.topicComposerQueries.searchTopicTags(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            term: tag.name,
            categoryId: categoryId,
            selectedTagIds: selected.map((item) => item.id).whereType<int>(),
            limit: siteConfigFor(
              siteUrl,
            ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
          ),
        );
        final match = result.results
            .where(
              (item) =>
                  item.id == tag.id ||
                  item.name.toLowerCase() == tag.name.toLowerCase(),
            )
            .firstOrNull;
        if (!result.isForbidden && match != null && !match.disabled) {
          kept.add(match);
        }
      } catch (_) {
        // A failed validation lookup must not silently remove existing tags.
        return selected;
      }
    }
    return List.unmodifiable(kept);
  }

  void openTagsEdit({ShellTabContext? context}) {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent || !identical(document.shell, this)) return;
    final instance = currentInstance;
    final route = document.currentContent;
    final detail = document.currentTopic;
    if (instance == null ||
        route?.topicId == null ||
        detail?.canEditTags != true) {
      return;
    }
    unawaited(_ensureTopicComposerCapabilities(instance.url));
    if (!_replaceComposer()) return;
    // A mega topic's run starts at the first post only when read from there.
    final firstId = detail!.stream.firstOrNull;
    final heldFirstPost =
        !detail.isMegaTopic ||
        (firstId != null &&
            store.read<Post>(instance.url, firstId)?.postNumber == 1);
    final target = TagsEditComposerTarget(
      siteUrl: instance.url,
      tabId: document.tabId,
      topicId: route!.topicId!,
      slug: route.slug ?? '',
      topicTitle: detail.title,
      firstPostId: heldFirstPost ? firstId : null,
      initialCategoryId: detail.categoryId,
      initialTags: detail.tags,
      privateMessageTopic: detail.privateMessage,
    );
    _setComposer(
      ComposerController(
        target,
        minimumRequiredTags:
            categoryFor(
              detail.categoryId,
              siteUrl: instance.url,
            )?.minimumRequiredTags ??
            0,
      ),
    );
    _notify();
  }

  Future<String?> updateTopicTagsFromSidebar({
    required String siteUrl,
    required int topicId,
    required Iterable<TopicTag> tags,
  }) async {
    if (currentInstance?.url != siteUrl ||
        currentContent?.topicId != topicId ||
        currentTopic?.canEditTags != true) {
      return appL10n.topicTagsCanNoLongerBeEdited;
    }
    final next = List<TopicTag>.unmodifiable(tags);
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return appL10n.theSiteChangedBeforeTagsWereSaved;
    if (credential.failure case final failure?) return failure.message;
    try {
      await credential.request!.run(
        () => api.topicMutations.updateTopicTags(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          tags: next,
        ),
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topicSidebar.editTopicTags',
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return appL10n.theSiteChangedBeforeTagsWereSaved;
    lease.commit(() {
      _applyTopicTags(siteUrl, topicId, next);
      _notify();
    });
    return null;
  }

  Future<void> _ensureTopicComposerCapabilities(String siteUrl) async {
    if (_topicComposerCapabilities.containsKey(siteUrl)) return;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent || credential.failure != null) return;
      final capabilities = await credential.request!.run(
        () => api.topicComposerQueries.topicComposerCapabilities(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
        ),
      );
      lease.commit(() {
        _topicComposerCapabilities[siteUrl] = capabilities;
        _notify();
      });
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.topicCapabilities',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  ComposerSearch _composerSearch(ComposerTarget target) {
    if (siteConfigFor(target.siteUrl).emojiEnabled) {
      unawaited(ensureEmojiCatalog(target.siteUrl));
    }

    final mentionTopicId = target.mentionTopicId;
    return (
      users: (term) async {
        final found = await _searchMentions(
          siteUrl: target.siteUrl,
          topicId: mentionTopicId != null && mentionTopicId > 0
              ? mentionTopicId
              : null,
          term: term,
        );
        return [
          for (final group in found.groups)
            ComposerSuggestion(
              kind: ComposerTriggerKind.mention,
              value: group.name,
              label: group.name,
              detail: group.fullName ?? appL10n.group,
              art: const ArtIcon(null, fallback: DIcons.users),
            ),
          for (final user in found.users)
            ComposerSuggestion(
              kind: ComposerTriggerKind.mention,
              value: user.username,
              label: user.username,
              detail: user.name,
              art: ArtAvatar(user.avatarUrl),
              siteUrl: target.siteUrl,
              userId: user.id,
              userStatus: user.status,
            ),
        ];
      },
      hashtags: (term) async {
        final found = await searchHashtags(siteUrl: target.siteUrl, term: term);
        return [
          for (final hashtag in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.hashtag,
              // The ref, not the slug: it is what the site cooks against, and
              // the only form that finds a subcategory or tells two things
              // that share a name apart.
              value: hashtag.ref,
              label: hashtag.text,
              detail: hashtag.secondaryText,
              art: _hashtagArt(target.siteUrl, hashtag),
            ),
        ];
      },
      emojis: (query) async {
        if (!siteConfigFor(target.siteUrl).emojiEnabled) return const [];
        final catalog = await ensureEmojiCatalog(target.siteUrl);
        if (catalog == null ||
            catalog.isEmpty ||
            !siteConfigFor(target.siteUrl).emojiEnabled) {
          return const [];
        }

        // Aliases are optional. Waiting for them gives the first query the
        // forum's active-locale vocabulary; a failed request leaves the
        // catalog's canonical-name search fully usable.
        await ensureEmojiSearchAliases(target.siteUrl);
        await emojiPickerStore.ensureLoaded(siteUrl: target.siteUrl);
        if (!siteConfigFor(target.siteUrl).emojiEnabled) return const [];
        final tone = emojiPickerStore.skinToneFor(siteUrl: target.siteUrl);
        final found = searchEmojis(target.siteUrl, query, limit: 5);
        return [
          for (final emoji in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.emoji,
              value: emoji.codeFor(tone),
              label: emoji.codeFor(tone),
              art: ArtImage(emoji.urlFor(tone)),
            ),
          ComposerSuggestion(
            kind: ComposerTriggerKind.emoji,
            value: query,
            label: appL10n.moreEmoji,
            art: const ArtIcon('discourse-emojis'),
            action: ComposerSuggestionAction.openEmojiPicker,
          ),
        ];
      },
    );
  }

  Future<void> _loadEditBody(
    ComposerController composer,
    Post post, {
    String? focusText,
  }) async {
    final target = composer.target;
    if (target is! PostEditingComposerTarget) return;
    if (post.raw case final raw?) {
      composer.loadedBody(raw, caretOffset: _editCaretOffset(raw, focusText));
      return;
    }

    composer.beginLoadingBody();
    final lease = lifecycle.capture(target.siteUrl);
    try {
      final credential = await AccountRequestSession(
        target.siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent || !_ownsComposer(composer)) {
        return;
      }
      final fetched = await credential.run(
        () => api.topicContent.posts(
          siteUrl: target.siteUrl,
          topicId: target.topicId,
          ids: [post.id],
          includeRaw: true,
          apiKey: credential.apiKey,
        ),
      );
      final raw = fetched.firstWhere((p) => p.id == post.id).raw;
      lease.commit(() {
        if (raw == null) {
          composer.bodyLoadFailed();
        } else {
          composer.loadedBody(
            raw,
            caretOffset: _editCaretOffset(raw, focusText),
          );
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'post.loadEditBody');
      lease.commit(composer.bodyLoadFailed);
    }
  }

  static int? _editCaretOffset(String raw, String? focusText) {
    final selection = focusText?.trim();
    if (selection == null || selection.isEmpty) return null;
    final firstLine = selection
        .split(RegExp(r'[\r\n]'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim()
        .replaceFirst(RegExp(r'^\*\s+'), '');
    if (firstLine.isEmpty) return 0;

    var match = raw.indexOf(firstLine);
    if (match < 0) {
      match = _plainQuoteCharacters(
        raw,
      ).indexOf(_plainQuoteCharacters(firstLine));
    }
    return match < 0 ? 0 : raw.lastIndexOf('\n', match - 1) + 1;
  }

  static String _plainQuoteCharacters(String value) =>
      value.replaceAll(RegExp('[“”]'), '"').replaceAll(RegExp('[‘’]'), "'");

  bool topicPostSelectionEnabled(String siteUrl, int topicId) =>
      _topicPostSelections.containsKey(_topicKey(siteUrl, topicId));

  Set<int> selectedTopicPostIds(String siteUrl, int topicId) =>
      Set.unmodifiable(
        _topicPostSelections[_topicKey(siteUrl, topicId)] ?? const <int>{},
      );

  bool isTopicPostSelected(String siteUrl, int topicId, int postId) =>
      _topicPostSelections[_topicKey(siteUrl, topicId)]?.contains(postId) ??
      false;

  List<Post> selectedTopicPosts(String siteUrl, int topicId) {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final selected = _topicPostSelections[_topicKey(siteUrl, topicId)];
    if (detail == null || selected == null || selected.isEmpty) return const [];
    return List.unmodifiable([
      for (final id in detail.stream)
        if (selected.contains(id)) ?store.read<Post>(siteUrl, id),
    ]);
  }

  bool topicPostSelectionWriteInFlight(String siteUrl, int topicId) =>
      _topicPostSelectionWrites.contains(_topicKey(siteUrl, topicId));

  void setTopicPostSelectionEnabled(String siteUrl, int topicId, bool enabled) {
    final key = _topicKey(siteUrl, topicId);
    if (enabled) {
      final topic = store.read<TopicDetail>(siteUrl, topicId);
      if (topic == null || !topic.canSelectPosts) return;
      if (_topicPostSelections.containsKey(key)) return;
      _topicPostSelections[key] = <int>{};
    } else {
      if (_topicPostSelectionWrites.contains(key) ||
          _topicPostSelections.remove(key) == null) {
        return;
      }
    }
    _notify();
  }

  void toggleTopicPostSelected(String siteUrl, int topicId, int postId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selected == null ||
        topic == null ||
        !topic.canSelectPosts ||
        _topicPostSelectionWrites.contains(key) ||
        !topic.stream.contains(postId) ||
        store.read<Post>(siteUrl, postId) == null) {
      return;
    }
    if (!selected.remove(postId)) selected.add(postId);
    _notify();
  }

  void selectAllLoadedTopicPosts(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selected == null ||
        topic == null ||
        !topic.canSelectPosts ||
        _topicPostSelectionWrites.contains(key)) {
      return;
    }
    selected
      ..clear()
      ..addAll(
        topic.stream.where((id) => store.read<Post>(siteUrl, id) != null),
      );
    _notify();
  }

  void clearSelectedTopicPosts(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    if (selected == null ||
        selected.isEmpty ||
        _topicPostSelectionWrites.contains(key)) {
      return;
    }
    selected.clear();
    _notify();
  }

  Future<String?> deleteSelectedTopicPosts(String siteUrl, int topicId) {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.isEmpty ||
        posts.any((post) => !post.canDelete)) {
      return Future.value();
    }
    return _mutateSelectedTopicPosts(
      siteUrl,
      topicId,
      posts,
      (apiKey, ids) => api.postMutations.deletePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postIds: ids,
      ),
    );
  }

  Future<String?> mergeSelectedTopicPosts(String siteUrl, int topicId) {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.length < 2 ||
        posts.any((post) => !post.canDelete) ||
        posts.map((post) => post.username).toSet().length != 1) {
      return Future.value();
    }
    return _mutateSelectedTopicPosts(
      siteUrl,
      topicId,
      posts,
      (apiKey, ids) => api.postMutations.mergePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postIds: ids,
      ),
    );
  }

  TopicPostMoveTarget captureTopicPostMoveTarget(String siteUrl, int topicId) =>
      TopicPostMoveTarget._(
        siteUrl: siteUrl,
        topicId: topicId,
        privateMessage:
            store.read<TopicDetail>(siteUrl, topicId)?.privateMessage ?? false,
        lease: lifecycle.capture(siteUrl),
      );

  static String get _obsoleteTopicPostMove =>
      appL10n.yourConnectionChangedReopenMovePostsAndTryAgain;

  bool isTopicPostMoveTargetCurrent(TopicPostMoveTarget target) =>
      !isDisposed && target._lease.isCurrent;

  /// Whether a message's posts may start a new message. The server accepts it
  /// from any staff member, but web offers it to admins only.
  bool canMoveTopicPostsToNewMessage(TopicPostMoveTarget target) =>
      currentUserFor(target.siteUrl)?.admin == true;

  String? _topicPostMoveRefusal(
    TopicPostMoveTarget target, {
    List<int>? postIds,
    bool newTopic = false,
  }) {
    if (!isTopicPostMoveTargetCurrent(target)) return _obsoleteTopicPostMove;
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    final forbidden = const WriteException(WriteFailure.forbidden).message;
    if (topic == null || !topic.canMovePosts) return forbidden;
    // A move is sent with the archetype it was offered in, and one sent as a
    // topic publishes a message's posts in a new public topic.
    if (topic.privateMessage != target.privateMessage) return forbidden;
    if (postIds == null) return null;
    if (postIds.isEmpty ||
        postIds.any(
          (id) =>
              !topic.stream.contains(id) ||
              store.read<Post>(target.siteUrl, id) == null,
        )) {
      return forbidden;
    }
    if (newTopic &&
        (postIds.length == topic.stream.length ||
            store.read<Post>(target.siteUrl, postIds.first)?.postType !=
                Post.regularPostType ||
            (target.privateMessage &&
                !canMoveTopicPostsToNewMessage(target)))) {
      return forbidden;
    }
    return null;
  }

  Future<TopicMoveDestinationSearchResult> searchTopicMoveDestinations(
    TopicPostMoveTarget target,
    String term,
  ) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final trimmed = term.trim();
    if (_topicPostMoveRefusal(target) case final error?) {
      return (destinations: const <TopicMoveDestination>[], error: error);
    }
    if (trimmed.isEmpty) {
      return (destinations: const <TopicMoveDestination>[], error: null);
    }
    final credential = await _credentialForWrite(siteUrl, lease: target._lease);
    if (_topicPostMoveRefusal(target) case final error?) {
      return (destinations: const <TopicMoveDestination>[], error: error);
    }
    if (credential.failure case final failure?) {
      return (
        destinations: const <TopicMoveDestination>[],
        error: failure.message,
      );
    }
    try {
      // The server refuses a move between a message and a topic, so each
      // searches only its own archetype, as web's topic and message choosers
      // do.
      final results = await credential.request!.run(
        () => api.search.searchPosts(
          siteUrl: siteUrl,
          term: trimmed,
          typeFilter: target.privateMessage ? 'private_messages' : 'topic',
          searchForId: true,
          restrictToArchetype: target.privateMessage
              ? 'private_message'
              : 'regular',
          apiKey: credential.apiKey,
        ),
      );
      if (_topicPostMoveRefusal(target) case final error?) {
        return (destinations: const <TopicMoveDestination>[], error: error);
      }
      final seen = <int>{};
      return (
        destinations: List<TopicMoveDestination>.unmodifiable([
          for (final hit in results.hits)
            if (hit.topicId != topicId &&
                hit.privateMessage == target.privateMessage &&
                seen.add(hit.topicId))
              (id: hit.topicId, title: hit.topicTitle, slug: hit.topicSlug),
        ]),
        error: results.error,
      );
    } on WriteException catch (error) {
      return (
        destinations: const <TopicMoveDestination>[],
        error: _topicPostMoveRefusal(target) ?? error.message,
      );
    } catch (error, stackTrace) {
      if (isTopicPostMoveTargetCurrent(target)) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.selectedPosts.searchDestination',
          severity: DiagnosticSeverity.warning,
        );
      }
      return (
        destinations: const <TopicMoveDestination>[],
        error:
            _topicPostMoveRefusal(target) ??
            const WriteException(WriteFailure.unreachable).message,
      );
    }
  }

  Future<TopicPostMoveResult> moveSelectedTopicPostsToExisting(
    TopicPostMoveTarget target,
    int destinationTopicId, {
    bool chronologicalOrder = false,
  }) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final posts = selectedTopicPosts(siteUrl, topicId);
    if (_topicPostMoveRefusal(
          target,
          postIds: [for (final post in posts) post.id],
        )
        case final error?) {
      return (destinationUrl: null, error: error);
    }
    if (destinationTopicId <= 0 || destinationTopicId == topicId) {
      return (
        destinationUrl: null,
        error: const WriteException(WriteFailure.forbidden).message,
      );
    }
    String? destinationUrl;
    final error = await _mutateSelectedTopicPosts(siteUrl, topicId, posts, (
      apiKey,
      ids,
    ) async {
      if (_topicPostMoveRefusal(target, postIds: ids) case final error?) {
        throw WriteException(WriteFailure.forbidden, errors: [error]);
      }
      destinationUrl = await api.postMutations.movePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        destinationTopicId: destinationTopicId,
        chronologicalOrder: chronologicalOrder,
        privateMessage: target.privateMessage,
      );
      // PostMover publishes nothing to the destination's readers, so a copy
      // held from an earlier visit would open without the arrived posts.
      target._lease.commit(
        () => _topicData.forSite(siteUrl).refreshWhenOpened(destinationTopicId),
      );
    });
    if (!isTopicPostMoveTargetCurrent(target)) {
      return (destinationUrl: null, error: _obsoleteTopicPostMove);
    }
    return (
      destinationUrl: error == null ? destinationUrl : null,
      error: error,
    );
  }

  Future<TopicPostMoveResult> moveSelectedTopicPostsToNew(
    TopicPostMoveTarget target, {
    required String title,
    int? categoryId,
    List<int> tagIds = const [],
  }) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final posts = selectedTopicPosts(siteUrl, topicId);
    if (_topicPostMoveRefusal(
          target,
          postIds: [for (final post in posts) post.id],
          newTopic: true,
        )
        case final error?) {
      return (destinationUrl: null, error: error);
    }
    if (title.trim().isEmpty || (target.privateMessage && categoryId != null)) {
      return (
        destinationUrl: null,
        error: const WriteException(WriteFailure.forbidden).message,
      );
    }
    String? destinationUrl;
    final error = await _mutateSelectedTopicPosts(siteUrl, topicId, posts, (
      apiKey,
      ids,
    ) async {
      if (_topicPostMoveRefusal(target, postIds: ids, newTopic: true)
          case final error?) {
        throw WriteException(WriteFailure.forbidden, errors: [error]);
      }
      destinationUrl = await api.postMutations.movePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        title: title,
        categoryId: categoryId,
        tagIds: tagIds,
        privateMessage: target.privateMessage,
      );
    });
    if (!isTopicPostMoveTargetCurrent(target)) {
      return (destinationUrl: null, error: _obsoleteTopicPostMove);
    }
    return (
      destinationUrl: error == null ? destinationUrl : null,
      error: error,
    );
  }

  bool canChangeSelectedTopicPostOwner(String siteUrl, int topicId) {
    if (currentInstance?.url != siteUrl ||
        currentInstance?.user?.canChangePostOwner != true) {
      return false;
    }
    final posts = selectedTopicPosts(siteUrl, topicId);
    return posts.isNotEmpty &&
        posts.map((post) => post.username).toSet().length == 1;
  }

  Future<String?> changeSelectedTopicPostOwner(
    TopicPostOwnerTarget target,
    String username,
  ) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final posts = selectedTopicPosts(siteUrl, topicId);
    final postIds = [for (final post in posts) post.id];
    final trimmedUsername = username.trim();
    if (target.postId != null) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (_topicPostOwnerRefusal(target, postIds, trimmedUsername)
        case final error?) {
      return error;
    }
    final error = await _mutateSelectedTopicPosts(siteUrl, topicId, posts, (
      apiKey,
      ids,
    ) async {
      if (_topicPostOwnerRefusal(target, ids, trimmedUsername)
          case final error?) {
        throw WriteException(WriteFailure.forbidden, errors: [error]);
      }
      await api.postMutations.changePostOwners(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        username: trimmedUsername,
      );
    });
    return _ownsTopicPostOwnerTarget(target) ? error : _obsoleteTopicPostOwner;
  }

  bool canChangeTopicPostOwner(Post post) {
    final instance = currentInstance;
    final topic = currentTopic;
    return instance?.isConnected == true &&
        instance?.user?.canChangePostOwner == true &&
        topic != null &&
        topic.stream.contains(post.id) &&
        store.read<Post>(instance!.url, post.id) != null;
  }

  TopicPostOwnerTarget captureTopicPostOwnerTarget({
    required String siteUrl,
    required int topicId,
    int? postId,
  }) => TopicPostOwnerTarget._(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: postId,
    lease: lifecycle.capture(siteUrl),
  );

  static String get _obsoleteTopicPostOwner =>
      appL10n.yourConnectionChangedReopenChangeOwnerAndTryAgain;

  bool _ownsTopicPostOwnerTarget(TopicPostOwnerTarget target) =>
      !isDisposed && target._lease.isCurrent;

  String? _topicPostOwnerRefusal(
    TopicPostOwnerTarget target,
    List<int> postIds,
    String username,
  ) {
    if (!_ownsTopicPostOwnerTarget(target)) return _obsoleteTopicPostOwner;
    final instance = _instanceAt(target.siteUrl);
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    final posts = [
      for (final id in postIds) ?store.read<Post>(target.siteUrl, id),
    ];
    if (instance?.isConnected != true ||
        instance?.user?.canChangePostOwner != true ||
        topic == null ||
        (target.postId == null &&
            (currentInstance?.url != target.siteUrl ||
                !topic.canSelectPosts)) ||
        postIds.isEmpty ||
        posts.length != postIds.length ||
        postIds.any((id) => !topic.stream.contains(id)) ||
        posts.map((post) => post.username).toSet().length != 1 ||
        username.isEmpty ||
        posts.first.username == username) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    return null;
  }

  Future<List<FoundUser>> searchTopicPostOwnerUsers(
    TopicPostOwnerTarget target,
    String term,
  ) async {
    if (!_ownsTopicPostOwnerTarget(target)) return const [];
    final users = await searchUsers(
      siteUrl: target.siteUrl,
      topicId: target.topicId,
      term: term,
    );
    return _ownsTopicPostOwnerTarget(target) ? users : const [];
  }

  Future<String?> changeTopicPostOwner(
    TopicPostOwnerTarget target,
    String username,
  ) async {
    final postId = target.postId;
    if (postId == null) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    final siteUrl = target.siteUrl;
    final lease = target._lease;
    final trimmedUsername = username.trim();
    String? refusal() =>
        _topicPostOwnerRefusal(target, [postId], trimmedUsername);
    if (refusal() case final error?) return error;
    final releasePost = _topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(postId);
    if (releasePost == null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // The write guard notifies listeners. Recheck the opening account and
      // current target records both there and after acquiring credentials.
      if (refusal() case final error?) return error;
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (refusal() case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      await credential.request!.run(
        () => api.postMutations.changePostOwners(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: target.topicId,
          postIds: [postId],
          username: trimmedUsername,
        ),
      );
      if (!_ownsTopicPostOwnerTarget(target)) return _obsoleteTopicPostOwner;
      await _topicData
          .forLease(siteUrl, lease)
          ?.repairPost(target.topicId, postId, credential.apiKey, lease);
      return _ownsTopicPostOwnerTarget(target) ? null : _obsoleteTopicPostOwner;
    } on WriteException catch (error) {
      return _ownsTopicPostOwnerTarget(target)
          ? error.message
          : _obsoleteTopicPostOwner;
    } catch (error, stackTrace) {
      if (!_ownsTopicPostOwnerTarget(target)) return _obsoleteTopicPostOwner;
      _reportOperationalError(error, stackTrace, 'post.changeOwner');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(releasePost);
    }
  }

  Future<String?> deletePost(Post post) async {
    if (!post.canDelete) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null && _topicData.forSite(siteUrl).postWriting(post.id)) {
      return null;
    }
    final editing = switch (_composer?.target) {
      PostEditingComposerTarget(:final editingPostId)
          when editingPostId == post.id =>
        _composer,
      TaxonomyEditComposerTarget(:final firstPostId)
          when firstPostId == post.id =>
        _composer,
      _ => null,
    };

    final error = await _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.deletePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
    );

    if (error == null && _ownsComposer(editing)) {
      closeComposer(composer: editing);
    }
    return error;
  }

  bool canPermanentlyDeletePost(Post post) {
    final topic = currentTopic;
    return topic != null && _canPermanentlyDeletePost(topic, post);
  }

  bool _canPermanentlyDeletePost(TopicDetail topic, Post post) =>
      post.isDeleted &&
      topic.stream.contains(post.id) &&
      (post.postNumber == 1
          ? topic.deletedAt != null && topic.canPermanentlyDelete
          : post.canPermanentlyDelete);

  PostPermanentDeleteTarget capturePostPermanentDeleteTarget({
    required String siteUrl,
    required int topicId,
    required Post post,
  }) => PostPermanentDeleteTarget._(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: post.id,
    postNumber: post.postNumber,
    lease: lifecycle.capture(siteUrl),
  );

  static String get _obsoletePermanentPostDeletion =>
      appL10n.yourConnectionChangedReopenTheActionAndTryAgain;

  String? _permanentPostDeletionRefusal(PostPermanentDeleteTarget target) {
    if (isDisposed || !target._lease.isCurrent) {
      return _obsoletePermanentPostDeletion;
    }
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    final post = store.read<Post>(target.siteUrl, target.postId);
    if (_instanceAt(target.siteUrl)?.isConnected != true ||
        topic == null ||
        post == null ||
        post.postNumber != target.postNumber ||
        !_canPermanentlyDeletePost(topic, post)) {
      return appL10n.thisPostCannotBePermanentlyDeleted;
    }
    return null;
  }

  Future<String?> checkPermanentPostDeletion(
    PostPermanentDeleteTarget target,
  ) async {
    if (_permanentPostDeletionRefusal(target) case final error?) return error;
    final lease = target._lease;
    try {
      final credential = await _credentialForWrite(
        target.siteUrl,
        lease: lease,
        withClientId: true,
      );
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      final result = await credential.request!.run(
        () => api.postMutations.checkPermanentPostDeletion(
          siteUrl: target.siteUrl,
          apiKey: credential.apiKey!,
          postId: target.postId,
          clientId: clientId,
        ),
      );
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      return result.allowed
          ? null
          : result.reason ?? appL10n.thisPostCannotBePermanentlyDeletedYet;
    } catch (error, stackTrace) {
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }
      _reportOperationalError(
        error,
        stackTrace,
        'post.permanentDeletionCheck',
        severity: DiagnosticSeverity.warning,
      );
      return const WriteException(WriteFailure.unreachable).message;
    }
  }

  Future<String?> permanentlyDeletePost(
    PostPermanentDeleteTarget target,
  ) async {
    if (_permanentPostDeletionRefusal(target) case final error?) return error;
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final postId = target.postId;
    final lease = target._lease;
    final topicKey = _topicKey(siteUrl, topicId);
    void Function()? releasePost;
    if (target.deletesTopic) {
      if (!_topicDeletionWrites.add(topicKey)) {
        return appL10n.anotherTopicActionIsStillFinishing;
      }
      _notify();
    } else if ((releasePost = _topicData
            .forLease(siteUrl, lease)
            ?.beginPostWrite(postId)) ==
        null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // The write guard notifies listeners. Retain the opening account even
      // if a listener replaces it before credentials are read.
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      final credential = await _credentialForWrite(
        siteUrl,
        lease: lease,
        withClientId: target.deletesTopic,
      );
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      if (!target.deletesTopic) {
        await credential.request!.run(
          () => api.postMutations.permanentlyDeletePost(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            postId: postId,
          ),
        );
        if (!lease.isCurrent || isDisposed) {
          return _obsoletePermanentPostDeletion;
        }
        await _topicData
            .forLease(siteUrl, lease)
            ?.repairPost(topicId, postId, credential.apiKey, lease);
        return lease.isCurrent && !isDisposed
            ? null
            : _obsoletePermanentPostDeletion;
      }

      final clientId = credential.request!.clientId;
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      await credential.request!.run(
        () => api.topicMutations.permanentlyDeleteTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }
      lease.commit(() {
        _topicData.forLease(siteUrl, lease)?.removeTopicPermanently(topicId);
        _notify();
      });
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }
      if (currentInstance?.url == siteUrl &&
          currentContent?.topicId == topicId) {
        handleBack(canReturnToSidebar: false);
      }
      return null;
    } on WriteException catch (error) {
      return lease.isCurrent && !isDisposed
          ? error.message
          : _obsoletePermanentPostDeletion;
    } catch (error, stackTrace) {
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }
      _reportOperationalError(
        error,
        stackTrace,
        target.deletesTopic
            ? 'topic.permanentlyDelete'
            : 'post.permanentlyDelete',
      );
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        if (target.deletesTopic) {
          _topicDeletionWrites.remove(topicKey);
          _notify();
        } else {
          releasePost?.call();
        }
      });
    }
  }

  Future<String?> recoverPost(Post post) async {
    if (!post.canRecover) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null && _topicData.forSite(siteUrl).postWriting(post.id)) {
      return null;
    }
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.recoverPost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
      // PostDestroyer#recover also recovers the topic of a first post, and the
      // only topic message it publishes is a stats one, so the held topic has
      // to be recovered here, as after the header's recover.
      accepted: post.postNumber == 1
          ? (siteUrl, topicId, lease) =>
                _applyTopicDeletion(siteUrl, topicId, false, lease)
          : null,
    );
  }

  Future<String?> setPostWiki(Post post, bool wiki) {
    if (!post.canWiki || post.wiki == wiki) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostWiki(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        wiki: wiki,
      ),
    );
  }

  bool canLockPost(Post post) =>
      currentInstance?.user?.staff == true && post.userId != null;

  Future<String?> setPostLocked(Post post, bool locked) {
    if (!canLockPost(post) || post.locked == locked) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostLocked(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        locked: locked,
      ),
    );
  }

  bool canUnhidePost(Post post) =>
      currentInstance?.user?.staff == true && post.hidden;

  Future<String?> unhidePost(Post post) {
    if (!canUnhidePost(post)) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.unhidePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
    );
  }

  bool canTogglePostType(Post post) =>
      currentInstance?.user?.staff == true && !post.isWhisper;

  Future<String?> togglePostType(Post post) {
    if (!canTogglePostType(post)) return Future.value();
    final nextType = post.isModeratorAction
        ? Post.regularPostType
        : Post.moderatorPostType;
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostType(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        postType: nextType,
      ),
    );
  }

  bool canEditPostNotice({
    required String siteUrl,
    required int topicId,
    required int postId,
  }) {
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    return _instanceAt(siteUrl)?.isConnected == true &&
        topic?.canEditStaffNotes == true &&
        topic!.stream.contains(postId) &&
        store.read<Post>(siteUrl, postId) != null;
  }

  PostNoticeTarget capturePostNoticeTarget({
    required String siteUrl,
    required int topicId,
    required int postId,
  }) => PostNoticeTarget._(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: postId,
    lease: lifecycle.capture(siteUrl),
  );

  static String get _obsoletePostNotice =>
      appL10n.yourConnectionChangedReopenThePostNoticeAndTryAgain;

  String? _postNoticeRefusal(PostNoticeTarget target) {
    if (isDisposed || !target._lease.isCurrent) return _obsoletePostNotice;
    if (!canEditPostNotice(
      siteUrl: target.siteUrl,
      topicId: target.topicId,
      postId: target.postId,
    )) {
      return appL10n.thisPostNoticeCanNoLongerBeEdited;
    }
    return null;
  }

  Future<String?> setPostNotice(PostNoticeTarget target, String? notice) async {
    if (_postNoticeRefusal(target) case final error?) return error;
    final siteUrl = target.siteUrl;
    final postId = target.postId;
    final lease = target._lease;
    final next = notice == null || notice.trim().isEmpty ? null : notice;
    if (next == store.read<Post>(siteUrl, postId)?.notice?.raw) return null;
    final releasePost = _topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(postId);
    if (releasePost == null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // Acquiring the write guard notifies listeners, which may retire the
      // opening account. Keep that lease through credential reads and refresh.
      if (_postNoticeRefusal(target) case final error?) return error;
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (_postNoticeRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      if (next == store.read<Post>(siteUrl, postId)?.notice?.raw) return null;

      await credential.request!.run(
        () => api.postMutations.updatePostNotice(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          postId: postId,
          notice: next,
        ),
      );
      if (!lease.isCurrent) return _obsoletePostNotice;
      await _topicData
          .forLease(siteUrl, lease)
          ?.repairPost(target.topicId, postId, credential.apiKey, lease);
      return lease.isCurrent ? null : _obsoletePostNotice;
    } on WriteException catch (error) {
      return lease.isCurrent ? error.message : _obsoletePostNotice;
    } catch (error, stackTrace) {
      if (!lease.isCurrent) return _obsoletePostNotice;
      _reportOperationalError(error, stackTrace, 'post.setNotice');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(releasePost);
    }
  }

  Future<String?> createPostFlag(
    String siteUrl,
    Post post,
    PostFlagType flagType, {
    String? message,
  }) async {
    final instance = _instanceAt(siteUrl);
    final held = store.read<Post>(siteUrl, post.id);
    PostFlagType? currentType;
    for (final type in postFlagTypesFor(siteUrl)) {
      if (type.id == flagType.id) {
        currentType = type;
        break;
      }
    }
    if (instance?.isConnected != true) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        held.hidden ||
        held.isDeleted ||
        held.actedFlagSummaries.isNotEmpty ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToPost ||
        !held.canFlagWith(currentType.id)) {
      return appL10n.thisPostCanNoLongerBeFlagged;
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = siteConfigFor(siteUrl).minPersonalMessagePostLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return appL10n.yourMessageMustBeBetweenAndCharacters(
        (minimum).toString(),
        (PostFlagType.maximumMessageLength).toString(),
      );
    }

    final lease = lifecycle.capture(siteUrl);
    final releasePost = _topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(held.id);
    if (releasePost == null) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }
    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent) {
        return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        final flagActionTypeId = currentType.id;
        final fresh = await credential.request!.run(
          () => api.postMutations.createPostFlag(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            postId: held.id,
            postActionTypeId: flagActionTypeId,
            message: submittedMessage,
          ),
        );
        if (!lease.isCurrent) {
          return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
        }
        lease.commit(() {
          _topicData.forLease(siteUrl, lease)?.acceptPostAction(fresh);
          _notify();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'post.flag');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      lease.commit(releasePost);
    }
  }

  bool topicFlagWriteInFlight(String siteUrl, int topicId) =>
      _topicFlagWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> createTopicFlag(
    String siteUrl,
    TopicDetail topic,
    PostFlagType flagType, {
    String? message,
  }) async {
    final instance = _instanceAt(siteUrl);
    final held = store.read<TopicDetail>(siteUrl, topic.id);
    final currentType = _postActionCatalogs[siteUrl]?.topicFlags
        .where((type) => type.id == flagType.id)
        .firstOrNull;
    if (instance?.isConnected != true) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToTopic ||
        !held.canFlagWith(currentType.id)) {
      return appL10n.thisTopicCanNoLongerBeFlagged;
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = siteConfigFor(siteUrl).minPersonalMessagePostLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return appL10n.yourMessageMustBeBetweenAndCharacters(
        (minimum).toString(),
        (PostFlagType.maximumMessageLength).toString(),
      );
    }

    final key = _topicKey(siteUrl, held.id);
    if (!_topicFlagWrites.add(key)) {
      return appL10n.anotherFlagOnThisTopicIsStillBeingSaved;
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent) {
        return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        await credential.request!.run(
          () => api.postMutations.createTopicFlag(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: held.id,
            postActionTypeId: currentType.id,
            message: submittedMessage,
          ),
        );
        if (!lease.isCurrent) {
          return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
        }
        lease.commit(() {
          store.update<TopicDetail>(
            siteUrl,
            held.id,
            (current) => current.withTopicFlag(currentType.id),
          );
          _notify();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'topic.flag');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      lease.commit(() {
        _topicFlagWrites.remove(key);
        _notify();
      });
    }
  }

  final _postChecklistWrites = <String, PostChecklistWrite>{};
  int _checklistMutationSequence = 0;

  Future<String?> togglePostChecklist({
    required String siteUrl,
    required int topicId,
    required Post post,
    required PostChecklistTarget target,
    required bool checked,
  }) async {
    final instance = _instanceAt(siteUrl);
    final held = store.read<Post>(siteUrl, post.id);
    if (instance?.isConnected != true ||
        held?.canEdit != true ||
        held!.isLocalized ||
        held.isDeleted ||
        topicId <= 0) {
      return null;
    }
    final key = _postKey(siteUrl, post.id);
    final active = _postChecklistWrites[key];
    if (active != null && active.isCurrent()) {
      active.toggle(post, target, checked);
      return null;
    }
    if (postWriteInFlight(post.id, siteUrl: siteUrl) &&
        !_bookmarks.forSite(siteUrl).postBookmarkWriting(post.id)) {
      return appL10n.anotherPostActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    final data = _topicData.forLease(siteUrl, lease);
    if (data == null) return null;
    String? apiKey;
    AccountRequestCredentials? requestCredential;
    late final PostChecklistWrite operation;
    operation = PostChecklistWrite(
      post: held,
      isCurrent: () =>
          lease.isCurrent && identical(_postChecklistWrites[key], operation),
      publish: data.publishChecklist,
      load: () async {
        final fresh = await data.checklistPost(topicId, post.id, apiKey);
        if (fresh == null || fresh.raw == null || fresh.updatedAt == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
        return fresh;
      },
      save: (baseline, toggles) => requestCredential!.run(
        () => api.postMutations.togglePostChecklist(
          siteUrl: siteUrl,
          apiKey: apiKey!,
          postId: post.id,
          toggles: toggles,
          expectedRaw: baseline.raw!,
          expectedUpdatedAt: baseline.updatedAt!,
          mutationId:
              'native-${DateTime.now().microsecondsSinceEpoch}-${_checklistMutationSequence++}',
        ),
      ),
    );
    _postChecklistWrites[key] = operation;
    final releasePost = data.holdPostWrite(post.id);
    try {
      if (!operation.toggle(post, target, checked)) return null;
      if (!lease.isCurrent) return null;
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) {
        operation.reject();
        return failure.message;
      }
      apiKey = credential.apiKey!;
      requestCredential = credential.request!;
      return await operation.run();
    } finally {
      if (identical(_postChecklistWrites[key], operation)) {
        _postChecklistWrites.remove(key);
      }
      lease.commit(releasePost);
    }
  }

  Future<String?> toggleLike(Post post, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || !post.canToggleLike) return null;
    // A completed write can precede the frame that replaces its old button.
    final held = store.read<Post>(targetSite, post.id);
    if (held != null && held.liked != post.liked) return null;

    final lease = lifecycle.capture(targetSite);
    final releasePost = _topicData
        .forLease(targetSite, lease)
        ?.beginPostWrite(post.id);
    if (releasePost == null) return null;

    try {
      return await _writeLike(targetSite, post, lease);
    } finally {
      lease.commit(releasePost);
    }
  }

  Future<String?> _writeLike(String siteUrl, Post post, SiteLease lease) async {
    final credential = await _credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return null;
    if (credential.failure case final failure?) return failure.message;
    final apiKey = credential.apiKey!;
    final data = _topicData.forLease(siteUrl, lease);
    if (data == null) return null;

    final liked = !post.liked;
    // Apply the guess to the current store value: a re-read can land during
    // credential lookup, and a 204 response will not correct a stale put.
    final applied = lease.commit(() {
      data.guessLike(post.id, liked);
      _notify();
    });
    if (!applied || !lease.isCurrent) return null;

    void revert() {
      lease.commit(() {
        data.rejectLike(post.id, guessed: liked, original: post.liked);
        _notify();
      });
    }

    try {
      final fresh = liked
          ? await credential.request!.run(
              () => api.postMutations.likePost(
                siteUrl: siteUrl,
                apiKey: apiKey,
                postId: post.id,
              ),
            )
          : await credential.request!.run(
              () => api.postMutations.unlikePost(
                siteUrl: siteUrl,
                apiKey: apiKey,
                postId: post.id,
              ),
            );
      // A route that answered with nothing still did the thing it was asked to
      // — the guess above stands until the post is read again.
      if (fresh != null) {
        lease.commit(() {
          data.acceptPostAction(fresh);
          _notify();
        });
      }
    } on WriteException catch (e) {
      revert();
      return e.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'post.toggleLike');
      }
      revert();
      return const WriteException(WriteFailure.unreachable).message;
    }
    return null;
  }

  bool postWriteInFlight(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    return targetSite != null &&
        _topicData.forSite(targetSite).postWriting(postId);
  }

  final Map<String, Set<int>> _topicPostSelections = {};
  final Set<String> _topicPostSelectionWrites = {};
  final Set<String> _topicFlagWrites = {};

  @override
  BookmarkTargetHost bookmarkTarget(BookmarkTargetType targetType) =>
      _bookmarks.bookmarkTarget(targetType);

  Topic _prepareTopicForStore(
    String siteUrl,
    Topic incoming,
    int? versionAtDispatch,
  ) => _bookmarks
      .forSite(siteUrl)
      .prepareRow(
        _projectTopicTracking(siteUrl, _topicReads.project(siteUrl, incoming)),
        versionAtDispatch,
      );

  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarks
      .forSite(siteUrl)
      .bookmarkWriteInFlight(
        topicId: topicId,
        targetType: targetType,
        targetId: targetId,
      );
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _bookmarks
      .forSite(siteUrl)
      .createBookmark(
        topicId: topicId,
        targetType: targetType,
        targetId: targetId,
        name: name,
        reminderAt: reminderAt,
        autoDeletePreference: autoDeletePreference,
      );
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _bookmarks
      .forSite(siteUrl)
      .updateBookmark(
        topicId: topicId,
        bookmark: bookmark,
        name: name,
        reminderAt: reminderAt,
        autoDeletePreference: autoDeletePreference,
      );
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => _bookmarks
      .forSite(siteUrl)
      .clearBookmarkReminder(topicId: topicId, bookmark: bookmark);
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => _bookmarks
      .forSite(siteUrl)
      .deleteBookmark(topicId: topicId, bookmark: bookmark);
  @override
  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required String siteUrl,
    required int topicId,
  }) => _bookmarks.forSite(siteUrl).deleteAllTopicBookmarks(topicId: topicId);

  static String _postKey(String siteUrl, int postId) => '$siteUrl~$postId';

  PostLikers? likers(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return store.read<PostLikers>(targetSite, postId);
  }

  String? likersError(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return likerRequests.errorFor(targetSite, postId);
  }

  // Every hover-open of a like count lands here, so progress and failures
  // go to [likerRequests] and the likers to [store], never to the facade.
  Future<void> loadLikers(int postId, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;

    // Captured before the fetch is announced, so a listener that replaces
    // the account cannot hand this fetch the new one.
    final lease = lifecycle.capture(targetSite);
    if (!likerRequests.begin(targetSite, postId)) return;
    String? failure;

    try {
      final credential = await AccountRequestSession(
        targetSite,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final fetched = await credential.run(
        () => api.topicContent.postLikers(
          siteUrl: targetSite,
          postId: postId,
          // Keep credential reads inside the guarded try: macOS entitlement
          // failures must not strand the fetch in [likerRequests].
          apiKey: credential.apiKey,
        ),
      );
      lease.commit(() => store.put(targetSite, fetched));
    } on SiteLookupException catch (e, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !likerRequests.isPending(targetSite, postId)) {
        return;
      }
      _reportOperationalError(
        e,
        stackTrace,
        'post.loadLikers',
        severity: DiagnosticSeverity.warning,
      );
      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeWhoLikedThis
          : appL10n.couldnTReach((instance.host).toString());
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !likerRequests.isPending(targetSite, postId)) {
        return;
      }
      _reportOperationalError(
        error,
        stackTrace,
        'post.loadLikers',
        severity: DiagnosticSeverity.warning,
      );
      failure = appL10n.couldnTLoadWhoLikedThis;
    } finally {
      lease.commit(
        () => likerRequests.finish(targetSite, postId, error: failure),
      );
    }
  }

  Future<PostRevision?> loadPostRevision({
    required String siteUrl,
    required int postId,
    int? revision,
  }) async {
    if (_instanceAt(siteUrl) == null) return null;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return null;
      final fetched = await credential.run(
        () => api.topicContent.postRevision(
          siteUrl: siteUrl,
          postId: postId,
          revision: revision,
          apiKey: credential.apiKey,
        ),
      );
      return lease.isCurrent ? fetched : null;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.loadRevision',
          severity: DiagnosticSeverity.warning,
        );
      }
      rethrow;
    }
  }

  /// [accepted] applies what the server's acceptance of [write] changes beyond
  /// the post itself. It runs under the write's lease, before the re-read,
  /// which may fail without taking back what the server already did.
  Future<String?> _mutatePost(
    Post post,
    Future<void> Function(String siteUrl, String apiKey) write, {
    void Function(String siteUrl, int topicId, SiteLease lease)? accepted,
  }) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;

    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    final releasePost = _topicData
        .forLease(siteUrl, lease)
        ?.beginPostWrite(post.id);
    if (releasePost == null) return null;

    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final apiKey = credential.apiKey!;

      try {
        await credential.request!.run(() => write(siteUrl, apiKey));
      } on WriteException catch (e) {
        return e.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'post.mutate');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }

      if (!lease.isCurrent) return null;
      if (accepted != null) {
        lease.commit(() {
          accepted(siteUrl, topicId, lease);
          _notify();
        });
      }
      await _topicData
          .forLease(siteUrl, lease)
          ?.repairPost(topicId, post.id, apiKey, lease);
      return null;
    } finally {
      lease.commit(releasePost);
    }
  }

  Future<String?> _mutateSelectedTopicPosts(
    String siteUrl,
    int topicId,
    List<Post> posts,
    Future<void> Function(String apiKey, List<int> ids) write,
  ) async {
    final topicKey = _topicKey(siteUrl, topicId);
    final idsToHold = [for (final post in posts) post.id];
    final data = _topicData.forSite(siteUrl);
    if (_topicPostSelectionWrites.contains(topicKey) ||
        idsToHold.any(data.postWriting)) {
      return null;
    }
    final lease = data.lease;
    _topicPostSelectionWrites.add(topicKey);
    final releases = [
      for (final id in idsToHold)
        data.holdPostWrite(id, notifyOnRelease: false),
    ];
    _notify();

    var succeeded = false;
    try {
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final ids = List<int>.unmodifiable(posts.map((post) => post.id));
      try {
        await credential.request!.run(() => write(credential.apiKey!, ids));
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(
            error,
            stackTrace,
            'topic.selectedPosts.mutate',
          );
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
      if (!lease.isCurrent) return null;
      await _topicData
          .forLease(siteUrl, lease)
          ?.repairSelectedPosts(topicId, ids, credential.apiKey, lease);
      succeeded = true;
      return null;
    } finally {
      lease.commit(() {
        _topicPostSelectionWrites.remove(topicKey);
        if (succeeded) _topicPostSelections.remove(topicKey);
        for (final release in releases) {
          release();
        }
        _notify();
      });
    }
  }

  bool _replaceComposer() {
    final existing = _composer;
    if (existing == null) return true;
    if (existing.discarding || existing.closing) return false;
    if (existing.canSaveDraft &&
        (!existing.target.isPrivateMessage ||
            existing.target.draftKey !=
                ComposerDraft.newPrivateMessageDraftKey)) {
      existing.focus.unfocus();
      existing.titleFocus.unfocus();
      return true;
    }
    _composerDrafts.retire(existing);
    existing.dispose();
    _removeComposer(existing);
    return true;
  }

  void closeComposer({ComposerController? composer}) {
    composer ??= _composer;
    if (composer == null || composer.discarding || !_ownsComposer(composer)) {
      return;
    }
    _composerDrafts.retire(composer);
    composer.dispose();
    _removeComposer(composer);
    _notify();
  }

  bool hideComposerForClose(ComposerController composer) {
    if (!_ownsComposer(composer) || !composer.beginClose()) return false;
    _notify();
    return true;
  }

  void restoreComposerAfterFailedClose(ComposerController composer) {
    if (!_ownsComposer(composer) || composer.isDisposed) return;
    composer.cancelClose();
    _notify();
  }

  Future<bool> finishComposerDraftRestore(ComposerController composer) =>
      _composerDrafts.finishRestore(composer);

  /// Preserves a draft before closing its composer. False leaves
  /// the session open for retry or an explicit discard choice by the UI.
  Future<bool> prepareComposerForClose(ComposerController composer) async {
    if (!_ownsComposer(composer)) return true;
    if (_composerHasPendingOperation(composer)) return false;
    if (!composer.canSaveDraft) {
      return !composer.hasChanges && !composer.metadataChanged;
    }
    if (!await finishComposerDraftRestore(composer)) return false;
    if (!_ownsComposer(composer)) return true;
    if (_composerHasPendingOperation(composer)) return false;
    if (composer.hasUnappliedDraft && !composer.hasChanges) return true;

    if (composer.hasChanges || composer.localDraftFailed) {
      await composer.flushDraft();
    }
    await composer.finishDraftSaves();
    return !_ownsComposer(composer) ||
        (!_composerHasPendingOperation(composer) &&
            !composer.localDraftFailed &&
            !composer.draftPersistencePending);
  }

  bool _composerHasPendingOperation(ComposerController composer) =>
      composer.discarding ||
      composer.submitting ||
      composer.loadingBody ||
      composer.hasActiveUploads ||
      composer.state == ComposerState.checking;

  Future<({int? revision, String? error})> rollbackSavedComposerDraft(
    ComposerController composer, {
    required int confirmedRevision,
  }) => _composerDrafts.rollbackSavedDraft(
    composer,
    confirmedRevision: confirmedRevision,
  );

  Future<String?> discardComposer(ComposerController composer) =>
      _composerDrafts.discard(composer);

  Future<ComposerUploadResult> _uploadComposerImage(
    ComposerTarget target,
    ComposerUploadFile file, {
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
  }) async {
    if (isDisposed) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    final lease = lifecycle.capture(target.siteUrl);
    final held = await _credentialForWrite(
      target.siteUrl,
      lease: lease,
      withClientId: true,
    );
    if (isDisposed || !lease.isCurrent) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    if (held.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    final forPrivateMessage = _uploadsForPrivateMessage(target);
    return held.request!.run(
      () => api.composerPersistence.uploadComposerImage(
        siteUrl: target.siteUrl,
        apiKey: held.apiKey!,
        clientId: held.request!.clientId,
        file: file,
        onProgress: onProgress,
        abortTrigger: abortTrigger,
        uploadType: target is PluginComposerTarget
            ? target.policy.uploadType
            : ComposerUploadType.composer,
        forPrivateMessage: forPrivateMessage,
        sizeLimit: siteConfigFor(target.siteUrl).uploadSizeLimit(
          file.name,
          staff: currentUserFor(target.siteUrl)?.staff == true,
          privateMessage: forPrivateMessage,
        ),
      ),
    );
  }

  /// The web composer's `privateMessage`: a reply to or edit of a post in a
  /// message is as private as a new one.
  static bool _uploadsForPrivateMessage(ComposerTarget target) =>
      target.isPrivateMessage || target.privateMessageTopic;

  Future<Map<String, String>> _resolveComposerUploadUrls(
    ComposerTarget target,
    Iterable<String> urls,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    final held = await _credentialForWrite(
      target.siteUrl,
      lease: lease,
      withClientId: true,
    );
    if (isDisposed || !lease.isCurrent) return const {};
    if (held.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    return held.request!.run(
      () => api.composerPersistence.lookupUploadUrls(
        siteUrl: target.siteUrl,
        apiKey: held.apiKey!,
        clientId: held.request!.clientId,
        shortUrls: urls,
      ),
    );
  }

  Future<void> submitComposer({
    ComposerController? composer,
    void Function(String)? onPreparationNotice,
  }) => _submitComposer(composer ?? _composer, onPreparationNotice);

  Future<void> _submitComposer(
    ComposerController? composer,
    void Function(String)? onPreparationNotice,
  ) async {
    if (composer == null ||
        !_ownsComposer(composer) ||
        composer.discarding ||
        composer.submitting ||
        !composer.canSubmit) {
      return;
    }

    final target = composer.target;
    if (target.isNewTopic) {
      if (_newTopicRefusal(composer) case final refusal?) {
        composer.failed(
          WriteException(WriteFailure.validation, errors: [refusal]),
        );
        return;
      }
    }
    // Read before the awaits: a reply retargeted at a whisper while this one
    // is out would otherwise post what was written in public as a whisper.
    final whisper = composer.whisper;
    final lease = lifecycle.capture(target.siteUrl);
    if (target is TopicCreationComposerTarget) {
      _composerSubmissionTabs[composer] = _workspace
          .forSite(target.siteUrl)
          ?.activeTabId;
    }

    if (target is EditComposerTarget) {
      return _submitEdit(composer, target, composer.editRaw, lease);
    }

    if (target is PluginComposerTarget) return;

    // Before any await: the credential round trip below is a gap a second tap
    // can pass through, and a create sent twice posts twice — unlike an edit,
    // nothing undoes that.
    composer.beginSubmit();
    var preparationChanged = false;
    for (final preparer
        in _pluginSession.capabilities<PluginComposerSubmitPreparer>()) {
      final PluginComposerSubmitPreparation result;
      try {
        result = await preparer.prepareComposerSubmit(composer);
      } catch (error, stackTrace) {
        _pluginDiagnosticsReporter.reportError(
          error,
          stackTrace,
          operation: 'composer.prepareSubmit',
          source: 'plugin',
          handled: true,
          degraded: true,
        );
        if (!lease.isCurrent) return;
        if (preparationChanged) await composer.flushDraft();
        composer.failed(
          WriteException(
            WriteFailure.unreachable,
            errors: [appL10n.couldnTPrepareThisPostNothingWasPosted],
          ),
        );
        return;
      }
      if (!lease.isCurrent) return;
      if (result.failure case final failure?) {
        if (preparationChanged) await composer.flushDraft();
        composer.failed(failure);
        return;
      }
      preparationChanged |= result.changed;
      if (result.notice case final notice?) onPreparationNotice?.call(notice);
    }
    if (preparationChanged) await composer.flushDraft();
    await composer.finishDraftSaves();
    // Accepting the post deletes its draft. A replaced composer's save of the
    // same key that lands after that would write the posted text back into
    // the cached draft, and its conflict retry would recreate it on the site.
    await _composerDrafts.finishRetiredSaves(composer);
    if (!lease.isCurrent) return;

    final sent = composer.recordSubmission();
    final raw = sent.raw;

    final credential = await _credentialForWrite(target.siteUrl, lease: lease);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;
    final PostCreation creation;
    try {
      creation = await credential.request!.run(
        () async => switch (target) {
          TopicCreationComposerTarget() =>
            await api.composerPersistence.createTopic(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              title: sent.title,
              raw: raw,
              categoryId: composer.categoryId,
              tags: composer.tags,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              targetRecipients: target.targetRecipients,
              draftKey: target.draftKey,
            ),
          ReplyComposerTarget() => await api.composerPersistence.createPost(
            siteUrl: target.siteUrl,
            apiKey: apiKey,
            topicId: target.topicId,
            raw: raw,
            replyToPostNumber: target.replyToPostNumber,
            whisper: whisper,
            typingDuration: composer.typingDuration,
            composerOpenDuration: composer.openDuration,
            draftKey: target.draftKey,
          ),
          EditComposerTarget() || PluginComposerTarget() => throw StateError(
            'Unsupported forum submission target',
          ),
        },
      );
    } on WriteException catch (e) {
      // A refusal is certain — the site answered and said no. Not reaching it
      // is not: the post may well have been created and only the answer lost.
      // A request that never left has nothing to look for, and offline the
      // look would fail too, stranding the post on "may have posted".
      if (e.notSent) {
        lease.commit(
          () => composer.failed(
            WriteException(
              WriteFailure.unreachable,
              errors: [appL10n.couldnTReachTheSiteNothingWasPosted],
              notSent: true,
            ),
          ),
        );
      } else if (e.failure == WriteFailure.unreachable) {
        if (target is TopicCreationComposerTarget) {
          await _reconcileNewTopic(target, sent, composer, e, lease: lease);
        } else if (target is ReplyComposerTarget) {
          await _reconcile(target, raw, composer, e, lease: lease);
        }
      } else {
        lease.commit(() => composer.failed(e));
      }
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.submit');
      }
      if (target is TopicCreationComposerTarget) {
        await _reconcileNewTopic(
          target,
          sent,
          composer,
          const WriteException(WriteFailure.unreachable),
          lease: lease,
        );
      } else if (target is ReplyComposerTarget) {
        await _reconcile(
          target,
          raw,
          composer,
          const WriteException(WriteFailure.unreachable),
          lease: lease,
        );
      }
      return;
    }

    if (target is TopicCreationComposerTarget) {
      lease.commit(
        () => _applyTopicCreation(target, creation, composer, lease),
      );
    } else if (target is ReplyComposerTarget) {
      lease.commit(() => _applyCreation(target, creation, composer, lease));
    }
  }

  /// What core's composer refuses to send for a new topic before asking the
  /// site: a body that, trimmed, is still its category's template, and, on a
  /// site that has templates but no uncategorized topics, a topic with no
  /// category.
  String? _newTopicRefusal(ComposerController composer) {
    final siteUrl = composer.target.siteUrl;
    final categoryId = composer.categoryId;
    final template = categoryFor(categoryId, siteUrl: siteUrl)?.topicTemplate;
    if (template != null && composer.raw.trim() == template.trim()) {
      return appL10n.pleaseAddDetailsAndSpecificsToYourTopicByEditingThe;
    }
    if (categoryId == null &&
        !siteConfigFor(siteUrl).allowUncategorizedTopics &&
        topicComposerCategories(
          siteUrl,
        ).any((category) => category.topicTemplate != null)) {
      return appL10n.youMustChooseACategory;
    }
    return null;
  }

  Future<void> _submitEdit(
    ComposerController composer,
    EditComposerTarget target,
    String raw,
    SiteLease lease,
  ) async {
    switch (target) {
      case CategoryEditComposerTarget():
        return _submitCategoryEdit(composer, target);
      case TagsEditComposerTarget():
        return _submitTagsEdit(composer, target);
      case PostEditingComposerTarget():
        final releasePost = _topicData
            .forLease(target.siteUrl, lease)
            ?.beginPostWrite(target.editingPostId);
        if (releasePost == null) {
          composer.failed(
            WriteException(
              WriteFailure.conflict,
              errors: [appL10n.anotherActionOnThisPostIsStillBeingSaved],
            ),
          );
          return;
        }
        try {
          await _submitEditNow(composer, target, raw, lease);
        } finally {
          lease.commit(releasePost);
        }
    }
  }

  Future<void> _submitEditNow(
    ComposerController composer,
    PostEditingComposerTarget target,
    String raw,
    SiteLease lease,
  ) async {
    if (!lease.isCurrent || !_ownsComposer(composer)) return;
    composer.beginSubmit();
    // A missing baseline means the body fetch failed. Never build a destructive
    // edit without the original text used for conflict detection.
    if (composer.originalRaw == null) {
      composer.failed(const WriteException(WriteFailure.unreachable));
      return;
    }
    final credential = await _credentialForWrite(target.siteUrl, lease: lease);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;

    if (target.editsTopicMetadata && composer.metadataChanged) {
      final TopicUpdate update;
      try {
        update = await credential.request!.run(
          () => api.topicMutations.updateTopic(
            siteUrl: target.siteUrl,
            apiKey: apiKey,
            topicId: target.topicId,
            title: composer.title.text.trim(),
            originalTitle: composer.originalTitle,
            categoryId: composer.categoryId,
            tags: composer.tags,
            originalTags: composer.originalTags,
          ),
        );
      } on WriteException catch (e) {
        lease.commit(() => composer.failed(e));
        return;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'composer.editTopic');
        }
        lease.commit(
          () => composer.failed(const WriteException(WriteFailure.unreachable)),
        );
        return;
      }
      lease.commit(() {
        final title = update.title ?? composer.title.text.trim();
        final tags = update.tags ?? composer.tags;
        store.update<TopicDetail>(
          target.siteUrl,
          target.topicId,
          (detail) => detail.copyWith(
            title: title,
            categoryId: composer.categoryId,
            clearCategory: composer.categoryId == null,
            tags: tags,
          ),
        );
        store.update<Topic>(
          target.siteUrl,
          target.topicId,
          (topic) => topic.copyWith(
            title: title,
            categoryId: composer.categoryId,
            clearCategory: composer.categoryId == null,
            tags: tags,
          ),
        );
        _updateTopicRouteMetadata(
          target.siteUrl,
          target.topicId,
          title,
          composer.categoryId,
        );
        composer.metadataSettled(title: update.title, tags: update.tags);
      });
      if (raw == composer.originalRaw?.trimRight()) {
        lease.commit(() => _closeSubmittedComposer(composer));
        return;
      }
    }

    if (!lease.isCurrent || !_ownsComposer(composer)) return;
    final Post updated;
    try {
      updated = await credential.request!.run(
        () => api.composerPersistence.updatePost(
          siteUrl: target.siteUrl,
          apiKey: apiKey,
          postId: target.editingPostId,
          raw: raw,
          originalText: composer.originalRaw,
        ),
      );
    } on WriteException catch (e) {
      lease.commit(() => composer.failed(e));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.edit');
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }

    lease.commit(() {
      _topicData
          .forLease(target.siteUrl, lease)
          ?.acceptEditedPost(updated, raw: raw);
      _closeSubmittedComposer(composer);
    });
  }

  Future<void> _submitTagsEdit(
    ComposerController composer,
    TagsEditComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl, lease: lease);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await credential.request!.run(
        () => api.topicMutations.updateTopicTags(
          siteUrl: target.siteUrl,
          apiKey: credential.apiKey!,
          topicId: target.topicId,
          tags: composer.tags,
        ),
      );
    } on WriteException catch (error) {
      lease.commit(() => composer.failed(error));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.editTopicTags');
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }
    lease.commit(() {
      _applyTopicTags(target.siteUrl, target.topicId, composer.tags);
      _closeSubmittedComposer(composer);
    });
  }

  void _applyTopicTags(String siteUrl, int topicId, List<TopicTag> tags) {
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.copyWith(tags: tags),
    );
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(tags: tags),
    );
  }

  Future<void> _submitCategoryEdit(
    ComposerController composer,
    CategoryEditComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl, lease: lease);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await credential.request!.run(
        () => api.topicMutations.updateTopic(
          siteUrl: target.siteUrl,
          apiKey: credential.apiKey!,
          topicId: target.topicId,
          title: target.topicTitle,
          originalTitle: target.topicTitle,
          categoryId: composer.categoryId,
          tags: composer.tags,
          originalTags: composer.originalTags,
        ),
      );
    } on WriteException catch (error) {
      lease.commit(() => composer.failed(error));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.editTopicCategory',
        );
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }
    lease.commit(() {
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.copyWith(
          categoryId: composer.categoryId,
          clearCategory: composer.categoryId == null,
          tags: composer.tags,
        ),
      );
      store.update<Topic>(
        target.siteUrl,
        target.topicId,
        (topic) => topic.copyWith(
          categoryId: composer.categoryId,
          clearCategory: composer.categoryId == null,
          tags: composer.tags,
        ),
      );
      _updateTopicRouteMetadata(
        target.siteUrl,
        target.topicId,
        target.topicTitle,
        composer.categoryId,
      );
      _closeSubmittedComposer(composer);
    });
  }

  void _closeSubmittedComposer(ComposerController composer) {
    if (_ownsComposer(composer)) {
      composer.dispose();
      _removeComposer(composer);
    }
    _notify();
  }

  Future<void> recheckComposer({ComposerController? composer}) async {
    composer ??= _composer;
    if (composer == null || !composer.canRecheck) return;
    final sent = composer.submission;
    if (sent == null) return;
    final target = composer.target;
    if (target is TopicCreationComposerTarget) {
      await _reconcileNewTopic(
        target,
        sent,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    } else if (target is ReplyComposerTarget) {
      await _reconcile(
        target,
        sent.raw,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<void> _reconcileNewTopic(
    TopicCreationComposerTarget target,
    ComposerSubmission sent,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;
    final data = _topicData.forLease(target.siteUrl, session);
    if (data == null) return;
    final credential = await _credentialForWrite(
      target.siteUrl,
      lease: session,
    );
    if (!session.isCurrent || credential.failure != null) {
      session.commit(composer.unresolved);
      return;
    }
    final apiKey = credential.apiKey!;

    try {
      final retained = await credential.request!.run(
        () => api.composerPersistence.draft(
          siteUrl: target.siteUrl,
          apiKey: apiKey,
          draftKey: target.draftKey,
        ),
      );
      if (!session.isCurrent) return;
      final draft = retained.draft;
      // Creating the topic advances the draft sequence, and so does every save
      // after it, including one that recreates the draft the create removed.
      // A draft still at the sequence the create was sent at therefore shows
      // the create never ran, whatever it holds: the last save before sending
      // may not have reached the site.
      if (draft != null && retained.sequence == sent.draftSequence) {
        session.commit(() => composer.checkedNotPosted(failure));
        return;
      }

      final username = _instanceAt(target.siteUrl)?.user?.username;
      if (username == null) {
        session.commit(composer.unresolved);
        return;
      }

      final match = await data.findCreatedTopic(
        username: username,
        title: sent.title,
        raw: sent.raw,
        privateMessage: target.isPrivateMessage,
        credential: credential.request!,
      );
      session.commit(() {
        if (match == null) {
          composer.unresolved();
        } else {
          _finishCreatedTopic(
            target,
            composer,
            session,
            match.topicId,
            match.slug,
            match.title,
          );
        }
      });
    } catch (error, stackTrace) {
      if (session.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.reconcileTopic',
          severity: DiagnosticSeverity.warning,
        );
      }
      session.commit(composer.unresolved);
    }
  }

  Future<void> _reconcile(
    ReplyComposerTarget target,
    String raw,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;
    final data = _topicData.forLease(target.siteUrl, session);
    if (data == null) return;
    final username = _instanceAt(target.siteUrl)?.user?.username;
    final credential = await _credentialForWrite(
      target.siteUrl,
      lease: session,
    );
    if (!session.isCurrent) return;
    if (credential.failure != null) {
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }
    Post? landed;
    try {
      landed = await data.findReply(
        topicId: target.topicId,
        slug: target.slug,
        username: username,
        raw: raw,
        credential: credential.request!,
      );
    } catch (error, stackTrace) {
      if (session.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.reconcile',
          severity: DiagnosticSeverity.warning,
        );
      }
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }
    session.commit(() {
      if (landed == null) {
        composer.checkedNotPosted(failure);
        _notify();
        return;
      }
      _composerDrafts.settleAfterSubmission(composer, session);
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.withDraft(null, _composerDrafts.sequenceFor(target)),
      );
      if (_ownsComposer(composer)) {
        composer.dispose();
        _removeComposer(composer);
      }
      _notify();
    });
  }

  DiscourseInstance? _instanceAt(String url) {
    for (final instance in _instances) {
      if (instance.url == url) return instance;
    }
    return null;
  }

  void _applyCreation(
    ReplyComposerTarget target,
    PostCreation creation,
    ComposerController composer,
    SiteLease lease,
  ) {
    final post = creation.post;
    if (post != null) {
      _topicData
          .forLease(target.siteUrl, lease)
          ?.acceptReply(target.topicId, post);
      if (!lease.isCurrent) return;
    }

    // Accepting a post deletes its draft and advances the sequence server side,
    // so the local copy goes too and the next save uses the number it sent back
    // — keeping the old one earns a conflict on the very next keystroke.
    _composerDrafts.settleAfterSubmission(
      composer,
      lease,
      sequence: creation.draftSequence,
    );
    store.update<TopicDetail>(
      target.siteUrl,
      target.topicId,
      (detail) => detail.withDraft(null, _composerDrafts.sequenceFor(target)),
    );

    if (creation.isEnqueued) {
      composer.enqueued(creation.message);
      _notify();
      return;
    }

    if (_ownsComposer(composer)) {
      composer.dispose();
      _removeComposer(composer);
    }
    _notify();

    unawaited(
      _topicData
          .forLease(target.siteUrl, lease)
          ?.refresh(target.topicId, slug: target.slug),
    );
  }

  void _applyTopicCreation(
    TopicCreationComposerTarget target,
    PostCreation creation,
    ComposerController composer,
    SiteLease lease,
  ) {
    _composerDrafts.settleAfterSubmission(
      composer,
      lease,
      sequence: creation.draftSequence,
    );
    if (creation.isEnqueued) {
      composer.enqueued(creation.message);
      _notify();
      return;
    }
    final topicId = creation.topicId;
    if (topicId == null) {
      composer.failed(const WriteException(WriteFailure.unreachable));
      return;
    }
    if (creation.post case final post?) {
      _topicData.forLease(target.siteUrl, lease)?.acceptNewTopicPost(post);
      if (!lease.isCurrent) return;
    }
    _finishCreatedTopic(
      target,
      composer,
      lease,
      topicId,
      creation.topicSlug ?? '',
      creation.topicTitle ?? composer.title.text.trim(),
    );
  }

  void _finishCreatedTopic(
    TopicCreationComposerTarget target,
    ComposerController composer,
    SiteLease lease,
    int topicId,
    String slug,
    String title,
  ) {
    _composerDrafts.settleAfterSubmission(composer, lease);
    final wasRetained = _ownsComposer(composer);
    _closeSubmittedComposer(composer);
    if (target.isPrivateMessage) {
      // Core lists a new message under its author's Sent and each recipient
      // group's inbox, but not their own Inbox until someone else posts. The
      // site holds it whether or not this composer is still the one shown.
      _refreshMessageFolders(
        target.siteUrl,
        personal: const [MessageListMode.sent],
        group: const [MessageListMode.inbox],
        groupNames: {
          for (final name in (target.targetRecipients ?? '').split(','))
            if (name.trim().isNotEmpty) name.trim(),
        },
      );
    }
    if (!wasRetained) return;
    final origin = target.originFeedId;
    final workspace = _workspace.forSite(target.siteUrl);
    final submittedTabId = _composerSubmissionTabs[composer];
    final tabId =
        workspace?.tabById(submittedTabId ?? '')?.id ?? workspace?.activeTabId;
    if (currentInstance?.url == target.siteUrl && activeTabId == tabId) {
      _openTopic(topicId, slug, title);
      if (origin != null && target.isNewTopic) {
        unawaited(loadFeed(origin, force: true));
      }
    } else if (tabId != null) {
      final tab = _workspace.forSite(target.siteUrl)?.tabById(tabId);
      if (tab != null) {
        _workspace.replaceTab(
          target.siteUrl,
          tab.push(
            ContentRoute.topic(topicId: topicId, slug: slug, title: title),
          ),
        );
        _notify();
      }
    }
  }

  UserCard? userCard(String username, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return store.read<UserCard>(targetSite, username.toLowerCase());
  }

  String? userCardError(String username, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return userCardRequests.errorFor(targetSite, username.toLowerCase());
  }

  // Every newly hovered name lands here, so progress and failures go to
  // [userCardRequests] and the card to [store], never to the facade.
  Future<void> loadUserCard(
    String username, {
    bool force = false,
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || username.isEmpty) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;

    final key = username.toLowerCase();
    if (userCardRequests.isPending(targetSite, key)) return;
    if (!force) {
      if (userCardRequests.errorFor(targetSite, key) != null) return;
      if (store.read<UserCard>(targetSite, key) != null) return;
    }

    // Captured before the fetch is announced, so a listener that replaces
    // the account cannot hand this fetch the new one.
    final lease = lifecycle.capture(targetSite);
    userCardRequests.begin(targetSite, key);
    String? failure;

    try {
      final credential = await AccountRequestSession(
        targetSite,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final card = await credential.run(
        () => api.site.userCard(
          siteUrl: targetSite,
          username: username,
          // Read inside the guard, the way `loadLikers` does: storage that
          // throws would otherwise strand the fetch in [userCardRequests].
          apiKey: credential.apiKey,
        ),
      );
      lease.commit(() => store.put(targetSite, card));
    } on SiteLookupException catch (e, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !userCardRequests.isPending(targetSite, key)) {
        return;
      }
      _reportOperationalError(
        e,
        stackTrace,
        'userCard.load',
        severity: DiagnosticSeverity.warning,
      );
      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeThatProfile
          : appL10n.couldnTReach((instance.host).toString());
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !userCardRequests.isPending(targetSite, key)) {
        return;
      }
      _reportOperationalError(
        error,
        stackTrace,
        'userCard.load',
        severity: DiagnosticSeverity.warning,
      );
      failure = appL10n.couldnTLoadShellcontroller((username).toString());
    } finally {
      lease.commit(
        () => userCardRequests.finish(targetSite, key, error: failure),
      );
    }
  }

  Future<void> loadMoreFeed(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;
    await topicFeeds.loadMore(instance: instance, destinationId: destinationId);
  }

  SiteEmojiCatalog? emojiCatalogFor(String siteUrl) =>
      _presentation.emojiCatalogFor(siteUrl);

  Future<SiteEmojiCatalog?> ensureEmojiCatalog(String siteUrl) =>
      _presentation.ensureEmojiCatalog(siteUrl);

  Future<SiteEmojiCatalog?> refreshEmojiCatalog(String siteUrl) =>
      _presentation.refreshEmojiCatalog(siteUrl);

  Future<Map<String, List<String>>?> ensureEmojiSearchAliases(String siteUrl) =>
      _presentation.ensureEmojiSearchAliases(siteUrl);

  Future<Map<String, List<String>>?> refreshEmojiSearchAliases(
    String siteUrl,
  ) => _presentation.refreshEmojiSearchAliases(siteUrl);

  List<SiteEmoji> searchEmojis(String siteUrl, String query, {int limit = 7}) =>
      _presentation.searchEmojis(siteUrl, query, limit: limit);

  SuggestionArt _hashtagArt(String siteUrl, FoundHashtag hashtag) {
    final presentation = resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: hashtag.type,
        style: HashtagStyle.parse(hashtag.styleType),
        icon: hashtag.icon,
        emoji: hashtag.emoji,
        colorValues: hashtag.colorValues,
      ),
      pluginPresentation: plugins.registry.pluginHashtagPresentation,
    );
    return hashtagSuggestionArt(
      presentation,
      resolveEmoji: (emoji) => emojiUrlFor(siteUrl, emoji),
    );
  }

  static const int composerIdentityCacheCapacity = 2048;

  final Map<String, BoundedLruCache<String, FoundHashtag?>> _hashtags = {};
  final Map<String, Set<String>> _hashtagsInFlight = {};

  final Map<String, BoundedLruCache<String, bool>> _mentioned = {};
  final Map<String, Set<String>> _mentionsInFlight = {};

  List<String> _composerHashtagTypes() {
    final types = <String>{
      ...defaultDiscourseHashtagOrder,
      ...plugins.registry.pluginHashtagWireTypes,
    };
    // The endpoint rejects the entire request above its fixed bound. Core
    // kinds stay first; installed registrations retain manifest order after
    // them. Servers without one of those data sources simply filter it out.
    return types
        .take(maximumDiscourseHashtagsPerRequest)
        .toList(growable: false);
  }

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final List<FoundHashtag> found;
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return const [];
      found = await credential.run(
        () => api.search.searchHashtags(
          siteUrl: siteUrl,
          term: term,
          order: _composerHashtagTypes(),
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'hashtags.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }

    // Everything offered is now known, so accepting a suggestion draws its
    // pill without a second round trip. This is the path almost every hashtag
    // in a post takes.
    final accepted = lease.commit(() {
      final known = _hashtags.putIfAbsent(
        siteUrl,
        () => BoundedLruCache(composerIdentityCacheCapacity),
      );
      for (final hashtag in found) {
        known.put(hashtag.ref, hashtag);
      }
      if (found.isNotEmpty) cooking.contextChanged(siteUrl);
    });
    return accepted ? found : const [];
  }

  ComposerPills _composerPills(ComposerTarget target) {
    final siteUrl = target.siteUrl;
    return (
      hashtag: (ref) => _hashtags[siteUrl]?.read(ref),
      mention: (username) => _mentioned[siteUrl]?.read(username),
      resolve: (refs, usernames) {
        unawaited(_resolveHashtags(siteUrl, refs));
        unawaited(_resolveMentions(siteUrl, target.mentionTopicId, usernames));
      },
    );
  }

  Future<void> _resolveHashtags(String siteUrl, Set<String> refs) async {
    final known = _hashtags.putIfAbsent(
      siteUrl,
      () => BoundedLruCache(composerIdentityCacheCapacity),
    );
    final inFlight = _hashtagsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final ref in refs)
        if (!known.containsKey(ref) && inFlight.add(ref)) ref,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return;
      final found = await credential.run(
        () => api.lookups.lookupHashtags(
          siteUrl: siteUrl,
          refs: ask,
          order: _composerHashtagTypes(),
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final ref in ask) {
          known.put(ref, null);
        }
        for (final hashtag in found) {
          known.put(hashtag.ref, hashtag);
        }
        cooking.contextChanged(siteUrl);
        for (final composer in _composersForSite(siteUrl)) {
          composer.text.artworkArrived();
        }
      });
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent && ask.any(inFlight.contains)) {
        _reportOperationalError(
          error,
          stackTrace,
          'hashtags.resolve',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  Future<void> _resolveMentions(
    String siteUrl,
    int? topicId,
    Set<String> usernames,
  ) async {
    final known = _mentioned.putIfAbsent(
      siteUrl,
      () => BoundedLruCache(composerIdentityCacheCapacity),
    );
    final inFlight = _mentionsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final name in usernames)
        if (!known.containsKey(name) && inFlight.add(name)) name,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return;
      final real = await credential.run(
        () => api.lookups.checkMentions(
          siteUrl: siteUrl,
          names: ask,
          topicId: topicId,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final name in ask) {
          known.put(name, real.contains(name));
        }
        cooking.contextChanged(siteUrl);
        for (final composer in _composersForSite(siteUrl)) {
          composer.text.artworkArrived();
        }
      });
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent && ask.any(inFlight.contains)) {
        _reportOperationalError(
          error,
          stackTrace,
          'mentions.resolve',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  Future<FoundUsersAndGroups> searchMessageRecipients({
    required String siteUrl,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return const FoundUsersAndGroups();
      if (!lease.isCurrent) {
        return const FoundUsersAndGroups();
      }
      final found = await credential.run(
        () => api.search.searchUsersAndGroups(
          siteUrl: siteUrl,
          term: term,
          limit: 20,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      return lease.isCurrent ? found : const FoundUsersAndGroups();
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'message.recipients.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const FoundUsersAndGroups();
    }
  }

  Future<FoundUsersAndGroups> _searchMentions({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final FoundUsersAndGroups found;
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return const FoundUsersAndGroups();
      if (!lease.isCurrent) {
        return const FoundUsersAndGroups();
      }
      found = await credential.run(
        () => api.search.searchMentions(
          siteUrl: siteUrl,
          term: term,
          topicId: topicId,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'mentions.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      if (lease.isCurrent) rethrow;
      return const FoundUsersAndGroups();
    }

    // The site just named these, so they exist — accepting one draws its pill
    // without asking again.
    final accepted = lease.commit(() {
      final known = _mentioned.putIfAbsent(
        siteUrl,
        () => BoundedLruCache(composerIdentityCacheCapacity),
      );
      for (final user in found.users) {
        known.put(user.username, true);
      }
      for (final group in found.groups) {
        known.put(group.name, true);
      }
      if (found.users.isNotEmpty || found.groups.isNotEmpty) {
        cooking.contextChanged(siteUrl);
      }
    });
    return accepted ? found : const FoundUsersAndGroups();
  }

  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final List<FoundUser> found;
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = _instanceAt(siteUrl)?.isConnected == true
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return const [];
      found = await credential.run(
        () => api.lookups.searchUsers(
          siteUrl: siteUrl,
          term: term,
          topicId: topicId,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'users.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }

    // The site just named these, so they exist — accepting one draws its pill
    // without asking again.
    final accepted = lease.commit(() {
      final known = _mentioned.putIfAbsent(
        siteUrl,
        () => BoundedLruCache(composerIdentityCacheCapacity),
      );
      for (final user in found) {
        known.put(user.username, true);
      }
      if (found.isNotEmpty) cooking.contextChanged(siteUrl);
    });
    return accepted ? found : const [];
  }

  String emojiUrlFor(String siteUrl, String name) =>
      _presentation.emojiUrlFor(siteUrl, name);

  bool knowsEmoji(String siteUrl, String name) =>
      _presentation.knowsEmoji(siteUrl, name);

  String? emojiNameFor(String siteUrl, String name) =>
      _presentation.emojiNameFor(siteUrl, name);

  Object presentationTokenFor(String siteUrl) =>
      _presentation.presentationTokenFor(siteUrl);

  SiteConfig siteConfigFor(String siteUrl) => _presentation.configFor(siteUrl);

  /// What a bookmark editor needs to know about a site's reader: the account
  /// the reminder is for, its timezone, and the site's date-picker policy.
  BookmarkSiteContext bookmarkSiteContextFor(String siteUrl) {
    final user = currentUserFor(siteUrl);
    final config = siteConfigFor(siteUrl);
    return BookmarkSiteContext(
      username: user?.username,
      timezone: user?.timezone,
      suggestWeekendsInDatePickers: config.suggestWeekendsInDatePickers,
    );
  }

  Future<SiteConfig?> resolveSiteConfig(String siteUrl) =>
      _presentation.resolveConfig(siteUrl);

  SiteConfig get currentSiteConfig {
    final instance = currentInstance;
    return instance == null
        ? const SiteConfig.unknown()
        : siteConfigFor(instance.url);
  }

  SiteAppearance? siteAppearanceFor(String siteUrl) =>
      _presentation.appearanceFor(siteUrl);

  SiteAppearance? get currentSiteAppearance {
    final instance = currentInstance;
    return instance == null ? null : siteAppearanceFor(instance.url);
  }

  Future<void> _persistSiteAppearance(
    String siteUrl,
    SiteAppearance appearance,
  ) async {
    final held = _instanceAt(siteUrl);
    if (held == null || held.appearance == appearance) return;
    _replaceInstance(held, held.copyWith(appearance: appearance));
    await instanceStore.save(List.of(_instances));
  }

  DiscourseUser? currentUserFor(String siteUrl) => _instanceAt(siteUrl)?.user;

  DiscourseUser? freshCurrentUserFor(String siteUrl) =>
      _sessionUsersRefreshed.contains(siteUrl)
      ? _instanceAt(siteUrl)?.user
      : null;

  ({bool valid, PluginData data}) _pluginDataForTarget(
    String siteUrl,
    PluginTarget target,
  ) {
    switch (target.kind) {
      case 'topic':
        if (target.id != target.topicId) {
          return (valid: false, data: PluginData.none);
        }
        final topic = store.read<TopicDetail>(siteUrl, target.id);
        return (valid: topic != null, data: topic?.plugins ?? PluginData.none);
      case 'post':
        final topic = store.read<TopicDetail>(siteUrl, target.topicId);
        if (topic == null || !topic.stream.contains(target.id)) {
          return (valid: false, data: PluginData.none);
        }
        final post = store.read<Post>(siteUrl, target.id);
        // Post #1 is represented by the topic target in Discourse write APIs.
        if (post == null || post.postNumber == 1) {
          return (valid: false, data: PluginData.none);
        }
        return (valid: true, data: post.plugins);
      default:
        return (valid: false, data: PluginData.none);
    }
  }

  Future<void> _persistSiteConfig(String siteUrl, SiteConfig config) async {
    cooking.service.invalidate();
    if (currentInstance?.url == siteUrl) {
      search.selectSite(siteUrl, logSearchQueries: config.logSearchQueries);
    }
    for (final composer in _composersForSite(siteUrl)) {
      if (!config.emojiEnabled) composer.closeEmojiAutocomplete();
      composer.updateEnableAutoGridImages(config.enableAutoGridImages);
      composer.updateMarkdownLinkify(
        enabled: config.enableMarkdownLinkify,
        tlds: config.markdownLinkifyTlds,
      );
    }
    final held = _instanceAt(siteUrl);
    if (held == null) return;
    final persisted = plugins.models.preserveUnknownSiteSettings(
      held.config,
      config,
    );
    if (held.config == persisted) return;
    _replaceInstance(held, held.copyWith(config: persisted));
    await instanceStore.save(List.of(_instances));
  }

  Future<void> loadCategories(String siteUrl, {bool force = false}) =>
      _taxonomy.loadCategories(siteUrl, force: force);

  Future<void> loadTags(String siteUrl, {bool force = false}) =>
      _taxonomy.loadTags(siteUrl, force: force);

  Future<void> loadMoreCategories(String siteUrl) =>
      _taxonomy.loadMoreCategories(siteUrl);

  Future<void> connectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null || _connectingSiteUrl != null) return;

    _connectingSiteUrl = instance.url;
    _connectErrors.remove(instance.url);
    _notify();

    try {
      final result = await _accountSessions.connect(instance.url);
      switch (result.outcome) {
        case AccountConnectionOutcome.connected:
          _connectErrors.remove(instance.url);
          final connected = result.instance!;
          unawaited(_refreshOne(connected));
          unawaited(_customSidebar.ensure(instance.url));
        case AccountConnectionOutcome.cancelled:
          _connectErrors.remove(instance.url);
        case AccountConnectionOutcome.failed:
          _connectErrors[instance.url] = result.message!;
          if (result.refreshSignedOutPresentation &&
              currentInstance?.url == instance.url) {
            unawaited(
              RequestIntent.background().run(
                () => _presentation.ensureAppearance(instance.url),
              ),
            );
          }
        case AccountConnectionOutcome.stale || AccountConnectionOutcome.missing:
          break;
      }
    } finally {
      if (_connectingSiteUrl == instance.url) _connectingSiteUrl = null;
      final held = _instanceAt(instance.url);
      if (held?.isConnected == true &&
          !_sessionUsersRefreshed.contains(instance.url)) {
        // A cancelled/failed handshake leaves the previous account in place.
        // Retry a background refresh that deliberately stood aside above.
        unawaited(_refreshSessionUserFor(held!));
      }
      _notify();
    }
  }

  Future<void> disconnectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null) return;

    await disconnectInstance(instance.url);
  }

  Future<bool> disconnectInstance(String siteUrl) async {
    final result = await _accountSessions.disconnect(siteUrl);
    return result.outcome == AccountDisconnectionOutcome.disconnected;
  }

  @override
  bool get accountSessionDisposed => isDisposed;

  @override
  List<DiscourseInstance> get accountSessionInstances =>
      List.unmodifiable(_instances);

  @override
  DiscourseInstance? accountSessionInstance(String siteUrl) =>
      _instanceAt(siteUrl);

  @override
  void clearAccountSessionState(String siteUrl) {
    // An operation rotates more than once; keep the workspace from before
    // its first rotation, not one opened on its signed-out boundary since.
    final workspace =
        _rotatedWorkspaces[siteUrl] ?? _workspace.forSite(siteUrl);
    _forgetSiteState(siteUrl, invalidateLifecycle: false);
    if (workspace != null) _rotatedWorkspaces[siteUrl] = workspace;
  }

  @override
  DiscourseInstance? applyAccountSessionInstance(
    DiscourseInstance replacement,
    AccountSessionPhase phase,
  ) {
    final held = _instanceAt(replacement.url);
    if (held == null) return null;

    if (held.user?.id != replacement.user?.id) cooking.forget(replacement.url);
    var applied = replacement;
    if (phase == AccountSessionPhase.connected && replacement.user != null) {
      final user = _acceptDoNotDisturbSnapshot(
        replacement.url,
        replacement.user!,
      );
      applied = replacement.copyWith(user: user);
      _seedGroupedUnreadNotifications(replacement.url, user);
      _sessionUsersRefreshed.add(replacement.url);
    } else if (phase == AccountSessionPhase.restored &&
        replacement.user != null) {
      if (replacement.notificationTotals case final totals?) {
        accountActivity.restoreTotals(replacement.url, totals);
      }
      doNotDisturb.restoreSnapshot(
        replacement.url,
        replacement.user?.doNotDisturbUntil,
      );
      _seedGroupedUnreadNotifications(replacement.url, replacement.user!);
    }

    final rotated = switch (phase) {
      AccountSessionPhase.connecting ||
      AccountSessionPhase.disconnecting => null,
      _ => _rotatedWorkspaces.remove(replacement.url),
    };
    // A rolled-back sign-out or removal leaves the same account signed in,
    // so what it had open comes back with it, in memory and on disk.
    final restoredWorkspace =
        phase == AccountSessionPhase.restored &&
            rotated?.accountIdentity == _workspaceAccountIdentity(applied)
        ? rotated
        : null;
    if (restoredWorkspace != null) _workspace.put(restoredWorkspace);

    _replaceInstance(held, applied);
    _taxonomy.bind(replacement.url);
    if (currentInstance?.url == replacement.url) {
      switch (phase) {
        case AccountSessionPhase.connecting:
          break;
        case AccountSessionPhase.connected:
          _resetToInstanceDefault(refreshAppearance: false);
          unawaited(_presentation.refreshAppearance(replacement.url));
        case AccountSessionPhase.disconnecting:
          // The coordinator has published the pending signed-out boundary and
          // still owns persistence, revocation and deletion. Starting anonymous
          // presentation work here would race that teardown and read the same
          // credential again. The final disconnected phase rebuilds and
          // hydrates the public workspace once secret storage has settled.
          break;
        case AccountSessionPhase.rolledBack:
          _resetToInstanceDefault(refreshAppearance: false);
        case AccountSessionPhase.restored when restoredWorkspace != null:
          _restoreInstanceWorkspace();
        case AccountSessionPhase.disconnected || AccountSessionPhase.restored:
          _resetToInstanceDefault();
      }
    }
    _notify();
    return applied;
  }

  void _forgetSiteState(String siteUrl, {bool invalidateLifecycle = true}) {
    _topicData.clearPrefetch();
    cooking.forget(siteUrl);
    if (invalidateLifecycle) lifecycle.invalidate(siteUrl);
    _bookmarks.forget(siteUrl);
    _topicData.forget(siteUrl);
    siteImages.forget(siteUrl);
    videoThumbnails.forget(siteUrl);
    pdfThumbnails.forget(siteUrl);
    _workspace.remove(siteUrl);
    _rotatedWorkspaces.remove(siteUrl);
    search.forget(siteUrl);
    _composerDrafts.forgetSite(siteUrl);

    for (final composer in _composersForSite(siteUrl).toList()) {
      composer.draftSettled();
      composer.dispose();
      _removeComposer(composer);
    }

    accountActivity.forget(siteUrl);
    draftList.forget(siteUrl);
    userSummary.forget(siteUrl);
    groups.forget(siteUrl);
    userDirectory.forget(siteUrl);
    badges.forget(siteUrl);
    preferences.forget(siteUrl);
    store.forget(siteUrl);

    likerRequests.forget(siteUrl);
    userCardRequests.forget(siteUrl);
    _postChecklistWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _topicPostSelections.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicPostSelectionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicFlagWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicNotificationWrites.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _categoryNotificationWrites.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    _categoryNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    final _ = _categoryNotificationSiteTails.remove(siteUrl);
    _currentUserReconcilers.remove(siteUrl)?.retire();
    _categoryNotificationConfirmed.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    _topicPinWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicStatusWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _messageArchiveWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicDeletionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicJumpRuns.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicReads.forget(siteUrl);
    _topicUnreadWrites.removeWhere((key, _) => key.startsWith("$siteUrl#"));

    _taxonomy.forget(siteUrl);
    _topicTrackingBySite.remove(siteUrl)?.retire();
    _topicTrackingRetries.remove(siteUrl);
    _topicComposerCapabilities.remove(siteUrl);
    _postActionCatalogs.remove(siteUrl);
    _customSidebar.forget(siteUrl);
    _siteNotificationTypes.remove(siteUrl);
    _siteNotificationTypeRequests.remove(siteUrl)?.ignore();
    _sitePresentation?.forget(siteUrl);
    _pluginSiteConfigListenables.remove(siteUrl)?.dispose();
    _hashtags.remove(siteUrl);
    _hashtagsInFlight.remove(siteUrl);
    _mentioned.remove(siteUrl);
    _mentionsInFlight.remove(siteUrl);
    _connectErrors.remove(siteUrl);
    _unavailableForums.remove(siteUrl);
    _retryingUnavailableForums.remove(siteUrl);
    _basicInfoRefreshes.remove(siteUrl);

    _backgroundRetention.releaseSite(siteUrl);
    final forgetPlugins = _pluginSession
        .forget(siteUrl)
        .whenComplete(() => _backgroundRetention.releaseSite(siteUrl));
    _observePluginLifecycle(forgetPlugins, 'plugins.session.forget');
    topicFeeds.forget(siteUrl);
    _trackersStarting.remove(siteUrl);
    _trackerStartRequests.remove(siteUrl)?.ignore();
    _sessionUsersRefreshed.remove(siteUrl);
    _sessionUserRequests.remove(siteUrl)?.ignore();
    doNotDisturb.forget(siteUrl);
    userStatuses.forget(siteUrl);
    _userStatusWrites.remove(siteUrl);
    _optimisticHidePresence.remove(siteUrl);
    _hidePresenceWrites.remove(siteUrl);
    _hidePresenceErrors.remove(siteUrl);
    _pluginNotificationFeedRefreshTimers.remove(siteUrl)?.cancel();
    _disposeTracking(siteUrl);
    _notify();
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) {
      _instances[index] = updated;
      if (old.user?.id != updated.user?.id ||
          old.user?.username != updated.user?.username ||
          old.user?.timezone != updated.user?.timezone ||
          old.config != updated.config) {
        cooking.contextChanged(updated.url);
      }
    }
  }

  void _restoreInstanceWorkspace({
    bool refreshAppearance = true,
    bool hydrateActiveTab = true,
  }) {
    final instance = currentInstance;
    if (instance == null) {
      search.selectSite(null);
      _syncTracking();
      return;
    }

    _workspace.ensure(instance);
    _activateInstanceWorkspace(
      instance,
      refreshAppearance: refreshAppearance,
      hydrateActiveTab: hydrateActiveTab,
    );
  }

  void _resetToInstanceDefault({bool refreshAppearance = true}) {
    final instance = currentInstance;
    if (instance == null) {
      search.selectSite(null);
      _syncTracking();
      return;
    }

    _workspace.reset(instance);
    _activateInstanceWorkspace(instance, refreshAppearance: refreshAppearance);
  }

  void _activateInstanceWorkspace(
    DiscourseInstance instance, {
    required bool refreshAppearance,
    bool hydrateActiveTab = true,
  }) {
    assert(currentInstance?.url == instance.url);

    final canRead = !instance.loginRequired || instance.isConnected;
    search.selectSite(
      canRead ? instance.url : null,
      logSearchQueries: instance.config.logSearchQueries,
    );
    if (refreshAppearance && canRead) {
      unawaited(
        RequestIntent.background().run(
          () => _presentation.ensureAppearance(instance.url),
        ),
      );
    }
    // Category navigation is first-class shell state. It cannot depend on the
    // default topic feed succeeding, and its ordering/defaults live in the
    // client settings payload. Selection warms rather than ensures because
    // topic opens may already have spent every attempt during an outage.
    if (canRead) {
      unawaited(_presentation.warmConfig(instance.url));
      unawaited(_presentation.warmCustomEmojis(instance.url));
      if (!instance.isConnected) {
        unawaited(_customSidebar.ensure(instance.url));
      }
      // Warm the emoji catalog with the first feed to avoid a second title frame.
      unawaited(_presentation.warmEmojiCatalog(instance.url));
      unawaited(
        RequestIntent.background().run(
          () => _taxonomy.ensureCategoriesFor(instance),
        ),
      );
    }
    for (final activator
        in _pluginSession.capabilities<PluginSiteActivator>()) {
      _observePluginLifecycle(
        Future.sync(
          () => activator.activatePluginSite(
            instance.url,
            connected: instance.isConnected,
          ),
        ),
        'plugins.session.activateSite',
      );
    }
    _syncTracking();
    _syncTopicChannels();
    _retryTopicTrackingLoad(instance.url);
    // Totals may have landed while this site was inactive. The ordinary
    // refresh on reselection can legitimately reuse that five-minute snapshot,
    // so activation itself must notify totals observers instead of relying on
    // a callback which only runs after network responses.
    _notifyPluginTotals(instance);
    if (canRead && hydrateActiveTab) _hydrateActiveTab(instance);
    _refreshBasicInfoOnce(instance.url);
  }

  Future<void> _hydrateHomepage(
    DiscourseInstance instance,
    ForumTab initialTab,
  ) async {
    await _presentation.ensureConfig(instance.url);
    if (instance.isConnected &&
        plugins.registry.homepage(
              siteConfigFor(instance.url).defaultHomepage,
            ) !=
            null) {
      await _refreshSessionUserFor(instance);
    }
    if (isDisposed ||
        currentInstance?.url != instance.url ||
        !_workspace.awaitsHomepage(initialTab.id) ||
        !identical(currentWorkspace?.tabById(initialTab.id), initialTab)) {
      return;
    }
    _workspace.consumeHomepage(initialTab.id);
    _workspace.replaceTab(
      instance.url,
      initialTab.navigate(
        rootDestinationId: initialTab.rootDestinationId,
        contentStack: [_homepageFor(_instanceAt(instance.url) ?? instance)],
      ),
    );
    _notify();
    _hydrateActiveTab(instance);
  }

  void _hydrateActiveTab(DiscourseInstance instance) {
    if (desktopPanelsEnabled) {
      for (final panel in ForumPanel.values) {
        final tab = selectedTabIn(panel);
        if (tab != null) _hydrateTab(instance, tabContext(tab.id));
      }
    } else {
      _hydrateTab(instance, focusedTabContext);
    }
  }

  void _hydrateTab(DiscourseInstance instance, ShellTabContext context) {
    final initialTab = context.tab;
    if (initialTab != null && _workspace.awaitsHomepage(initialTab.id)) {
      unawaited(_hydrateHomepage(instance, initialTab));
      return;
    }
    _rewriteContentRoutes(
      instance.url,
      (route) => route.resolveCategoryLink(filterCategoriesFor(instance.url)),
    );
    final tab = context.tab;
    if (tab == null || currentInstance?.url != instance.url) return;

    final root = tab.contentStack.first;
    unawaited(
      _loadPage(context, root, ContentPageContract.resolve(root).rootLoad),
    );
    final source = context.topicListContent;
    if (source != null && !source.sameDestinationAs(root)) {
      unawaited(context.loadFeed(source.id));
    }
    final route = tab.currentContent;
    final page = ContentPageContract.resolve(route);
    if (page.loadCurrentAtRoot || !route.sameDestinationAs(root)) {
      unawaited(_loadPage(context, route, page.currentLoad));
    }
  }

  int _forumSwitchTraceGeneration = 0;

  @override
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);
    SurfaceOpeningTrace.mark('forum.select');
    final traceGeneration = ++_forumSwitchTraceGeneration;
    _rootMode = ShellRootMode.forum;
    if (mobileNavigationEnabled) mobileNavigation.reset();
    final switched = index != _instanceIndex;
    _instanceIndex = index;
    // Every mobile selection lands on the forum's default route. Restoring the
    // persisted workspace first would activate the site a second time and
    // request a route that is replaced before it is ever shown.
    if (mobileNavigationEnabled) {
      _resetToInstanceDefault();
    } else if (switched) {
      _restoreInstanceWorkspace();
    }
    if (switched) {
      SurfaceOpeningTrace.mark('forum.workspaceRestored');
      final selected = currentInstance;
      if (selected != null && selected.isConnected) {
        unawaited(
          Future.wait([
            _refreshOne(selected),
            _refreshSessionUserFor(selected),
          ]),
        );
      }
    }
    _mobilePane = MobilePane.sidebar;
    _notify();
    SurfaceOpeningTrace.mark('forum.notified');
    SurfaceOpeningTrace.afterFrame(
      'forum.frame',
      isCurrent: () =>
          !isDisposed &&
          _rootMode == ShellRootMode.forum &&
          _instanceIndex == index &&
          traceGeneration == _forumSwitchTraceGeneration,
    );
  }

  void openCurrentSettings() {
    final siteUrl = currentInstance?.url;
    if (siteUrl != null) openForumSettings(siteUrl);
  }

  bool openAppSettingsModal() {
    if (isDisposed || _appSettingsModalOpen) return false;
    _appSettingsModalOpen = true;
    _notify();
    return true;
  }

  void closeAppSettingsModal() {
    if (isDisposed || !_appSettingsModalOpen) return;
    _appSettingsModalOpen = false;
    _notify();
  }

  @override
  void selectDestination(SidebarDestination destination) {
    if (!desktopPanelsEnabled) {
      _workspace.preparePluginPaneForRoute(
        ContentRoute.fromDestination(destination),
      );
    }
    final instance = currentInstance;
    if (instance == null) return;
    final workspace = _workspace.ensure(instance);
    final tab = workspace.activeTab;
    // Tapping what you are already looking at asks for it again — the cache
    // otherwise holds a list for the life of the session, and a mouse cannot
    // pull to refresh. Only at the destination's root: a tap that is busy
    // returning from a topic stays a return.
    final refresh =
        destination.id == tab.rootDestinationId && tab.contentStack.length <= 1;

    final content = destination.id == 'latest'
        ? _homepageFor(instance)
        : destination.id == 'groups'
        ? ContentRoute.group(const GroupRoute.directory())
        : destination.id == 'badges'
        ? ContentRoute.badges(
            const BadgeRoute.directory(),
            title: destination.label,
          )
        : ContentRoute.fromDestination(destination);
    final updated = tab.navigate(
      rootDestinationId: destination.id,
      contentStack: [content],
    );
    _workspace.replaceActiveTab(updated);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();

    final page = ContentPageContract.resolve(content);
    unawaited(
      _loadPage(
        tabContext(updated.id),
        content,
        page.loadOnSelection(refresh: refresh),
        force: refresh,
      ),
    );
  }

  void selectGroupRoute(GroupRoute route, {String? feedPath}) {
    final instance = currentInstance;
    final current = currentContent?.groupRoute;
    if (instance == null ||
        current?.isDetail != true ||
        route.groupName != current!.groupName ||
        route == current) {
      return;
    }
    final content = ContentRoute.group(
      route,
      title: currentContent?.title,
      feedPath: feedPath ?? route.topicFeedPath(instance.user?.username),
    );
    replaceCurrentContent(content);
    if (content.feedPath != null) unawaited(loadFeed(content.id));
  }

  Future<void> selectTopicListMode(
    TopicListMode mode, {
    bool keepTopicOpen = false,
  }) =>
      focusedTabContext.selectTopicListMode(mode, keepTopicOpen: keepTopicOpen);

  Future<void> sortTopicList(String column) =>
      focusedTabContext.sortTopicList(column);

  void selectTopicListCategory(
    TopicCategory? category, {
    bool keepTopicOpen = false,
  }) => focusedTabContext.selectTopicListCategory(
    category,
    keepTopicOpen: keepTopicOpen,
  );

  void selectTopicListTag(String? tagName, {bool keepTopicOpen = false}) =>
      focusedTabContext.selectTopicListTag(
        tagName,
        keepTopicOpen: keepTopicOpen,
      );

  void selectTopicListTags(List<String> tags, {bool keepTopicOpen = false}) =>
      focusedTabContext.selectTopicListTags(tags, keepTopicOpen: keepTopicOpen);

  void clearTopicListFilters() {
    if (currentContent?.isTopicListFilter != true) return;
    _selectTopicListFilter(category: null, tagName: null);
  }

  void _selectTopicListFilter({
    required TopicCategory? category,
    required String? tagName,
    List<String>? tags,
    bool keepTopicOpen = false,
  }) => focusedTabContext._selectTopicListFilter(
    category: category,
    tagName: tagName,
    tags: tags,
    keepTopicOpen: keepTopicOpen,
  );

  void _replaceTopicListContent(
    ContentRoute route, {
    required bool keepTopicOpen,
  }) => focusedTabContext._replaceTopicListContent(
    route,
    keepTopicOpen: keepTopicOpen,
  );

  void browseTopicCategory(
    TopicCategory category, {
    bool keepTopicOpen = false,
  }) {
    _selectTopicListFilter(
      category: category,
      tagName: null,
      keepTopicOpen: keepTopicOpen,
    );
  }

  /// The tags [route] passes on to a list that narrows it. `tags[]`, the
  /// Filter box's `tag:` and a `/tags/c/…/<tag>` segment all look tags up by
  /// name, but a `/tag/<slug>/<id>` list carries the URL slug core derives
  /// from the name (`café` is `cafe`, `中文` is `7-tag`), so its id picks the
  /// name. An unknown tag keeps its slug.
  List<String> _topicListFilterTagNames(String siteUrl, ContentRoute? route) {
    if (route == null) return const [];
    final id = route.tagId;
    final name = id == null ? null : _tagNameFor(siteUrl, id, route.id);
    return name == null ? route.tagNames : [name];
  }

  /// The tag's own list goes first: it follows a rename the sidebar, top tags
  /// and directory have not seen, and names tags none of them hold, such as
  /// one opened from a topic.
  String? _tagNameFor(String siteUrl, int id, String listId) {
    final listed = topicFeeds.feedFor(siteUrl, listId)?.topicIds;
    for (final topicId in listed ?? const <int>[]) {
      final topic = store.read<Topic>(siteUrl, topicId);
      for (final tag in topic?.tags ?? const <TopicTag>[]) {
        if (tag.id == id) return tag.name;
      }
    }
    for (final tag in _taxonomy.knownTagsFor(siteUrl)) {
      if (tag.id == id) return tag.name;
    }
    return null;
  }

  ContentRoute _topicListFilterRoute({
    required String siteUrl,
    required TopicCategory? category,
    required String? tagName,
    List<String>? tags,
    TopicListMode mode = TopicListMode.latest,
  }) {
    final selectedTags =
        (tags ?? [?tagName])
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    // Core interprets numeric tag path segments as IDs, including in category
    // routes. Query filters preserve the selected tag name without ambiguity.
    final numericTagName =
        selectedTags.length == 1 &&
        RegExp(r'^\d+$').hasMatch(selectedTags.single);
    if (mode != TopicListMode.latest ||
        selectedTags.length > 1 ||
        numericTagName) {
      return ContentRoute.filteredTopicList(
        mode,
        categoryId: category?.id,
        tags: selectedTags,
      );
    }
    if (category == null && tagName == null) {
      return ContentRoute.topicList(TopicListMode.latest);
    }

    final categories = filterCategoriesFor(siteUrl);
    final categoriesById = <int, TopicCategory>{
      for (final item in categories) item.id: item,
    };
    if (category case final selected?) {
      categoriesById[selected.id] = selected;
    }
    final categoryDestination = category == null
        ? null
        : buildCategoryDestination(category, categoriesById: categoriesById);
    if (tagName == null) {
      return ContentRoute.fromDestination(categoryDestination!);
    }

    final tagPath = Uri(pathSegments: ['tag', tagName]).toString();
    final selectedCategory = category;
    if (categoryDestination == null || selectedCategory == null) {
      return ContentRoute(
        destination: FeedDestination(
          key: 'topic-list-filter-$tagPath',
          sourcePath: '/$tagPath.json',
        ),
        title: tagName,
        icon: DIcons.tag,
      );
    }

    final categoryFeedPath = categoryDestination.feedPath!;
    final categoryPath = categoryFeedPath.substring(
      0,
      categoryFeedPath.length - '.json'.length,
    );
    final combinedPath = Uri(
      pathSegments: ['tags', ...Uri.parse(categoryPath).pathSegments, tagName],
    ).toString();
    return ContentRoute(
      destination: FeedDestination(
        key: 'topic-list-filter-$combinedPath',
        sourcePath: '/$combinedPath.json',
      ),
      title: selectedCategory.name,
      icon: categoryDestination.icon,
      color: categoryDestination.routeColor,
    );
  }

  void flushAnchorPersist() {
    if (isDisposed) return;
    _workspace.flushAnchors();
  }

  void switchSidebarPanel(VoidCallback switchPanel) =>
      _workspace.switchSidebarPanel(switchPanel);

  void createTab({ForumPanel? panel}) => _workspace.createTab(panel: panel);

  void selectTab(String id) => _workspace.selectTab(id);

  void moveTabToPanel(String id, ForumPanel panel, {int? index}) =>
      _workspace.moveTabToPanel(id, panel, index: index);

  void moveTab(String id, int newIndex) => _workspace.moveTab(id, newIndex);

  void closeTab(String id) => _workspace.closeTab(id);

  bool reopenClosedTab([String? id]) => _workspace.reopenClosedTab(id);

  void closeOtherTabs(String id, {bool? reading, ForumPanel? panel}) =>
      _workspace.closeOtherTabs(id, reading: reading, panel: panel);

  TabOpenResult openContentInNewTab(
    ContentRoute route, {
    String? siteUrl,
    ForumPanel? panel,
    int? index,
    bool? select,
    String? rootDestinationId,
    ForumTab? source,
  }) => _workspace.openContentInNewTab(
    route,
    siteUrl: siteUrl,
    panel: panel,
    index: index,
    select: select,
    rootDestinationId: rootDestinationId,
    source: source,
  );

  TabOpenResult openContentInPanel(
    ContentRoute route, {
    required ForumPanel panel,
    bool resetScrollPosition = false,
    ShellTabContext? context,
  }) => _workspace.openContentInPanel(
    route,
    panel: panel,
    resetScrollPosition: resetScrollPosition,
    context: context,
  );

  @override
  bool activatePluginPane(PluginId owner) =>
      _workspace.activatePluginPane(owner);

  @override
  void deactivatePluginPane(PluginId owner) =>
      _workspace.deactivatePluginPane(owner);

  void openDrafts(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);

    final instance = _instances[index];
    for (final section in instance.sections) {
      for (final destination in section.destinations) {
        if (destination.id == 'drafts') {
          selectDestination(destination);
          return;
        }
      }
    }
  }

  void openUserSummary(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || _instances[index].user == null) return;
    if (index != _instanceIndex) selectInstance(index);
    if (currentContent?.isPage(CorePage.summary) == true) return;
    pushContent(
      ContentRoute(
        destination: const PageDestination(CorePage.summary),
        title: appL10n.summary,
        icon: DIcons.user,
      ),
    );
  }

  void openPreferences(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !_instances[index].isConnected) return;
    if (index != _instanceIndex) selectInstance(index);
    if (currentContent?.isPreferences == true) {
      _mobilePane = MobilePane.content;
      _notify();
      return;
    }
    pushContent(ContentRoute.preferences());
  }

  void openForumSettings(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex || _rootMode != ShellRootMode.forum) {
      selectInstance(index);
    }
    if (currentContent?.isAppearance == true) {
      _mobilePane = MobilePane.content;
      _notify();
      return;
    }
    pushContent(ContentRoute.appearance());
  }

  void openUserActivity(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    if (_instances[index].isConnected != true ||
        currentContent?.isPage(CorePage.activity) == true) {
      return;
    }
    pushContent(ContentRoute.userActivity());
  }

  Future<void> resumeDraft(
    String siteUrl,
    UserDraft draft, {
    bool Function()? sourceIsCurrent,
  }) async {
    if (isDisposed || !draft.canResume) return;
    final lease = lifecycle.capture(siteUrl);
    // Navigation can finish after reconnecting at the same URL. The row and
    // its private contents still belong to the account that started it.
    bool isCurrent() =>
        !isDisposed && lease.isCurrent && (sourceIsCurrent?.call() ?? true);
    if (!isCurrent()) return;
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    final instance = currentInstance;
    if (instance == null || instance.url != siteUrl) return;

    final retained = _composersForSite(
      siteUrl,
    ).where((composer) => composer.target.draftKey == draft.key).firstOrNull;
    if (retained != null) {
      selectComposer(retained);
      return;
    }
    if (draft.isNewTopic) {
      final destination = instance.defaultDestination;
      // Selecting the destination already on screen means "refresh" to the
      // shell. Do not start that second, unawaited request when a header-menu
      // draft is resumed from the default list; openNewTopic needs the
      // creatable feed that is already in hand.
      if (destinationId != destination.id || contentStack.length != 1) {
        selectDestination(destination);
      }
      await loadFeed(destination.id);
      if (!isCurrent() ||
          currentInstance?.url != siteUrl ||
          destinationId != destination.id) {
        return;
      }
      await _openNewTopic(
        permitted: canCreateTopicHere,
        revealContent: false,
        listedDraft: draft,
      );
      return;
    }

    final topicId = draft.topicId;
    if (topicId == null) return;
    pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: draft.slug ?? '',
        title: draft.title ?? draft.displayTitle,
      ),
    );
    await loadTopic(topicId, draft.slug ?? '');
    if (!isCurrent() ||
        currentInstance?.url != siteUrl ||
        currentContent?.topicId != topicId) {
      return;
    }
    final existing = _composer;
    openReply(
      replyToPostNumber: draft.data?.replyToPostNumber,
      replyToUsername: draft.data?.replyToUsername,
      listedDraft: draft,
    );
    final composer = _composer;
    // A composer opened above already ranks the row below its local and
    // cached copies; only one that was open for this topic needs it offered.
    if (composer == null || !identical(composer, existing)) return;
    await _composerDrafts.restoreListedDraft(composer, draft);
  }

  @override
  void openPageTab(ContentRoute route) {
    if (!desktopPanelsEnabled || !forumTabsEnabled) {
      pushContent(route);
      return;
    }
    final existing = currentWorkspace?.tabs
        .where((tab) => route.sameDestinationAs(tab.currentContent))
        .firstOrNull;
    if (existing != null) {
      selectTab(existing.id);
    } else {
      final result = openContentInNewTab(route, select: true);
      if (result == TabOpenResult.limitReached) pushContent(route);
    }
  }

  @override
  void pushContent(
    ContentRoute route, {
    bool newTab = false,
    ForumPanel? panel,
  }) {
    final requestedPanel = panel;
    if (newTab && forumTabsEnabled) {
      openContentInNewTab(
        route,
        source: activeTab,
        panel: requestedPanel,
        select: false,
      );
      return;
    }
    if (desktopPanelsEnabled &&
        requestedPanel != null &&
        activeTab?.panel != requestedPanel) {
      openContentInPanel(route, panel: requestedPanel);
      return;
    }
    final startsPluginPane = _workspace.preparePluginPaneForRoute(route);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _workspace.replaceActiveTab(
      startsPluginPane
          ? tab.copyWith(
              rootDestinationId: route.id,
              contentStack: [route],
              backHistory: const [],
              forwardHistory: const [],
            )
          : tab.push(route),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
  }

  @override
  void setPageSearchWords(String siteUrl, String routeId, String words) {
    if (isDisposed ||
        currentInstance?.url != siteUrl ||
        currentContent?.id != routeId) {
      return;
    }
    search.setPageWords(siteUrl, activeTabId, routeId, words);
  }

  @override
  void replaceCurrentContent(ContentRoute route) {
    final startsPluginPane = _workspace.preparePluginPaneForRoute(route);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _workspace.replaceActiveTab(
      startsPluginPane
          ? tab.copyWith(
              rootDestinationId: route.id,
              contentStack: [route],
              backHistory: const [],
              forwardHistory: const [],
            )
          : tab.navigate(
              contentStack: [
                ...tab.contentStack.take(tab.contentStack.length - 1),
                route,
              ],
            ),
    );
    if (mobileNavigationEnabled) {
      mobileNavigation.replaceCurrent(activeTab!.location);
    }
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
  }

  @override
  void showPluginContent() {
    if (!_setForumContentRoot()) return;
    _notify();
  }

  bool handleBack({bool canReturnToSidebar = true}) =>
      focusedTabContext.handleBack(canReturnToSidebar: canReturnToSidebar);

  bool handleForward() => focusedTabContext.handleForward();

  void _notify() {
    _notifyCurrentWorkspace();
  }

  void _notifyCurrentWorkspace() {
    if (loaded && forumTabs.selectedSiteUrl != currentInstance?.url) {
      _workspace.persist();
    }
    _rememberCurrentContent();
    _topicData.validatePrefetch();
    if (mobileNavigationEnabled) {
      if (_mobilePane == MobilePane.sidebar &&
          mobileNavigation.panelOwner == null &&
          activeTab != null) {
        _mobilePane = MobilePane.content;
      }
      mobileNavigation.synchronize(
        owner: (currentInstance?.url, currentAccountIdentity),
        contentRoot: true,
        location:
            _mobilePane == MobilePane.content &&
                _rootMode == ShellRootMode.forum
            ? activeTab?.location
            : null,
      );
    }
    final request = _pendingTopicProperty;
    if (request != null &&
        (currentInstance?.url != request.siteUrl ||
            !identical(currentContent, request.route) ||
            activeTab?.id != request.tabId ||
            topicNavigationRevision != request.revision)) {
      _pendingTopicProperty = null;
    }
    notifySafely();
  }

  void toggleMobileSidebar() {
    if (!mobileNavigationEnabled) return;
    if (!mobileNavigation.closeSidebar()) mobileNavigation.openSidebar();
    _notify();
  }

  void closeMobileSidebar() {
    if (mobileNavigation.closeSidebar()) _notify();
  }

  void selectMobilePanel(String? owner) {
    if (!mobileNavigationEnabled) return;
    mobileNavigation.selectPanel(owner);
    _rootMode = ShellRootMode.forum;
    _mobilePane = MobilePane.sidebar;
    _notify();
  }

  /// Starts a tab's journey using the same route and permission owners as desktop.
  void selectMobileDestination(MobileTab tab, SidebarDestination destination) {
    if (!mobileNavigationEnabled || !destination.enabled) return;
    mobileNavigation.selectTab(tab);
    _rootMode = ShellRootMode.forum;
    selectDestination(destination);
  }

  void _restoreMobileLocation() {
    final location = mobileNavigation.location;
    final tab = activeTab;
    if (mobileNavigation.atRoot) {
      _mobilePane = MobilePane.sidebar;
    } else if (tab != null && location != null) {
      _workspace.replaceActiveTab(
        tab.copyWith(
          rootDestinationId: location.rootDestinationId,
          contentStack: location.contentStack,
        ),
      );
      _mobilePane = MobilePane.content;
    }
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance? when location != null) {
      _hydrateActiveTab(instance);
    }
  }

  @override
  void dispose() {
    _bookmarks.dispose();
    _topicData.dispose();
    // Queue the final local draft before lifecycle invalidation without
    // entering the normal remote-sync callback.
    for (final composer in _composers) {
      _composerDrafts.preservePendingLocally(composer);
    }
    _discoverSites?.dispose();
    for (final watch in _cookingWatches) {
      watch.retire();
    }
    _cookingWatches.clear();
    unawaited(cooking.dispose());

    // A window can close in the frame immediately after a selection or a
    // scroll. Keep the latest local choice and anchor durable, but never start
    // hydration while tearing the controller down.
    _workspace.dispose();
    _topicPostHighlightTimer?.cancel();
    _topicPostHighlightTimer = null;
    _topicPostHighlight = null;
    _topicPostHighlightVisible = false;
    _topicPropertyRequests.dispose();
    unawaited(_topicListRevealRequests.close());
    _topicNotificationWrites.clear();
    _topicNotificationTails.clear();
    _categoryNotificationWrites.clear();
    _categoryNotificationTails.clear();
    _categoryNotificationConfirmed.clear();
    _categoryNotificationSiteTails.clear();
    for (final owner in _currentUserReconcilers.values) {
      owner.retire();
    }
    _currentUserReconcilers.clear();
    _topicPinWrites.clear();
    _topicStatusWrites.clear();
    _messageArchiveWrites.clear();
    _userStatusWrites.clear();
    _optimisticHidePresence.clear();
    _hidePresenceWrites.clear();
    _hidePresenceErrors.clear();
    for (final timer in _pluginNotificationFeedRefreshTimers.values) {
      timer.cancel();
    }
    _pluginNotificationFeedRefreshTimers.clear();
    _siteNotificationTypes.clear();
    for (final request in _siteNotificationTypeRequests.values) {
      request.ignore();
    }
    _siteNotificationTypeRequests.clear();
    _topicDeletionWrites.clear();
    _topicPostSelections.clear();
    _topicPostSelectionWrites.clear();
    _topicFlagWrites.clear();
    _topicJumpRuns.clear();
    _topicReads.dispose();
    _customSidebar.dispose();
    for (final instance in _instances) {
      lifecycle.invalidate(instance.url);
    }
    _taxonomy.dispose();
    for (final tracking in _topicTrackingBySite.values) {
      tracking.retire();
    }
    _topicTrackingBySite.clear();
    _topicTrackingRetries.clear();
    updates.dispose();
    accountActivity.dispose();
    doNotDisturb.dispose();
    userStatuses.dispose();
    userCardRequests.dispose();
    likerRequests.dispose();
    draftList.dispose();
    userSummary.dispose();
    groups.dispose();
    userDirectory.dispose();
    badges.dispose();
    preferences.dispose();
    topicFeeds.dispose();
    appSettings.dispose();
    forumSettings.dispose();
    siteImages.dispose();
    videoThumbnails.dispose();
    pdfThumbnails.dispose();
    final closePluginSession = _pluginSession.close();
    _backgroundRetention.close();
    _observePluginLifecycle(closePluginSession, 'plugins.session.close');
    if (_ownsPlugins) {
      final closeOwnedPlugins = closePluginSession
          .onError((_, _) {})
          .then((_) => plugins.close());
      _pluginTeardownFuture = closeOwnedPlugins;
      _observePluginLifecycle(closeOwnedPlugins, 'plugins.close');
    } else {
      _pluginTeardownFuture = closePluginSession;
    }
    globalSearch.dispose();
    search.dispose();

    for (final listenable in _pluginSiteConfigListenables.values) {
      listenable.dispose();
    }
    _pluginSiteConfigListenables.clear();
    final presentation = _sitePresentation;
    if (presentation != null) {
      presentation.removeListener(_notify);
      presentation.dispose();
    }
    for (final composer in _composers) {
      composer.dispose();
    }
    _composers.clear();
    _selectedComposers.clear();
    _composerRevealTarget = null;
    for (final tracker in _trackers.values) {
      tracker.dispose().ignore();
    }
    _trackers.clear();
    _trackerStartRequests.clear();
    _readerContentBounds.dispose();
    if (ownsApi) api.close();
    super.dispose();
  }
}

typedef _CookingSourceStamp = ({
  int revision,
  SiteConfig config,
  Object presentation,
  bool staleSettings,
  (int?, String?, String?) user,
  String readerTimezone,
  int users,
  int topics,
});

/// Active draft observers own only the bounded refs their source mentions.
final class _CookingWatch {
  _CookingWatch({required this.read, required this.onChanged})
    : _stamp = read();

  final _CookingSourceStamp Function() read;
  final VoidCallback onChanged;
  final List<VoidCallback> _retire = [];
  _CookingSourceStamp _stamp;
  bool _active = true;
  bool _pending = false;

  void listen(Listenable source) {
    source.addListener(changed);
    onRetire(() => source.removeListener(changed));
  }

  void onRetire(VoidCallback callback) => _retire.add(callback);

  void changed() {
    if (!_active) return;
    final next = read();
    if (next == _stamp) return;
    _stamp = next;
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_active) onChanged();
    });
  }

  void retire() {
    if (!_active) return;
    _active = false;
    for (final callback in _retire) {
      callback();
    }
    _retire.clear();
  }
}

final class _PluginSiteConfigListenable extends ChangeNotifier
    implements ValueListenable<SiteConfig> {
  _PluginSiteConfigListenable(Listenable source, SiteConfig Function() read)
    : _source = source,
      _read = read,
      _value = read() {
    _source.addListener(_refresh);
  }

  final Listenable _source;
  final SiteConfig Function() _read;
  SiteConfig _value;

  @override
  SiteConfig get value => _value;

  void _refresh() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_refresh);
    super.dispose();
  }
}

final class _ScopedEmojiPreferenceStore implements EmojiPreferenceStore {
  const _ScopedEmojiPreferenceStore(this._delegate, this._consumer);

  final EmojiPreferenceStore _delegate;
  final PluginId _consumer;

  void _requireOwned(EmojiUsageContext context) {
    if (context.isValidFor(_consumer)) return;
    throw PluginInstallationException(
      appL10n.pluginCannotUseEmojiContext(
        (_consumer).toString(),
        (context.id).toString(),
      ),
    );
  }

  @override
  Future<EmojiSkinTone> readSkinTone({required String siteUrl}) =>
      _delegate.readSkinTone(siteUrl: siteUrl);

  @override
  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) {
    _requireOwned(context);
    return _delegate.favoriteEmojiCodes(
      siteUrl: siteUrl,
      context: context,
      catalog: catalog,
    );
  }

  @override
  Future<void> writeSkinTone({
    required String siteUrl,
    required EmojiSkinTone tone,
  }) => _delegate.writeSkinTone(siteUrl: siteUrl, tone: tone);

  @override
  Future<void> trackEmoji({
    required String siteUrl,
    required EmojiUsageContext context,
    required String emoji,
  }) {
    _requireOwned(context);
    return _delegate.trackEmoji(
      siteUrl: siteUrl,
      context: context,
      emoji: emoji,
    );
  }

  @override
  Future<void> clearHistory({
    required String siteUrl,
    required EmojiUsageContext context,
  }) {
    _requireOwned(context);
    return _delegate.clearHistory(siteUrl: siteUrl, context: context);
  }
}

final class _ShellPluginSiteLease implements PluginSiteLease {
  const _ShellPluginSiteLease(this.value);

  final SiteLease value;

  @override
  bool get isCurrent => value.isCurrent;

  @override
  bool commit(VoidCallback mutation) => value.commit(mutation);
}

final class _ShellPluginRequestHost implements PluginRequestHost {
  const _ShellPluginRequestHost(this._shell);

  final ShellController _shell;

  @override
  PluginSiteLease capture(String siteUrl) =>
      _ShellPluginSiteLease(_shell.lifecycle.capture(siteUrl));

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    final snapshot = await AccountRequestSession(
      siteUrl,
      _shell.lifecycle.capture(siteUrl),
    ).credentials(_shell.credentials);
    return PluginRequestCredentials(
      apiKey: snapshot.apiKey,
      clientId: snapshot.clientId,
      execute: snapshot.run,
    );
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      _shell.pluginWriteCredential(siteUrl);
}

final class _ShellPluginAccountConnectionHost
    implements PluginAccountConnectionHost {
  const _ShellPluginAccountConnectionHost(this._shell);

  final ShellController _shell;

  @override
  bool isConnected(String siteUrl) =>
      _shell._instanceAt(siteUrl)?.isConnected == true;

  @override
  Future<String?> connect(String siteUrl) async {
    if (_shell.currentInstance?.url != siteUrl) return null;
    await _shell.connectCurrentInstance();
    return _shell._connectErrors[siteUrl];
  }
}

final class _ShellPluginTargetHost implements PluginTargetHost {
  const _ShellPluginTargetHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  PluginTargetSnapshot<T> recordFor<T extends Object>(
    String siteUrl,
    PluginTarget target,
    PluginDataKey<T> key,
  ) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        appL10n.pluginCannotInspectPluginDataOwnedBy(
          (_consumer).toString(),
          (key.owner).toString(),
        ),
      );
    }
    final snapshot = _shell._pluginDataForTarget(siteUrl, target);
    return (valid: snapshot.valid, value: snapshot.data.get(key));
  }
}

final class _ShellPluginFreshAccountHost implements PluginFreshAccountHost {
  const _ShellPluginFreshAccountHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  DiscourseUser? _user(String siteUrl) => _shell.freshCurrentUserFor(siteUrl);

  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) {
    final user = _user(siteUrl);
    return user == null
        ? null
        : PluginFreshAccountProfile(staff: user.staff, groups: user.groups);
  }

  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        appL10n.pluginCannotInspectCurrentUserDataOwnedBy(
          (_consumer).toString(),
          (key.owner).toString(),
        ),
      );
    }
    return _user(siteUrl)?.plugins.get(key);
  }
}

final class _ShellPluginPostHost implements PluginPostHost {
  const _ShellPluginPostHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  Post? readPost(String siteUrl, int postId) =>
      _shell.store.read<Post>(siteUrl, postId);

  @override
  bool topicArchived(String siteUrl, int topicId) =>
      _shell.store.read<TopicDetail>(siteUrl, topicId)?.archived == true;

  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T? held) update,
  ) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        appL10n.pluginCannotUpdatePluginDataOwnedBy(
          (_consumer).toString(),
          (key.owner).toString(),
        ),
      );
    }
    _shell.store.update<Post>(siteUrl, postId, (held) {
      final next = update(held.plugins.get(key));
      return held.withPlugins(held.plugins.withValue(key, next));
    });
    _shell.notifyPluginStateChanged();
  }

  @override
  bool beginWrite(String siteUrl, int postId) =>
      _shell.beginPluginPostWrite(siteUrl, postId);

  @override
  void endWrite(String siteUrl, int postId) =>
      _shell.endPluginPostWrite(siteUrl, postId);

  @override
  bool writeInFlight(String siteUrl, int postId) =>
      _shell.pluginPostWriteInFlight(siteUrl, postId);

  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) {
    if (lease is! _ShellPluginSiteLease) {
      throw ArgumentError.value(
        lease,
        'lease',
        'Lease belongs to another host.',
      );
    }
    return _shell.refreshPluginPost(
      siteUrl,
      topicId,
      postId,
      apiKey,
      lease.value,
    );
  }
}

final class _ShellPluginNavigationHost implements PluginNavigationHost {
  const _ShellPluginNavigationHost(this._shell, this._isDisposed);

  final ShellController _shell;
  final bool Function() _isDisposed;

  @override
  Listenable get changes => _shell;

  @override
  List<DiscourseInstance> get instances => _shell.instances;

  @override
  DiscourseInstance? get currentInstance => _shell.currentInstance;

  @override
  bool get forumActive => _shell.forumActive;

  @override
  bool get desktopPanelsEnabled => _shell.desktopPanelsEnabled;

  @override
  bool get isDisposed => _isDisposed();

  @override
  String? get activeTabId => _shell.activeTabId;

  @override
  ContentRoute? get currentContent => _shell.currentContent;

  @override
  List<ContentRoute> get contentStack => _shell.contentStack;

  @override
  NotificationTotals? get currentTotals => _shell.currentTotals;

  @override
  PluginVisibleTopicContext? get visibleTopicContext =>
      _shell.visibleTopicContext;

  @override
  Rect? get readerContentBounds => _shell.readerContentBounds;

  @override
  ValueListenable<Rect?> get readerContentBoundsListenable =>
      _shell.readerContentBoundsListenable;

  @override
  void selectInstance(int index) => _shell.selectInstance(index);

  @override
  void selectDestination(SidebarDestination destination) =>
      _shell.selectDestination(destination);

  @override
  void setPageSearchWords(String siteUrl, String routeId, String words) {
    if (!isDisposed) _shell.setPageSearchWords(siteUrl, routeId, words);
  }

  @override
  void openPageTab(ContentRoute route) => _shell.openPageTab(route);

  @override
  void pushContent(
    ContentRoute route, {
    bool newTab = false,
    ForumPanel? panel,
  }) => _shell.pushContent(route, newTab: newTab, panel: panel);

  @override
  void replaceCurrentContent(ContentRoute route) =>
      _shell.replaceCurrentContent(route);

  @override
  void showPluginContent() => _shell.showPluginContent();

  @override
  bool activatePluginPane(PluginId owner) => _shell.activatePluginPane(owner);

  @override
  void deactivatePluginPane(PluginId owner) =>
      _shell.deactivatePluginPane(owner);
}

final class _ShellPluginRouteNavigationHost
    implements PluginRouteNavigationHost, PluginRoutePresentationHost {
  const _ShellPluginRouteNavigationHost(this._shell);

  final ShellController _shell;

  @override
  void addListener(VoidCallback listener) => _shell.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _shell.removeListener(listener);

  @override
  bool get mobileNavigationEnabled => _shell.mobileNavigationEnabled;

  @override
  bool get currentContentVisible =>
      _shell.forumActive &&
      (!_shell.mobileNavigationEnabled ||
          (_shell.mobilePane == MobilePane.content &&
              !_shell.mobileNavigation.sidebarOpen &&
              _shell.mobileNavigation.panelOwner == null));

  @override
  String? get activeTabId => _shell.activeTabId;

  @override
  List<PluginRouteSite> get sites => List.unmodifiable([
    for (final instance in _shell.instances)
      PluginRouteSite(
        url: instance.url,
        title: instance.title,
        isConnected: instance.isConnected,
      ),
  ]);

  @override
  PluginRouteSite? get currentSite {
    final instance = _shell.currentInstance;
    return instance == null
        ? null
        : PluginRouteSite(
            url: instance.url,
            title: instance.title,
            isConnected: instance.isConnected,
          );
  }

  @override
  ContentRoute? get currentContent => _shell.currentContent;

  @override
  void selectInstance(int index) => _shell.selectInstance(index);

  @override
  void pushContent(ContentRoute route) => _shell.pushContent(route);

  @override
  void replaceCurrentContent(ContentRoute route) =>
      _shell.replaceCurrentContent(route);

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) => _shell.openTopicPost(
    siteUrl: siteUrl,
    topicId: topicId,
    postNumber: postNumber,
    highlight: highlight,
  );
}

final class _ShellPluginTopicListNavigationHost
    implements PluginTopicListNavigationHost {
  const _ShellPluginTopicListNavigationHost(this._shell);

  final ShellController _shell;

  @override
  void openTopicList(ContentRoute route) {
    if (route.destination is! FeedDestination ||
        route.sameDestinationAs(_shell.currentContent)) {
      return;
    }
    _shell.pushContent(route);
    unawaited(_shell.loadFeed(route.id));
  }
}

final class _ShellPluginBookmarkHostFactory
    implements PluginBookmarkHostFactory {
  const _ShellPluginBookmarkHostFactory(this._shell);

  final ShellController _shell;

  PluginBookmarkHostFactory scopedTo(PluginId consumer) =>
      _ShellScopedPluginBookmarkHostFactory(_shell, consumer);

  @override
  PluginBookmarkHost forTarget(BookmarkTargetType targetType) =>
      throw StateError(
        'The bookmark host factory must be scoped to a plugin session.',
      );
}

final class _ShellScopedPluginBookmarkHostFactory
    implements PluginBookmarkHostFactory {
  const _ShellScopedPluginBookmarkHostFactory(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  PluginBookmarkHost forTarget(BookmarkTargetType targetType) {
    if (targetType.owner != _consumer) {
      throw PluginInstallationException(
        appL10n.pluginCannotRequestBookmarkTarget(
          (_consumer).toString(),
          (targetType.id).toString(),
        ),
      );
    }
    return _shell._bookmarks.pluginTarget(targetType);
  }
}

final class _ShellPluginNotificationFeedHost
    implements PluginNotificationFeedHost {
  const _ShellPluginNotificationFeedHost(this._shell);

  final ShellController _shell;

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) =>
      _shell.notificationFeedListenable(id);

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => _shell.notificationFeedFor(id, siteUrl);

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) => _shell.loadPluginNotificationFeed(siteUrl, source);

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) => _shell.dismissPluginNotifications(siteUrl, source);

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _shell.readPluginNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      _shell.pluginAbsoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      _shell.openPluginNotificationUrl(url);
}

final class _ShellScopedPluginNotificationFeedHost
    implements PluginNotificationFeedHost {
  const _ShellScopedPluginNotificationFeedHost(
    this._host,
    this._consumer,
    this._sources,
  );

  final PluginNotificationFeedHost _host;
  final PluginId _consumer;
  final Map<PluginNotificationFeedId, PluginNotificationFeedSource> _sources;

  PluginNotificationFeedSource _requireDeclared(PluginNotificationFeedId id) {
    final source = _sources[id];
    if (source != null) return source;
    final reason = id.owner == _consumer
        ? appL10n.didNotRegisterNotificationFeed
        : appL10n.cannotAccessNotificationFeed;
    throw PluginInstallationException(
      appL10n.plugin(
        (_consumer).toString(),
        (reason).toString(),
        (id.id).toString(),
      ),
    );
  }

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) {
    _requireDeclared(id);
    return _host.notificationFeedListenable(id);
  }

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) {
    _requireDeclared(id);
    return _host.notificationFeedFor(id, siteUrl);
  }

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        appL10n.pluginMustUseItsRegisteredNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    return _host.loadPluginNotificationFeed(siteUrl, registered);
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        appL10n.pluginMustUseItsRegisteredNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    if (registered.dismissal == null) {
      throw PluginInstallationException(
        appL10n.pluginDidNotRegisterDismissalForNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    return _host.dismissPluginNotifications(siteUrl, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _host.readPluginNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      _host.pluginAbsoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      _host.openPluginNotificationUrl(url);
}

final class _QueuedTopicNotification {
  _QueuedTopicNotification({
    required this.siteUrl,
    required this.topicId,
    required this.level,
    required this.lease,
    required this.tracking,
    required this.choice,
  });

  final String siteUrl;
  final int topicId;
  final TopicNotificationLevel level;
  final SiteLease lease;
  final TopicTrackingReconciler tracking;
  final TopicTrackingChoice choice;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}

final class _QueuedCategoryNotification {
  _QueuedCategoryNotification({
    required this.siteUrl,
    required this.categoryId,
    required this.level,
    required this.lease,
  });

  final String siteUrl;
  final int categoryId;
  final CategoryNotificationLevel level;
  final SiteLease lease;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}
