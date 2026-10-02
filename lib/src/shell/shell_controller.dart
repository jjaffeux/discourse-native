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

import '../data/account_session_coordinator.dart';
import '../data/api_credentials.dart';
import '../data/app_settings_store.dart';
import '../data/application_cooking.dart';
import '../data/authenticator.dart';
import '../data/badges_api.dart';
import '../data/bookmark_reminder_store.dart';
import '../data/composer_image_optimizer.dart';
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
import '../data/topic_recommendations_tab_store.dart';
import '../data/topic_sidebar_store.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../data/user_directory_api.dart';
import '../data/user_directory_column_width_store.dart';
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
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
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
import '../models/topic_tracking_message_filter.dart';
import '../models/topic_tracking_state.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
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
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'app_settings_controller.dart';
import 'badges_controller.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'composer_draft_coordinator.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_triggers.dart';
import 'do_not_disturb_controller.dart';
import 'draft_list_controller.dart';
import 'forum_settings_controller.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
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
import 'topic_feed_controller.dart';
import 'topic_prefetch_controller.dart';
import 'topic_read_controller.dart';
import 'unread_topic_feed.dart';
import 'update_controller.dart';
import 'user_directory_controller.dart';
import 'user_status_overrides.dart';
import 'user_summary_controller.dart';

enum MobilePane { sidebar, content }

enum ShellRootMode { forum }

enum InstanceLoadStatus { loading, ready, failed }

enum TabOpenResult { opened, unsupported, limitReached }

typedef _PluginUserOptionUpdate = ({
  int revision,
  PluginData Function(PluginData) update,
});

typedef TopicMoveDestination = ({int id, String title, String slug});

// A site can retain a substantial topic, post, and taxonomy working set, while
// per-site/type shares stop one long browsing session from displacing every
// other connected forum.
const _shellEntityStorePolicy = StorePolicy(
  maxEntries: 4096,
  maxEntriesPerSite: 2048,
  maxEntriesPerSiteAndType: 1024,
);

/// Every preference core keeps on the device per forum. They name the forum,
/// and some its accounts or what was used there, so they leave with it.
const _coreSitePreferenceKeys = [
  BookmarkReminderStore.keys,
  SharedPreferencesEmojiPickerPersistence.keys,
  ForumSettingsStore.themeModeKeys,
  ForumSettingsStore.themesKeys,
  SharedPreferencesSidebarSectionPersistence.keys,
  SharedPreferencesTopicSidebarPersistence.keys,
  SharedPreferencesTopicRecommendationsTabPersistence.keys,
  SharedPreferencesUserDirectoryColumnWidthPersistence.keys,
];

typedef TopicMoveDestinationSearchResult = ({
  List<TopicMoveDestination> destinations,
  String? error,
});
typedef TopicPostMoveResult = ({String? destinationUrl, String? error});
typedef _SessionValue<T> = ({T value});
typedef _CategorySidebarCache = ({
  List<TopicCategory> categories,
  DiscourseUser? user,
  SiteConfig config,
  SidebarSection section,
});
typedef _TagSidebarCache = ({
  List<SidebarTag> tags,
  bool display,
  String? username,
  SidebarSection section,
});
typedef _TopicListFilterTagSources = ({
  (int?, String?) account,
  List<SidebarTag> personal,
  List<SidebarTag> siteTop,
  List<SidebarTag> anonymousDefaults,
  List<SidebarTag> directory,
});
typedef _TopicListFilterTagsCache = ({
  _TopicListFilterTagSources sources,
  List<SidebarTag> tags,
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
typedef _TopicPostHighlight = ({String siteUrl, int topicId, int postNumber});

int? _destinationNumericId(String destinationId, String prefix) {
  if (!destinationId.startsWith(prefix)) return null;
  final id = int.tryParse(destinationId.substring(prefix.length));
  return id != null && id > 0 ? id : null;
}

sealed class _BookmarkWriteContext {
  const _BookmarkWriteContext();
}

final class _TopicBookmarkWriteContext extends _BookmarkWriteContext {
  const _TopicBookmarkWriteContext(this.topicId);

  final int topicId;
}

final class _PluginBookmarkWriteContext extends _BookmarkWriteContext {
  const _PluginBookmarkWriteContext();
}

const _pluginBookmarkWriteContext = _PluginBookmarkWriteContext();

/// The held posts of one topic that one synchronous run of live messages
/// named for a re-read. It is also the owner token of each post's read, so a
/// write that disowns a queued post keeps it out of the request.
final class _PostRefreshBatch {
  _PostRefreshBatch(this.siteUrl, this.topicId, this.lease);

  final String siteUrl;
  final int topicId;
  final SiteLease lease;

  /// In the order the run named them; a post named twice is read once.
  final Set<int> postIds = {};
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
      siteUrl: siteUrl,
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
            return _composer?.target.editingPostId == postId;
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
            final revision = (_pluginUserOptionVersions[siteUrl] ?? 0) + 1;
            _pluginUserOptionVersions[siteUrl] = revision;
            (_pluginUserOptionUpdates[siteUrl] ??= {})[field] = (
              revision: revision,
              update: update,
            );
            final updated = user.withPlugins(update(user.plugins));
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
              _refetchTopic(siteUrl, topicId, ''),
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

  Future<PluginWriteCredential> pluginWriteCredential(String siteUrl) =>
      _credentialForWrite(siteUrl);

  bool beginPluginPostWrite(String siteUrl, int postId) =>
      _beginPostWrite(_postKey(siteUrl, postId));

  void endPluginPostWrite(String siteUrl, int postId) =>
      _endPostWrite(siteUrl, postId);

  bool pluginPostWriteInFlight(String siteUrl, int postId) =>
      _postWritesInFlight.containsKey(_postKey(siteUrl, postId));

  Future<void> refreshPluginPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) => _refreshPost(siteUrl, topicId, postId, apiKey, lease);

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

  Future<PluginWriteCredential> _credentialForWrite(String siteUrl) async {
    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      return apiKey == null
          ? (
              apiKey: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: apiKey, failure: null);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.readWriteCredential',
      );
      return (
        apiKey: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<_SessionValue<T>?> _readSessionValue<T>(
    SiteLease lease,
    Future<T> Function() read,
  ) async {
    final value = await read();
    if (isDisposed || !lease.isCurrent) return null;
    return (value: value);
  }

  /// Reads the client id to send beside [apiKey]; an anonymous request reads
  /// none, since reading it can raise the platform's notification prompt (see
  /// [ApiCredentialReader.clientId]).
  Future<_SessionValue<String?>?> _readClientIdFor(
    SiteLease lease,
    String? apiKey,
  ) => _readSessionValue(
    lease,
    () async => apiKey == null ? null : await authenticator.clientId(),
  );

  Future<T> _awaitTopicLoadStage<T>(
    Future<T> stage,
    Stopwatch elapsed,
    String description,
  ) {
    final remaining = topicLoadTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException(
          appL10n.timedOut((description).toString()),
          topicLoadTimeout,
        ),
      );
    }
    return stage.timeout(
      remaining,
      onTimeout: () => throw TimeoutException(
        appL10n.timedOut((description).toString()),
        topicLoadTimeout,
      ),
    );
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
        onGroupedUnreadAuthorityAdvanced:
            _advanceGroupedUnreadNotificationVersion,
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
      prepareFeed: (instance, apiKey, categories, categoryIds) async {
        final lease = lifecycle.capture(instance.url);
        if (categories.isNotEmpty) {
          _mergeCategories(instance.url, categories);
          _notify();
        }
        if (isDisposed || !lease.isCurrent) return;
        unawaited(_ensureCategoriesFor(instance));
        await _ensureCategoryIds(instance, apiKey, categoryIds);
      },
      readPersonalizationVersion: _siteBookmarkVersion,
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
  }) async {
    for (final handler in _pluginSession.capabilities<PluginLinkHandler>()) {
      if (await handler.openPluginUrl(url, origin: origin)) return true;
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

    final owner = _instances
        .where((instance) => instance.isConnected && instance.serves(target))
        .firstOrNull;
    if (owner == null) return false;

    final lease = lifecycle.capture(owner.url);
    final absolute = target.toString();
    final pluginHandled = await openPluginUrl(
      absolute,
      origin: PluginLinkOrigin.inApp,
    );
    if (isDisposed ||
        !lease.isCurrent ||
        _instanceAt(owner.url)?.isConnected != true) {
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

  final Map<String, ForumWorkspace> _forumWorkspaces = {};

  /// The workspace an account-session operation rotated away, until that
  /// operation settles. Only a rollback to the account that owned it may put
  /// it back; every other outcome lets it go.
  final Map<String, ForumWorkspace> _rotatedWorkspaces = {};
  final List<_ClosedForumTab> _closedForumTabs = [];
  final Map<_PluginPaneKey, ForumTab> _mainPaneTabs = {};
  final Map<_PluginPaneKey, ForumTab> _pluginPaneTabs = {};
  final Map<_PluginPaneStateKey, PluginId> _activePluginPanes = {};
  final Set<_PluginPaneStateKey> _coldPluginPanes = {};
  int _tabSequence = 0;
  ({String siteUrl, String tabId})? _pendingTabSelection;
  bool _tabSelectionSettlementScheduled = false;
  bool _tabSelectionPersistencePending = false;
  Timer? _anchorPersistTimer;
  bool _anchorPersistencePending = false;

  /// Settles with the newest workspace write. Those writes are serial, so
  /// every earlier one has settled by then too.
  Future<void> _workspacesSaved = Future<void>.value();

  ForumWorkspace? get currentWorkspace {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _forumWorkspaces[siteUrl];
  }

  ForumWorkspace? workspaceFor(String siteUrl) => _forumWorkspaces[siteUrl];

  bool _desktopTopicTabs = false;
  bool get desktopTopicTabs => _desktopTopicTabs;
  set desktopTopicTabs(bool value) {
    if (_desktopTopicTabs == value) return;
    _desktopTopicTabs = value;
    if (value) {
      for (final workspace in _forumWorkspaces.values.toList()) {
        _putWorkspace(workspace);
      }
      scheduleMicrotask(() {
        if (!isDisposed && desktopPanelsEnabled && currentInstance != null) {
          _hydrateActiveTab(currentInstance!);
          _syncTopicChannels();
        }
      });
    }
  }

  /// Whether the desktop workspace currently has room for both panels.
  bool topicPanelsVisible = false;
  @override
  bool get desktopPanelsEnabled => desktopTopicTabs && forumTabsEnabled;

  bool isTabVisible(String? id) {
    if (id == null) return false;
    final workspace = currentWorkspace;
    if (workspace == null) return false;
    if (!desktopTopicTabs) return workspace.activeTabId == id;
    return ForumPanel.values.any(
      (panel) => workspace.selectedTabIn(panel)?.id == id,
    );
  }

  ForumTab? get listPanelTab =>
      currentWorkspace?.selectedTabIn(ForumPanel.main);

  int? get readingTopicId {
    if (!desktopTopicTabs) return currentContent?.topicId;
    final source = activeTab;
    if (source?.currentContent.isTopic == true) {
      return source!.currentContent.topicId;
    }
    final other = source?.panel == ForumPanel.secondary
        ? ForumPanel.main
        : ForumPanel.secondary;
    return selectedTabIn(other)?.currentContent.topicId;
  }

  ForumTab? selectedTabIn(ForumPanel panel) =>
      currentWorkspace?.selectedTabIn(panel);

  String? _snapshotTabId;

  /// Evaluates synchronous presentation reads for a particular tab. The
  /// selection is restored before returning; this never focuses or navigates.
  T readTab<T>(String? tabId, T Function() read) {
    final previous = _snapshotTabId;
    _snapshotTabId = tabId;
    try {
      return read();
    } finally {
      _snapshotTabId = previous;
    }
  }

  ForumTab? get activeTab => _snapshotTabId == null
      ? currentWorkspace?.activeTab
      : currentWorkspace?.tabById(_snapshotTabId!);
  String? get activeTabId => activeTab?.id;
  List<ForumTab> get tabsForCurrentForum => currentWorkspace?.tabs ?? const [];
  List<ForumTab> get recentlyClosedTabsForCurrentForum {
    final workspace = currentWorkspace;
    if (workspace == null) return const [];
    final openIds = {for (final tab in workspace.tabs) tab.id};
    return List.unmodifiable([
      for (final closed in _closedForumTabs.reversed)
        if (closed.siteUrl == workspace.siteUrl &&
            closed.accountIdentity == workspace.accountIdentity &&
            !openIds.contains(closed.tab.id))
          closed.tab,
    ]);
  }

  bool get canCreateTab =>
      forumTabsEnabled &&
      (currentWorkspace?.tabs.length ?? 0) < ForumWorkspace.maximumTabs;

  String? get destinationId => activeTab?.rootDestinationId;

  @override
  List<ContentRoute> get contentStack => activeTab?.contentStack ?? const [];
  @override
  ContentRoute? get currentContent => activeTab?.currentContent;

  String _recentAccountIdentity(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    return instance == null ? 'anonymous' : _workspaceAccountIdentity(instance);
  }

  List<ContentRoute> recentCategoriesFor(String siteUrl) => recentDestinations
      .categoriesFor(siteUrl, _recentAccountIdentity(siteUrl));

  /// Uses the loaded topic tracking snapshot and live updates, with the same
  /// category counting rules as sidebar badges.
  int categoryActivityCountFor(String siteUrl, int categoryId) {
    final user = _instanceAt(siteUrl)?.user;
    final tracking = _topicTrackingBySite[siteUrl];
    if (user == null ||
        tracking == null ||
        !_topicTrackingSnapshotsLoaded.contains(siteUrl)) {
      return 0;
    }
    return tracking
        .categoryBadge(
          categoryId: categoryId,
          categories: _categoriesBySite[siteUrl] ?? const [],
          unifiedNew: user.unifiedNewEnabled,
          showCount: true,
        )
        .count;
  }

  List<ContentRoute> recentChannelsFor(String siteUrl) =>
      recentDestinations.channelsFor(siteUrl, _recentAccountIdentity(siteUrl));
  List<ContentRoute> recentTopicsFor(String siteUrl) =>
      recentDestinations.topicsFor(siteUrl, _recentAccountIdentity(siteUrl));

  /// Reads the shared Latest feed without starting a request. The Start page
  /// requests this feed on entry, and the feed controller reuses cached data.
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

  bool get canPopContent => mobileNavigationEnabled
      ? mobileNavigation.canGoBack
      : activeTab?.canGoBack ?? false;
  bool get canForwardContent => mobileNavigationEnabled
      ? mobileNavigation.canGoForward
      : activeTab?.canGoForward ?? false;

  Future<void>? Function()? _contentRefresher;
  final _refreshingTabs = <(ShellRootMode, String?, String?, String?)>{};

  (ShellRootMode, String?, String?, String?) get _currentRefreshKey =>
      (rootMode, currentInstance?.url, currentAccountIdentity, activeTabId);

  bool get refreshingCurrentTab => _refreshingTabs.contains(_currentRefreshKey);

  bool get canRefreshCurrentTab =>
      loaded &&
      hasInstances &&
      currentContent != null &&
      currentInstance != null &&
      (!currentInstance!.loginRequired || currentInstance!.isConnected);

  /// Returning null lets the shell use the route's standard loader.
  VoidCallback registerContentRefresher(Future<void>? Function() refresh) {
    _contentRefresher = refresh;
    return () {
      if (identical(_contentRefresher, refresh)) _contentRefresher = null;
    };
  }

  Future<void> refreshCurrentTab() async {
    if (!canRefreshCurrentTab) return;
    final key = _currentRefreshKey;
    if (!_refreshingTabs.add(key)) return;
    _notify();
    try {
      await (_contentRefresher?.call() ?? _refreshCurrentContent());
    } catch (error, stackTrace) {
      _reportOperationalError(error, stackTrace, 'tab.refresh');
    } finally {
      _refreshingTabs.remove(key);
      _notify();
    }
  }

  Future<void> _refreshCurrentContent() async {
    final instance = currentInstance;
    final route = currentContent;
    if (instance == null || route == null) return;
    if (route.topicId case final topicId?) {
      await Future.wait([
        loadTopic(topicId, route.slug ?? '', force: true),
        if (topicListContent case final source?)
          loadFeed(source.id, force: true),
      ]);
      return;
    }
    if (route.isBadges) {
      await badges.load(
        instance,
        route.badgeRoute ?? const BadgeRoute.directory(),
        refresh: true,
      );
      return;
    }
    final hydrator = _pluginSession
        .capabilities<PluginRouteHydrator>()
        .where((candidate) => candidate.handlesPluginRoute(route.id))
        .firstOrNull;
    if (hydrator != null) {
      await hydrator.hydratePluginRoute(instance.url, route.id, force: true);
      return;
    }
    switch (route.id) {
      case 'all-categories':
        await loadCategories(instance.url, force: true);
      case 'all-tags':
        await loadTags(instance.url, force: true);
      case 'users':
        await userDirectory.load(instance, refresh: true);
      case 'drafts':
        await draftList.load(instance, refresh: true);
      case 'summary':
        await userSummary.load(instance, refresh: true);
      case 'activity':
        await accountActivity.loadUserActivity(instance, refresh: true);
      case 'user-bookmarks':
        await accountActivity.loadBookmarkList(instance, refresh: true);
      case 'preferences':
        await preferences.load(instance, refresh: true);
      default:
        await loadFeed(route.id, force: true);
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

  String _nextTabId() {
    final held = <String>{
      for (final workspace in _forumWorkspaces.values)
        for (final tab in workspace.tabs) tab.id,
    };
    late String id;
    do {
      _tabSequence++;
      id =
          'tab-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${_tabSequence.toRadixString(36)}';
    } while (held.contains(id));
    return id;
  }

  final Set<String> _pendingHomepageTabs = {};

  ContentRoute _homepageFor(DiscourseInstance instance) =>
      ContentRoute.homepage(
        siteConfigFor(instance.url),
        connected: instance.isConnected,
      );

  ForumTab _newDefaultTab() {
    final id = _nextTabId();
    return ForumTab(
      id: id,
      rootDestinationId: 'new-tab',
      contentStack: [ContentRoute.newTab()],
    );
  }

  ForumWorkspace _newWorkspace(DiscourseInstance instance) {
    final id = _nextTabId();
    final tab = ForumTab(
      id: id,
      rootDestinationId: instance.defaultDestination.id,
      contentStack: [_homepageFor(instance)],
    );
    _pendingHomepageTabs.add(id);
    return ForumWorkspace(
      siteUrl: instance.url,
      accountIdentity: _workspaceAccountIdentity(instance),
      tabs: [tab],
      activeTabId: tab.id,
    );
  }

  ForumWorkspace _normalizeWorkspace(ForumWorkspace workspace) {
    if (!forumTabsEnabled && workspace.tabs.length > 1) {
      return workspace.copyWith(tabs: [workspace.activeTab]);
    }
    if (forumTabsEnabled) {
      final limit = desktopPanelsEnabled
          ? ForumWorkspace.maximumWorkspaceTabs
          : ForumWorkspace.maximumTabs;
      for (final panel in ForumPanel.values) {
        if (panel == ForumPanel.secondary && !desktopPanelsEnabled) continue;
        if (workspace.tabsIn(panel).isEmpty && workspace.tabs.length < limit) {
          final tab = _newDefaultTab().copyWith(panel: panel);
          workspace = workspace.copyWith(tabs: [...workspace.tabs, tab]);
        }
      }
    }
    return workspace;
  }

  ForumWorkspace _ensureWorkspace(
    DiscourseInstance instance, {
    bool persist = true,
  }) {
    final existing = _forumWorkspaces[instance.url];
    if (existing != null &&
        existing.accountIdentity == _workspaceAccountIdentity(instance)) {
      return existing;
    }
    _forgetPluginPaneTabs(instance.url);
    final workspace = _normalizeWorkspace(_newWorkspace(instance));
    _forumWorkspaces[instance.url] = workspace;
    if (persist) _persistWorkspaces();
    return workspace;
  }

  void _putWorkspace(ForumWorkspace workspace, {bool persist = true}) {
    final normalized = _normalizeWorkspace(workspace);
    _forumWorkspaces[normalized.siteUrl] = normalized;
    final liveTabIds = {for (final tab in normalized.tabs) tab.id};
    _postWindowCaches.removeWhere(
      (key, _) => key.$1 == normalized.siteUrl && !liveTabIds.contains(key.$2),
    );
    _postWindowCacheKeys.removeWhere(
      (key, _) => key.$1 == normalized.siteUrl && !liveTabIds.contains(key.$2),
    );
    _mainPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _pluginPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _activePluginPanes.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _coldPluginPanes.removeWhere(
      (key) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    if (persist) _persistWorkspaces();
  }

  void _removeWorkspace(String siteUrl, {bool persist = true}) {
    _forgetPluginPaneTabs(siteUrl);
    final removed = _forumWorkspaces.remove(siteUrl);
    if (removed == null) return;
    // A homepage still waiting for its config can no longer hydrate a tab
    // that has left the workspace map.
    for (final tab in removed.tabs) {
      _pendingHomepageTabs.remove(tab.id);
    }
    if (persist) _persistWorkspaces();
  }

  void _forgetPluginPaneTabs(String siteUrl) {
    _mainPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _pluginPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _activePluginPanes.removeWhere((key, _) => key.siteUrl == siteUrl);
    _coldPluginPanes.removeWhere((key) => key.siteUrl == siteUrl);
  }

  void _persistWorkspaces() {
    _tabSelectionPersistencePending = false;
    // Any full write already carries the in-memory anchors, so a waiting
    // anchor window has nothing left to add.
    _anchorPersistencePending = false;
    // The store reports its own failures; this only records when it is done.
    _workspacesSaved = forumTabs
        .save(_forumWorkspaces.values, selectedSiteUrl: currentInstance?.url)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _schedulePersistAnchors() {
    _anchorPersistencePending = true;
    if (_anchorPersistTimer != null) return;
    _anchorPersistTimer = Timer(anchorPersistDebounce, () {
      _anchorPersistTimer = null;
      if (isDisposed || !_anchorPersistencePending) return;
      _persistWorkspaces();
    });
  }

  void _flushPendingAnchorPersist() {
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    if (_anchorPersistencePending) _persistWorkspaces();
  }

  void flushAnchorPersist() {
    if (isDisposed) return;
    _flushPendingAnchorPersist();
  }

  void _replaceTab(
    String siteUrl,
    ForumTab replacement, {
    bool persist = true,
  }) {
    final workspace = _forumWorkspaces[siteUrl];
    if (workspace == null || workspace.tabById(replacement.id) == null) return;
    _putWorkspace(
      workspace.copyWith(
        tabs: [
          for (final tab in workspace.tabs)
            if (tab.id == replacement.id) replacement else tab,
        ],
      ),
      persist: persist,
    );
  }

  void _replaceActiveTab(ForumTab replacement, {bool persist = true}) {
    _pendingHomepageTabs.remove(replacement.id);
    final siteUrl = currentInstance?.url;
    if (siteUrl != null) {
      _replaceTab(siteUrl, replacement, persist: persist);
    }
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
    if (isDisposed) return;
    _instances
      ..clear()
      ..addAll(stored);
    for (final instance in stored) {
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
    _forumWorkspaces.clear();
    var workspacesNormalized = false;
    for (final workspace in workspaces) {
      final normalized = _normalizeWorkspace(workspace);
      workspacesNormalized =
          workspacesNormalized || !identical(normalized, workspace);
      final instance = _instanceAt(workspace.siteUrl);
      if (instance != null &&
          workspace.accountIdentity == _workspaceAccountIdentity(instance)) {
        _forumWorkspaces[workspace.siteUrl] = normalized;
      }
    }
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
    for (final workspace in _forumWorkspaces.values) {
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
    if (workspacesNormalized) _persistWorkspaces();
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
        [..._coreSitePreferenceKeys, ...plugins.registry.sitePreferenceKeys],
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
          emojiPickerStore.forgetSites(sites);
          forumSettings.forgetSites(sites);
          sidebarSections.forgetSites(sites);
          topicSidebar.forgetSites(sites);
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
        !_topicTrackingSnapshotsLoaded.contains(instance.url)) {
      return SidebarBadge.none;
    }
    final showCount = user.sidebarShowCountOfNewItems;
    final unifiedNew = user.unifiedNewEnabled;

    if (_destinationNumericId(destinationId, 'category-') case final id?) {
      return tracking.categoryBadge(
        categoryId: id,
        categories: _categoriesBySite[instance.url] ?? const [],
        unifiedNew: unifiedNew,
        showCount: showCount,
      );
    }
    if (_destinationNumericId(destinationId, 'tag-') case final id?) {
      final tags = <SidebarTag>[
        ...user.sidebarTags,
        ...?_siteTopTagsBySite[instance.url],
        ...?_anonymousDefaultTagsBySite[instance.url],
      ];
      if (tags.any((tag) => tag.id == id && tag.pmOnly)) {
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
      _topicTrackingRevisions[siteUrl] ?? 0;

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
      info = await api.siteLookup.basicInfo(siteUrl);
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final apiKey = credential.value;
      if (apiKey == null) {
        await _expireMissingAccount(instance.url, lease);
        return;
      }
      await _sessionUser(instance.url, apiKey, lease: lease, force: force);
      if (!lease.isCurrent || currentInstance?.url != instance.url) return;
      await _refreshCustomSidebarSections(instance.url, apiKey, lease: lease);
    } catch (_) {
      // Freshness-sensitive plugin capabilities remain unknown. Persisted
      // extension state must not authorize them in their place. A key that
      // could not be read is not a missing key, so the account stays.
    }
  }

  final Map<String, List<SidebarSection>> _customSidebarSections = {};
  final Set<String> _customSidebarSectionsLoaded = {};
  final Map<String, Future<void>> _customSidebarSectionRequests = {};
  final Map<String, DateTime> _customSidebarSectionAttemptedAt = {};

  /// Advanced when Core announces a section change, so a load that was
  /// already in flight cannot commit the sections from before it.
  final Map<String, int> _customSidebarSectionVersions = {};
  final Map<
    String,
    ({
      DiscourseInstance instance,
      List<SidebarSection> custom,
      List<SidebarSection> sections,
    })
  >
  _sidebarSectionsCache = {};

  static const _customSidebarRetryInterval = Duration(minutes: 5);

  List<SidebarSection> customSidebarSectionsFor(String siteUrl) =>
      _customSidebarSections[siteUrl] ?? const [];

  final _sidebarReorders = <(String, int)>{};

  bool canReorderSidebarLinks(String siteUrl, SidebarSection section) =>
      canEditSidebarLinks(siteUrl, section) && section.destinations.length > 1;

  bool canEditSidebarLinks(String siteUrl, SidebarSection section) {
    final instance = _instanceAt(siteUrl);
    return !isDisposed &&
        instance?.isConnected == true &&
        section.remoteId != null &&
        (!section.public || instance?.user?.admin == true);
  }

  /// [newIndex] is an insertion gap in the original list, as in Flutter's
  /// reorder callback and Core's sidebar drop handling.
  Future<void> reorderSidebarLinks({
    required String siteUrl,
    required SidebarSection section,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (!canReorderSidebarLinks(siteUrl, section) ||
        !customSidebarSectionsFor(siteUrl).contains(section) ||
        oldIndex < 0 ||
        oldIndex >= section.destinations.length ||
        newIndex < 0 ||
        newIndex > section.destinations.length ||
        newIndex == oldIndex ||
        newIndex == oldIndex + 1) {
      return;
    }
    final operation = (siteUrl, section.remoteId!);
    if (!_sidebarReorders.add(operation)) return;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      if (credential.value == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !canReorderSidebarLinks(siteUrl, section)) return;
      final ids = section.destinations.map((link) => link.linkId!).toList();
      final moved = ids.removeAt(oldIndex);
      ids.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
      final updated = await api.site.reorderSidebarLinks(
        siteUrl: siteUrl,
        apiKey: credential.value!,
        clientId: identity.value,
        sectionId: section.remoteId!,
        linksOrder: ids,
      );
      if (isDisposed) return;
      lease.commit(() {
        _customSidebarSections[siteUrl] = [
          for (final existing in customSidebarSectionsFor(siteUrl))
            existing.remoteId == section.remoteId ? updated : existing,
        ];
        _notify();
      });
    } finally {
      _sidebarReorders.remove(operation);
    }
  }

  bool canMoveSidebarLink({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) =>
      source != target &&
      canEditSidebarLinks(siteUrl, source) &&
      canEditSidebarLinks(siteUrl, target) &&
      customSidebarSectionsFor(siteUrl).contains(source) &&
      customSidebarSectionsFor(siteUrl).contains(target) &&
      oldIndex >= 0 &&
      oldIndex < source.destinations.length &&
      newIndex >= 0 &&
      newIndex <= target.destinations.length &&
      target.destinations.length < SidebarSection.maximumCustomLinks;

  Future<void> moveSidebarLink({
    required String siteUrl,
    required SidebarSection source,
    required SidebarSection target,
    required int oldIndex,
    required int newIndex,
  }) async {
    bool allowed() => canMoveSidebarLink(
      siteUrl: siteUrl,
      source: source,
      target: target,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    if (!allowed()) return;
    final operations = {
      (siteUrl, source.remoteId!),
      (siteUrl, target.remoteId!),
    };
    if (operations.any(_sidebarReorders.contains)) return;
    _sidebarReorders.addAll(operations);
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      if (credential.value == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !allowed()) return;
      final updated = await api.site.moveSidebarLink(
        siteUrl: siteUrl,
        apiKey: credential.value!,
        clientId: identity.value,
        sourceSectionId: source.remoteId!,
        targetSectionId: target.remoteId!,
        linkId: source.destinations[oldIndex].linkId!,
        position: newIndex,
      );
      if (isDisposed) return;
      lease.commit(() {
        _customSidebarSections[siteUrl] = [
          for (final existing in customSidebarSectionsFor(siteUrl))
            updated
                    .where((section) => section.remoteId == existing.remoteId)
                    .firstOrNull ??
                existing,
        ];
        _notify();
      });
    } finally {
      _sidebarReorders.removeAll(operations);
    }
  }

  List<SidebarSection> sidebarSectionsFor(DiscourseInstance instance) {
    final custom = customSidebarSectionsFor(instance.url);
    final cached = _sidebarSectionsCache[instance.url];
    if (cached != null &&
        identical(cached.instance, instance) &&
        identical(cached.custom, custom)) {
      return cached.sections;
    }
    final sections = instance.sectionsWithCustomSections(custom);
    _sidebarSectionsCache[instance.url] = (
      instance: instance,
      custom: custom,
      sections: sections,
    );
    return sections;
  }

  Future<void> _refreshCustomSidebarSections(
    String siteUrl,
    String? apiKey, {
    SiteLease? lease,
  }) {
    // Custom sections belong only to the site on screen. A session lookup can
    // finish after the reader has switched away, and must not turn that stale
    // completion into another inactive-site request.
    if (isDisposed || currentInstance?.url != siteUrl) return Future.value();
    if (_customSidebarSectionsLoaded.contains(siteUrl)) return Future.value();

    final active = _customSidebarSectionRequests[siteUrl];
    if (active != null) return active;
    final attemptedAt = _customSidebarSectionAttemptedAt[siteUrl];
    if (attemptedAt != null &&
        DateTime.now().difference(attemptedAt) < _customSidebarRetryInterval) {
      return Future.value();
    }

    late final Future<void> request;
    request = _loadCustomSidebarSections(siteUrl, apiKey, lease: lease)
        .whenComplete(() {
          if (identical(_customSidebarSectionRequests[siteUrl], request)) {
            final removed = _customSidebarSectionRequests.remove(siteUrl);
            assert(identical(removed, request));
          }
        });
    _customSidebarSectionRequests[siteUrl] = request;
    return request;
  }

  Future<void> _loadCustomSidebarSections(
    String siteUrl,
    String? apiKey, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(siteUrl);
    final version = _customSidebarSectionVersions[siteUrl] ?? 0;
    try {
      final identity = await _readClientIdFor(session, apiKey);
      if (identity == null ||
          !session.isCurrent ||
          currentInstance?.url != siteUrl) {
        return;
      }
      _customSidebarSectionAttemptedAt[siteUrl] = DateTime.now();
      final sections = await api.site.customSidebarSections(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: identity.value,
      );
      session.commit(() {
        if ((_customSidebarSectionVersions[siteUrl] ?? 0) != version) return;
        _customSidebarSections[siteUrl] = sections;
        _customSidebarSectionsLoaded.add(siteUrl);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !session.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'sidebar.loadCustomSections',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  /// Core announces every public section create, edit, reorder, move and
  /// delete to signed-in readers, and the web client re-fetches on it. Edits
  /// to private sections announce nothing on either client.
  void _invalidateCustomSidebarSections(String siteUrl, SiteLease lease) {
    _customSidebarSectionsLoaded.remove(siteUrl);
    _customSidebarSectionAttemptedAt.remove(siteUrl);
    _customSidebarSectionRequests.remove(siteUrl)?.ignore();
    _customSidebarSectionVersions.update(
      siteUrl,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    // Another site's selection path reloads it once it is shown again.
    if (currentInstance?.url != siteUrl) return;
    unawaited(_reloadCustomSidebarSections(siteUrl, lease));
  }

  Future<void> _reloadCustomSidebarSections(
    String siteUrl,
    SiteLease lease,
  ) async {
    final _SessionValue<String?>? credential;
    try {
      credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'sidebar.loadCustomSections',
        severity: DiagnosticSeverity.warning,
      );
      return;
    }
    if (credential?.value case final apiKey?) {
      await _refreshCustomSidebarSections(siteUrl, apiKey, lease: lease);
    }
  }

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

  void _advanceGroupedUnreadNotificationVersion(String siteUrl) {
    _groupedUnreadNotificationVersions.update(
      siteUrl,
      (version) => version + 1,
      ifAbsent: () => 1,
    );
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

  int likeNotificationUnreadCount(String siteUrl) =>
      _groupedUnreadCountOf(siteUrl, plugins.registry.likeNotificationTypes);

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
    String apiKey,
  ) {
    final cached = _siteNotificationTypes[instance.url];
    if (cached != null) return Future.value(cached);
    final active = _siteNotificationTypeRequests[instance.url];
    if (active != null) return active;

    final lease = lifecycle.capture(instance.url);
    late final Future<List<NotificationWireType>> request;
    request = api.site
        .siteNotificationTypes(siteUrl: instance.url, apiKey: apiKey)
        .then((types) {
          final immutable = List<NotificationWireType>.unmodifiable(types);
          lease.commit(() => _siteNotificationTypes[instance.url] = immutable);
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

  final Set<String> _categorised = {};
  final Map<String, Future<void>> _categoryRequests = {};
  final Map<String, List<TopicCategory>> _categoriesBySite = {};
  final Map<String, TopicTrackingState> _topicTrackingBySite = {};
  final Map<String, TopicTrackingMessageFilter> _topicTrackingMessageFilters =
      {};
  final Set<String> _topicTrackingSnapshotsLoaded = {};
  final Map<String, int> _topicTrackingRevisions = {};
  final Set<String> _topicTrackingLoads = {};
  final Map<String, ({SiteLease lease, Future<void> Function() load})>
  _topicTrackingRetries = {};
  bool _liveChangeNotifyPending = false;
  final Map<String, List<Object?>> _topicTrackingPendingEvents = {};
  final Map<String, CategoryFeed> _categoryFeeds = {};
  final Map<(String, int), Future<List<TopicCategory>>> _categoryIdRequests =
      {};
  final Map<String, _CategorySidebarCache> _categorySidebarCache = {};
  final Map<String, List<SidebarTag>> _siteTopTagsBySite = {};
  final Map<String, List<SidebarTag>> _anonymousDefaultTagsBySite = {};
  final Map<String, _TagSidebarCache> _tagSidebarCache = {};
  final Map<String, _TopicListFilterTagsCache> _topicListFilterTagsCache = {};
  final Map<String, TagDirectoryFeed> _tagDirectoryFeeds = {};
  final Map<String, Object> _tagDirectoryRequests = {};
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

  String? get currentFeedId {
    final route = currentContent?.isTopic == true
        ? topicListContent ?? currentContent
        : currentContent;
    if (route?.isMessages == true) return route!.id;
    if (route != null &&
        (route.feedPath != null || TopicListMode.fromRoute(route) != null)) {
      return route.id;
    }
    return topicListTab?.rootDestinationId;
  }

  final _unreadTopicFeed = UnreadTopicFeed();

  bool get currentFeedIsUnread {
    // Core serves personal and group Unread folders through the same unread
    // filter as /unread, so a message read here leaves them the same way.
    final route = topicListContent ?? topicListTab?.currentContent;
    if (route?.isMessages == true) {
      return route!.messageListMode == MessageListMode.unread;
    }
    return switch (currentTopicListMode) {
      TopicListMode.unread || TopicListMode.newReplies => true,
      _ => false,
    };
  }

  TopicFeed? get currentFeed {
    final instance = currentInstance;
    final feedId = currentFeedId;
    if (instance == null || feedId == null) return null;
    final feed = topicFeeds.feedFor(instance.url, feedId);
    if (feed == null || !currentFeedIsUnread) return feed;
    // The topic being read may sit in the other desktop panel.
    return _unreadTopicFeed.project(
      feed,
      selectedTopicId: readingTopicId,
      isRead: (id) => UnreadTopicFeed.isRead(
        topic: store.read<Topic>(instance.url, id),
        tracking: _topicTrackingBySite[instance.url]?.topic(id),
        localReadPostNumber: _topicReads.lastReadPostNumberFor(
          instance.url,
          id,
        ),
      ),
    );
  }

  TopicListMode? get currentTopicListMode {
    final tab = topicListTab;
    if (tab == null) return null;

    final route = topicListContent ?? tab.currentContent;
    final mode = TopicListMode.fromRoute(route);
    if (mode != null) return mode;
    if (tab.rootDestinationId != 'latest' &&
        route.categoryId == null &&
        route.tagName == null) {
      return null;
    }
    return route.isTopicListFilter ? TopicListMode.latest : null;
  }

  /// The current document owns its source list even when another panel shows
  /// a different feed.
  ForumTab? get topicListTab => activeTab;

  ContentRoute? get topicListContent {
    final routes = topicListTab?.contentStack ?? const <ContentRoute>[];
    for (final route in routes.reversed) {
      if (route.isTopic) continue;
      return route.isTopicList ? route : null;
    }
    return null;
  }

  void closeTopicListReader() {
    if (mobileNavigationEnabled) {
      if (currentContent?.isTopic == true) handleBack();
      return;
    }
    final active = activeTab;
    if (active != null && _readerClosesTab(active)) {
      closeTab(active.id);
      return;
    }
    if (active == null ||
        topicListContent == null ||
        !active.currentContent.isTopic) {
      return;
    }
    _replaceActiveTab(_closeTopicRoute(active));
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance?) _hydrateActiveTab(instance);
  }

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
    _replaceActiveTab(_closeTopicRoute(active));
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
        other.currentContent.id == source.id;
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
  ({int all, int topics, int replies}) get topicListNewCounts {
    final route = topicListContent ?? currentContent;
    final categoryId = route?.categoryId;
    final tagNames = route?.tagNames ?? const <String>[];
    if (categoryId == null && tagNames.isEmpty) return _forumNewCounts;

    final instance = currentInstance;
    if (instance == null ||
        instance.user == null ||
        !_topicTrackingSnapshotsLoaded.contains(instance.url)) {
      return (all: 0, topics: 0, replies: 0);
    }
    final tracking = _topicTrackingBySite[instance.url];
    if (tracking == null) return (all: 0, topics: 0, replies: 0);

    final tagIds = <int>{};
    for (final name in tagNames) {
      final normalized = name.toLowerCase();
      final tag = _knownTagsFor(instance.url)
          .where(
            (tag) =>
                tag.name.toLowerCase() == normalized ||
                tag.slug.toLowerCase() == normalized,
          )
          .firstOrNull;
      // An unresolved tag cannot use the unfiltered forum total.
      if (tag == null || tag.pmOnly) return (all: 0, topics: 0, replies: 0);
      tagIds.add(tag.id);
    }

    final counts = tracking.newActivityCountsFor(
      categoryId: categoryId,
      categories: filterCategoriesFor(instance.url),
      tagIds: tagIds,
    );
    return (
      all:
          counts.newTopics +
          (instance.user!.unifiedNewEnabled ? counts.newReplies : 0),
      topics: counts.newTopics,
      replies: counts.newReplies,
    );
  }

  ({int all, int topics, int replies}) get _forumNewCounts {
    final instance = currentInstance;
    final totals = currentTotals;
    if (instance?.user?.unifiedNewEnabled == true) {
      final tracking = _topicTrackingBySite[instance!.url];
      if (tracking == null ||
          !_topicTrackingSnapshotsLoaded.contains(instance.url)) {
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

  bool get canCreateTopicHere {
    if (currentContent?.isTopic != false ||
        currentContent?.isPreferences == true ||
        currentContent?.isAppearance == true ||
        currentContent?.isMessages == true) {
      return false;
    }
    final instance = currentInstance;
    if (currentContent?.id == 'all-categories' && instance != null) {
      return categoryFeedFor(instance.url).canCreateTopic;
    }
    return currentFeed?.canCreateTopic ?? false;
  }

  bool get canCreateTopicFromList =>
      topicListContent != null && currentFeed?.canCreateTopic == true;

  bool get canCreateTopicFromSidebar =>
      currentInstance?.user?.canCreateTopic == true;

  CategoryFeed categoryFeedFor(String siteUrl) =>
      _categoryFeeds[siteUrl] ?? const CategoryFeed();

  /// Per-category unread topic counts from the loaded account snapshot.
  /// Null means tracking is not ready; sparse live arrivals are not a total.
  Map<int, int>? categoryUnreadTopicCountsFor(String siteUrl) {
    if (currentUserFor(siteUrl) == null ||
        !_topicTrackingSnapshotsLoaded.contains(siteUrl)) {
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
      _categoriesBySite[siteUrl] ?? const [];

  bool sidebarNavigationLoadingFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      return false;
    }
    final feed = categoryFeedFor(siteUrl);
    return !feed.loaded && feed.error == null;
  }

  SidebarSection? categorySidebarSectionFor(String siteUrl) {
    if (!_categoriesBySite.containsKey(siteUrl)) return null;
    final categories = _categoriesBySite[siteUrl]!;
    final user = _instanceAt(siteUrl)?.user;
    final config = siteConfigFor(siteUrl);
    final held = _categorySidebarCache[siteUrl];
    if (held != null &&
        identical(held.categories, categories) &&
        identical(held.user, user) &&
        held.config == config) {
      return held.section;
    }

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: user != null,
      preferredCategoryIds: user?.sidebarCategoryIds ?? const [],
      defaultCategoryIds: config.defaultNavigationMenuCategoryIds,
      fixedCategoryPositions: config.fixedCategoryPositions,
      allowUncategorizedTopics: config.allowUncategorizedTopics,
    );
    _categorySidebarCache[siteUrl] = (
      categories: categories,
      user: user,
      config: config,
      section: section,
    );
    return section;
  }

  SidebarSection? tagSidebarSectionFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    if (instance == null || !siteConfigFor(siteUrl).taggingEnabled) return null;

    final user = instance.user;
    final siteTop = _siteTopTagsBySite[siteUrl] ?? const <SidebarTag>[];
    final anonymousDefaults =
        _anonymousDefaultTagsBySite[siteUrl] ?? const <SidebarTag>[];
    final tags = user == null
        ? (anonymousDefaults.isNotEmpty ? anonymousDefaults : siteTop)
        : (user.sidebarTags.isNotEmpty ? user.sidebarTags : siteTop);
    final display = user == null ? tags.isNotEmpty : user.displaySidebarTags;

    final held = _tagSidebarCache[siteUrl];
    if (held != null &&
        identical(held.tags, tags) &&
        held.display == display &&
        held.username == user?.username) {
      return held.section;
    }

    final section = buildTagSidebarSection(
      tags: tags,
      display: display,
      username: user?.username,
    );
    if (section == null) {
      _tagSidebarCache.remove(siteUrl);
      return null;
    }
    _tagSidebarCache[siteUrl] = (
      tags: tags,
      display: display,
      username: user?.username,
      section: section,
    );
    return section;
  }

  TagDirectoryFeed tagDirectoryFeedFor(String siteUrl) =>
      _tagDirectoryFeeds[siteUrl] ?? const TagDirectoryFeed();

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
    final parent = categoryFor(category.parentCategoryId, siteUrl: siteUrl);
    return category_path.topicCategoryPathLabel(category, parent: parent);
  }

  Ref<Topic> topicRef(String siteUrl, int topicId) =>
      store.ref<Topic>(siteUrl, topicId);

  Ref<TopicCategory> categoryRef(String siteUrl, int categoryId) =>
      store.ref<TopicCategory>(siteUrl, categoryId);

  Ref<Post> postRef(String siteUrl, int postId) =>
      store.ref<Post>(siteUrl, postId);

  String? _feedPath(String feedId, DiscourseInstance instance) {
    // A split list can navigate independently while the reader stays active.
    // Resolve its current route before consulting the reader's older stack.
    final routes = [?topicListContent, ...contentStack.reversed];
    for (final route in routes) {
      if (route.id != feedId) continue;
      if (route.isMessages) {
        final username = instance.user?.username;
        if (username == null) return null;
        return route.messageListMode.feedPathFor(
          username,
          groupName: route.messageGroupName,
        );
      }
      if (route.isAdvancedTopicFilter) return route.topicFilterRequestPath;
      if (route.feedPath != null) return route.feedPath;
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

  void selectMessageInbox(String? groupName, {bool keepTopicOpen = false}) {
    final instance = currentInstance;
    final route = topicListContent ?? currentContent;
    final user = instance?.user;
    if (instance == null || user == null || route?.isMessages != true) return;

    final group = groupName?.trim();
    if (group != null && !user.messageGroupNames.contains(group)) return;

    final mode = route!.messageListMode;
    final replacement = ContentRoute.messages(
      groupName: group,
      mode: group == null || mode.supportsGroup ? mode : MessageListMode.inbox,
    );
    if (route.id == replacement.id) return;
    _replaceTopicListContent(replacement, keepTopicOpen: keepTopicOpen);
    _syncTopicChannels();
    _notify();
    unawaited(loadFeed(replacement.id));
  }

  void selectMessageListMode(
    MessageListMode mode, {
    bool keepTopicOpen = false,
  }) {
    final route = topicListContent ?? currentContent;
    if (currentInstance?.user == null || route?.isMessages != true) return;
    final group = route!.messageGroupName;
    if (group != null && !mode.supportsGroup) return;
    final replacement = ContentRoute.messages(groupName: group, mode: mode);
    if (route.id == replacement.id) return;
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

  bool get canDismissNewTopics => _dismissNewScope != null;

  // reset-new looks `tag_name` up case-sensitively and, finding nothing,
  // drops the tag: the dismissal widens to every new topic in the category,
  // or on the whole forum. The list matched its tags case-insensitively, so
  // the only safe name is the exact one its own topics carry, and a list none
  // of whose topics carries it offers no dismissal.
  ({String? tagName})? get _dismissNewScope {
    final instance = currentInstance;
    final mode = currentTopicListMode;
    final feed = currentFeed;
    if (instance == null ||
        !instance.isConnected ||
        (mode != TopicListMode.newActivity &&
            mode != TopicListMode.newTopics &&
            mode != TopicListMode.newReplies) ||
        feed == null ||
        feed.topicIds.isEmpty) {
      return null;
    }
    final requested = topicListContent?.tagNames.firstOrNull?.toLowerCase();
    if (requested == null) return (tagName: null);
    for (final id in feed.topicIds) {
      final topic = store.read<Topic>(instance.url, id);
      for (final tag in topic?.tags ?? const <TopicTag>[]) {
        if (tag.name.toLowerCase() == requested) return (tagName: tag.name);
      }
    }
    return null;
  }

  Future<String?> dismissNewTopics() async {
    final instance = currentInstance;
    final route = topicListContent;
    final mode = currentTopicListMode;
    final scope = _dismissNewScope;
    if (instance == null ||
        route == null ||
        mode == null ||
        scope == null ||
        dismissingNewTopics) {
      return null;
    }
    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    final key = (siteUrl, lease.session);
    _dismissingNew.add(key);
    _notify();
    final topics = mode != TopicListMode.newReplies;
    final posts =
        instance.user?.unifiedNewEnabled == true &&
        mode != TopicListMode.newTopics;
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      final identity = await _readClientIdFor(lease, credential?.value);
      if (credential?.value == null || identity == null || !lease.isCurrent) {
        return appL10n.reconnectToDismissNewTopics;
      }
      // Core accepts one tag. Resolve the full intersection before a bulk
      // write when this app's list has multiple tags.
      List<int>? topicIds;
      if (route.tagNames.length > 1) {
        topicIds = [];
        String? path = route.feedPath;
        final visited = <String>{};
        while (path != null && visited.add(path)) {
          final page = await api.topicFeeds.topicList(
            siteUrl: siteUrl,
            path: path,
            apiKey: credential!.value,
            clientId: identity.value,
          );
          if (!lease.isCurrent || isDisposed) return null;
          topicIds.addAll(page.topics.map((topic) => topic.id));
          path = page.nextPagePath;
        }
        if (path != null) {
          throw StateError('Could not load all matching topics.');
        }
      }
      if (!lease.isCurrent || isDisposed) return null;
      final ids = await api.topicFeeds.dismissNewTopics(
        siteUrl: siteUrl,
        apiKey: credential!.value!,
        clientId: identity.value,
        dismissTopics: topics,
        dismissPosts: posts,
        categoryId: route.categoryId,
        tagName: scope.tagName,
        topicIds: topicIds,
      );
      if (!lease.isCurrent || isDisposed) return null;
      for (final type in [
        if (topics) 'dismiss_new',
        if (posts) 'dismiss_new_posts',
      ]) {
        _applyTopicTrackingMessage(siteUrl, {
          'message_type': type,
          'payload': {'topic_ids': ids},
        });
      }
      await topicFeeds.load(
        instance: instance,
        destinationId: route.id,
        path: route.feedPath!,
        incoming: _trackers[siteUrl]?.incoming,
        force: true,
      );
      return null;
    } catch (error, stackTrace) {
      if (!lease.isCurrent || isDisposed) return null;
      _reportOperationalError(error, stackTrace, 'topics.dismissNew');
      return appL10n.couldNotDismissNewTopicsPleaseTryAgain;
    } finally {
      _dismissingNew.remove(key);
      if (!isDisposed) _notify();
    }
  }

  Future<void> loadFeed(String destinationId, {bool force = false}) async {
    final instance = currentInstance;
    if (instance == null) return;

    // Lookup has already established that an anonymous request cannot read
    // this forum. The shell shows its sign-in action until connecting gives
    // this request a user API key.
    if (instance.loginRequired && !instance.isConnected) return;

    final path = _feedPath(destinationId, instance);
    if (path == null) return;
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
      _categoriesBySite[siteUrl] ?? const [];

  List<SidebarTag> topicListFilterTagsFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    if (instance == null) return const [];
    final user = instance.user;
    final sources = (
      account: (user?.id, user?.username),
      personal: user?.sidebarTags ?? const <SidebarTag>[],
      siteTop: _siteTopTagsBySite[siteUrl] ?? const <SidebarTag>[],
      anonymousDefaults:
          _anonymousDefaultTagsBySite[siteUrl] ?? const <SidebarTag>[],
      directory: tagDirectoryFeedFor(siteUrl).tags,
    );
    final held = _topicListFilterTagsCache[siteUrl];
    // Taxonomy sources are replaced when loaded. Record equality checks their
    // list identities, so shell selectors do not scan the directory on every
    // unrelated notification (including current-user counter updates).
    if (held != null && held.sources == sources) return held.tags;

    final byName = <String, SidebarTag>{};
    for (final tag in _knownTagsFor(siteUrl)) {
      if (tag.pmOnly) continue;
      byName.putIfAbsent(tag.name.toLowerCase(), () => tag);
    }
    final tags = List<SidebarTag>.unmodifiable(byName.values);
    final snapshot =
        held != null &&
            held.sources.account == sources.account &&
            listEquals(held.tags, tags)
        ? held.tags
        : tags;
    _topicListFilterTagsCache[siteUrl] = (sources: sources, tags: snapshot);
    return snapshot;
  }

  Future<List<TopicCategory>> searchFilterCategories({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.categories',
    (apiKey, clientId) => apiKey == null
        ? Future.value(const [])
        : api.categories.searchCategories(
            siteUrl: siteUrl,
            term: term,
            apiKey: apiKey,
            includeAncestors: true,
            clientId: clientId,
          ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.tags',
    (apiKey, clientId) => api.lookups.searchFilterTags(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      clientId: clientId,
    ),
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) return const [];
      final found = await lookup(credential.value, identity.value);
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
    _replaceTab(
      instance.url,
      tab.copyWith(
        anchors: {
          ...tab.anchors,
          destinationId: ForumTabAnchor(kind: 'feed', itemId: row),
        },
      ),
      persist: false,
    );
    _schedulePersistAnchors();
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
    _replaceTab(
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
    _schedulePersistAnchors();
  }

  final Map<String, SiteTracker> _trackers = {};
  final Set<String> _trackersStarting = {};
  final Map<String, Future<void>> _trackerStartRequests = {};
  // Each captured lease identifies both one write and its account lifetime.
  final Map<String, SiteLease> _userStatusWrites = {};
  final Map<String, bool> _optimisticHidePresence = {};
  final Map<String, Object> _hidePresenceWrites = {};
  final Map<String, String> _hidePresenceErrors = {};
  final Map<String, int> _hidePresenceVersions = {};
  final Map<String, int> _groupedUnreadNotificationVersions = {};
  final Map<String, int> _draftCountVersions = {};
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
      _topicTrackingMessageFilters
          .putIfAbsent(siteUrl, () => TopicTrackingMessageFilter(clock: _clock))
          .admitsIncoming(data, user: _instanceAt(siteUrl)?.user);

  /// What a loaded list announces, read the way core's `trackIncoming` reads
  /// the list `findTopicList` found: Latest, New and Unseen by name, a
  /// category or tag link as its default list, the category from the path
  /// and the tags as the server resolved them.
  IncomingTopicsFilter? _incomingTopicsFilter(String path, TopicList list) {
    final scope = ContentRoute(
      id: 'topic-list-filter-$path',
      title: '',
      icon: DIcons.list,
      feedPath: path,
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
              _refetchTopic(siteUrl, topicId, routes[topicId]?.slug ?? ''),
            );
          }
          final stale = plugins.registry.stalePosts(channel, data);
          if (stale.isNotEmpty) _refreshPosts(siteUrl, topicId, stale);
          if (core.post case final id?) {
            _refreshPosts(siteUrl, topicId, {id}, deletion: core.deletion);
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

  /// The newest `posts_count` a core `stats` message carried while a
  /// deletion's re-read of the topic was out, by [_topicKey]. Core publishes
  /// that count right after the deletion, and a re-read that then omits the
  /// post lowers the held count for it again, so the count waits for the
  /// re-read to decide.
  final Map<String, int> _deferredTopicPostsCounts = {};

  /// `Topic.publish_stats_to_clients!`: the topic's totals after a like, a new
  /// post, a deletion or a recovery. As on the web client, each total the
  /// message carries replaces the held one; nothing is read again for it. Its
  /// last-post fields have no held counterpart: a row's activity time is
  /// `bumped_at`, which this message does not carry.
  void _applyTopicStatsMessage(
    String siteUrl,
    int topicId,
    Object? data,
    SiteLease lease,
  ) {
    if (!lease.isCurrent || isDisposed) return;
    if (data is! Map || data['type'] != 'stats') return;
    int? total(Object? value) => value is int && value >= 0 ? value : null;
    final likeCount = total(data['like_count']);
    var postsCount = total(data['posts_count']);
    if (postsCount != null && _awaitsTopicDeletionRead(siteUrl, topicId)) {
      _deferredTopicPostsCounts[_topicKey(siteUrl, topicId)] = postsCount;
      postsCount = null;
    }
    _setTopicTotals(
      siteUrl,
      topicId,
      likeCount: likeCount,
      postsCount: postsCount,
    );
  }

  bool _awaitsTopicDeletionRead(String siteUrl, int topicId) =>
      _postRefreshDeletions.any(
        (key) =>
            key.startsWith('$siteUrl~') && _postRefreshTopics[key] == topicId,
      );

  void _releaseDeferredTopicPostsCount(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    if (!_deferredTopicPostsCounts.containsKey(key) ||
        _awaitsTopicDeletionRead(siteUrl, topicId)) {
      return;
    }
    _setTopicTotals(
      siteUrl,
      topicId,
      postsCount: _deferredTopicPostsCounts.remove(key),
    );
  }

  void _setTopicTotals(
    String siteUrl,
    int topicId, {
    int? likeCount,
    int? postsCount,
  }) {
    if (likeCount == null && postsCount == null) return;
    bool holds(int held, int? next) => next == null || next == held;
    var changed = false;
    store.update<TopicDetail>(siteUrl, topicId, (topic) {
      if (holds(topic.likeCount, likeCount) &&
          holds(topic.postsCount, postsCount)) {
        return topic;
      }
      changed = true;
      return topic.copyWith(likeCount: likeCount, postsCount: postsCount);
    });
    // A list row listens to its own ref, so only the topic needs the shell.
    store.update<Topic>(
      siteUrl,
      topicId,
      (row) =>
          holds(row.likeCount, likeCount) && holds(row.postsCount, postsCount)
          ? row
          : row.copyWith(likeCount: likeCount, postsCount: postsCount),
    );
    if (changed && !isDisposed && currentInstance?.url == siteUrl) {
      _notifyLiveChange();
    }
  }

  /// Re-reads of held posts that have not left yet, by [_topicKey]. One poll
  /// answer can name many held posts, some several times: a backlog replayed
  /// on resume, or the likes of a busy thread. Each request counts against
  /// the site's per-minute user API budget, which the reader's own actions
  /// share, so the posts a run names leave together once it is delivered.
  final Map<String, _PostRefreshBatch> _queuedPostRefreshes = {};

  void _refreshPosts(
    String siteUrl,
    int topicId,
    Set<int> postIds, {
    bool deletion = false,
  }) {
    final eligible = <int>[];
    for (final id in postIds) {
      final key = _postKey(siteUrl, id);
      if (store.read<Post>(siteUrl, id) == null) {
        _postRefreshDeletions.remove(key);
        continue;
      }
      // Kept until a read of this post commits, since the read that answers
      // may be a replay after an earlier read or a write.
      if (deletion) _postRefreshDeletions.add(key);
      if (_postWritesInFlight.containsKey(key)) {
        // A poll/reaction echo received during a write is useful, but not yet:
        // the pre-write personalized post could land over the write response.
        // Remember it and re-read as soon as the post lease is released.
        _postRefreshPending.add(key);
        _postRefreshTopics[key] = topicId;
      } else {
        eligible.add(id);
      }
    }
    // A deleted post that a write's own re-read already took out holds no
    // count back.
    _releaseDeferredTopicPostsCount(siteUrl, topicId);
    final topicKey = _topicKey(siteUrl, topicId);
    for (final id in eligible) {
      final key = _postKey(siteUrl, id);
      final owner = _postRefreshRequests[key];
      if (owner == null) {
        final batch = _queuedPostRefreshes.putIfAbsent(topicKey, () {
          final batch = _PostRefreshBatch(
            siteUrl,
            topicId,
            lifecycle.capture(siteUrl),
          );
          scheduleMicrotask(() => _sendPostRefreshBatch(batch));
          return batch;
        });
        batch.postIds.add(id);
        _postRefreshRequests[key] = batch;
        // Keep the topic beside every active read as well as beside reads that
        // arrive during a write. If a write starts now, it invalidates this
        // pre-write response and needs enough context to replay it afterward.
        _postRefreshTopics[key] = topicId;
      } else if (!identical(owner, _queuedPostRefreshes[topicKey])) {
        // The read already out may have been answered before this change.
        _postRefreshPending.add(key);
      }
    }
  }

  /// Sends what [batch] still owns, as reads by id of at most
  /// [TopicDetail.maximumInitialPosts] posts, the page the web client reads
  /// a stream in.
  void _sendPostRefreshBatch(_PostRefreshBatch batch) {
    final topicKey = _topicKey(batch.siteUrl, batch.topicId);
    // A forgotten site took its queued reads with it.
    if (!identical(_queuedPostRefreshes[topicKey], batch)) return;
    _queuedPostRefreshes.remove(topicKey);
    if (isDisposed) return;
    final owned = [
      for (final id in batch.postIds)
        if (identical(_postRefreshRequests[_postKey(batch.siteUrl, id)], batch))
          id,
    ];
    const page = TopicDetail.maximumInitialPosts;
    for (var start = 0; start < owned.length; start += page) {
      final end = math.min(start + page, owned.length);
      unawaited(_readRefreshedPosts(batch, owned.sublist(start, end)));
    }
  }

  Future<void> _readRefreshedPosts(
    _PostRefreshBatch batch,
    List<int> wanted,
  ) async {
    final _PostRefreshBatch(:siteUrl, :topicId, :lease) = batch;

    bool requestOwns(int postId) =>
        identical(_postRefreshRequests[_postKey(siteUrl, postId)], batch);

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final posts = await api.topicContent.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: wanted,
        apiKey: credential.value,
      );
      lease.commit(() {
        bool current(int postId) =>
            requestOwns(postId) &&
            !_postRefreshPending.contains(_postKey(siteUrl, postId));
        final fresh = [
          for (final post in posts)
            if (current(post.id)) post,
        ];
        // After a deletion, a read by id that leaves the post out means this
        // reader can no longer see it, as the web client concludes when its
        // own read fails. A full topic refetch keeps an omitted id that ends
        // the stream, so nothing else would take the last post out. No other
        // live re-read's omission removes a post.
        final answered = {for (final post in posts) post.id};
        final gone = [
          for (final id in wanted)
            if (!answered.contains(id) &&
                current(id) &&
                _postRefreshDeletions.contains(_postKey(siteUrl, id)))
              id,
        ];
        if (fresh.isEmpty && gone.isEmpty) return;
        store.putAll(siteUrl, fresh);
        for (final id in gone) {
          _removeTopicPost(siteUrl, topicId, id);
        }
        _notify();
      });
    } catch (error, stackTrace) {
      final stillRelevant = wanted.any((id) {
        final key = _postKey(siteUrl, id);
        return requestOwns(id) && !_postRefreshPending.contains(key);
      });
      if (!isDisposed && lease.isCurrent && stillRelevant) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.refreshFromMessageBus',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      final retry = <int>{};
      lease.commit(() {
        for (final id in wanted) {
          final key = _postKey(siteUrl, id);
          if (requestOwns(id)) {
            _postRefreshRequests.remove(key);
            if (_postRefreshPending.remove(key)) {
              retry.add(id);
            } else {
              _postRefreshTopics.remove(key);
              _postRefreshDeletions.remove(key);
            }
          }
        }
        _releaseDeferredTopicPostsCount(siteUrl, topicId);
      });
      if (retry.isNotEmpty) _refreshPosts(siteUrl, topicId, retry);
    }
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
      _advanceGroupedUnreadNotificationVersion(siteUrl);
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
    try {
      // The persisted account state, not a credential that may have failed
      // to delete, decides whether this session may open private channels.
      apiKey = instance.isConnected
          ? await credentials.apiKeyFor(siteUrl)
          : null;
      // An anonymous bus sends no client id, and a signed-out forum must not
      // raise the platform's notification prompt by reading one.
      clientId = apiKey == null ? null : await authenticator.clientId();
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'messageBus.readCredentials');
      lease.commit(() => _trackersStarting.remove(siteUrl));
      return;
    }

    final hidePresenceVersion = _hidePresenceVersions[siteUrl] ?? 0;
    final groupedUnreadNotificationVersion =
        _groupedUnreadNotificationVersions[siteUrl] ?? 0;
    final draftCountVersion = _draftCountVersions[siteUrl] ?? 0;
    final categoryPreferenceVersion =
        _categoryNotificationPreferenceVersions[siteUrl] ?? 0;
    final pluginUserOptionVersion = _pluginUserOptionVersions[siteUrl] ?? 0;
    final bootstrap = apiKey == null || clientId == null
        ? null
        : await _messageBusBootstrap(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
            lease: lease,
          );
    final bootstrapUser = bootstrap?.currentUser;
    final freshBootstrapUser = bootstrapUser == null
        ? null
        : _acceptFreshCurrentUserSnapshot(
            siteUrl,
            bootstrapUser,
            lease,
            hidePresenceVersion,
            groupedUnreadNotificationVersion,
            draftCountVersion,
            categoryPreferenceVersion,
            pluginUserOptionVersion,
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
      if (isDisposed || current == null) return;

      // A site that is neither visible nor retained by a plugin lease gets no
      // tracker, subscriptions or plugin attachments; _syncTracking builds
      // them once it qualifies.
      final selectedAndVisible = _foreground && currentInstance?.url == siteUrl;
      final connectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!selectedAndVisible &&
          !connectedAndVisible &&
          !_backgroundRetention.retains(siteUrl)) {
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
      final bootstrapTracking = bootstrap?.topicTrackingState;
      if (trackingUsername != null &&
          userId != null &&
          bootstrapTracking != null &&
          (_categoryNotificationPreferenceVersions[siteUrl] ?? 0) ==
              categoryPreferenceVersion &&
          bootstrap!.hasCompleteTopicTrackingSnapshot(userId)) {
        _replayTopicTrackingEvents(siteUrl, bootstrapTracking);
        _topicTrackingPendingEvents.remove(siteUrl);
        _topicTrackingRetries.remove(siteUrl);
        _topicTrackingBySite[siteUrl] = bootstrapTracking;
        _topicTrackingSnapshotsLoaded.add(siteUrl);
        _topicTrackingRevisions.update(
          siteUrl,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if (currentInstance?.url == siteUrl) _notify();
      }
      final shouldLoadTopicTracking =
          trackingUsername != null &&
          !_topicTrackingBySite.containsKey(siteUrl) &&
          _topicTrackingLoads.add(siteUrl);
      if (shouldLoadTopicTracking) {
        _topicTrackingRetries.remove(siteUrl);
        _topicTrackingPendingEvents.putIfAbsent(siteUrl, () => <Object?>[]);
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
        if (shouldLoadTopicTracking) {
          _topicTrackingLoads.remove(siteUrl);
          _topicTrackingPendingEvents.remove(siteUrl);
        }
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
              username: trackingUsername,
              apiKey: apiKey,
              clientId: clientId,
              lease: lease,
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
            (_) =>
                commit(() => _invalidateCustomSidebarSections(siteUrl, lease)),
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
    required String apiKey,
    required String clientId,
    required SiteLease lease,
  }) async {
    try {
      final bootstrap = await api.site.messageBusBootstrap(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
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
    required String apiKey,
    required String clientId,
    required SiteLease lease,
    Future<void> Function()? refreshCategoryPreferences,
  }) async {
    final events = _topicTrackingPendingEvents.putIfAbsent(siteUrl, () => []);
    bool ownsLoad() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_topicTrackingPendingEvents[siteUrl], events);
    try {
      if (!ownsLoad()) return;
      if (refreshCategoryPreferences != null) {
        await refreshCategoryPreferences();
        if (!ownsLoad()) return;
        // These events preceded the authoritative preferences and report.
        // Pending native topic choices are overlaid when the report lands.
        events.clear();
      }
      final snapshot = await api.site.topicTrackingState(
        siteUrl: siteUrl,
        apiKey: apiKey,
        username: username,
        clientId: clientId,
      );
      if (!ownsLoad()) return;
      final currentUsername = _instanceAt(siteUrl)?.user?.username;
      if (currentUsername?.toLowerCase() != username.toLowerCase()) return;

      // The bus is attached before the HTTP request starts. Replaying anything
      // received while it was in flight closes the snapshot/message race; the
      // operations are idempotent when the response already included one.
      // Admission was decided on arrival, before buffering: a later unmuted
      // hint must neither admit an earlier event nor expire an accepted one.
      // The report's own length says whether it is complete, so it is
      // measured before the replay adds topics to it.
      final complete =
          snapshot.topics.length < TopicTrackingState.maxReportTopics;
      _replayTopicTrackingEvents(siteUrl, snapshot);
      lease.commit(() {
        final held = _topicTrackingBySite[siteUrl];
        if (held != null) snapshot.keepOmitted(held, complete: complete);
        _topicTrackingBySite[siteUrl] = snapshot;
        _topicTrackingSnapshotsLoaded.add(siteUrl);
        _topicTrackingRevisions.update(
          siteUrl,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if (currentInstance?.url == siteUrl) _notify();
      });
    } catch (error, stackTrace) {
      if (ownsLoad()) {
        _reportOperationalError(
          error,
          stackTrace,
          'topicTracking.load',
          severity: DiagnosticSeverity.warning,
        );
        _topicTrackingRetries[siteUrl] = (
          lease: lease,
          load: () => _loadTopicTrackingState(
            siteUrl: siteUrl,
            username: username,
            apiKey: apiKey,
            clientId: clientId,
            lease: lease,
            refreshCategoryPreferences: refreshCategoryPreferences,
          ),
        );
      }
    } finally {
      if (ownsLoad()) {
        _topicTrackingLoads.remove(siteUrl);
        _topicTrackingPendingEvents.remove(siteUrl);
      }
    }
  }

  void _replayTopicTrackingEvents(String siteUrl, TopicTrackingState snapshot) {
    for (final event
        in _topicTrackingPendingEvents[siteUrl] ?? const <Object?>[]) {
      snapshot.applyMessage(event);
    }
    for (final topic in snapshot.topics.toList()) {
      final position = _topicReads.lastReadPostNumberFor(
        siteUrl,
        topic.topicId,
      );
      if (position != null) snapshot.markRead(topic.topicId, position);
    }
    for (final write in _topicNotificationWrites.values) {
      if (write.siteUrl == siteUrl &&
          !write.result.isCompleted &&
          _isLatestTopicNotification(
            _topicKey(siteUrl, write.topicId),
            write,
          )) {
        snapshot.applyMessage(
          _topicNotificationTrackingMessage(write.topicId, write.level),
        );
      }
    }
  }

  void _applyTopicTrackingMessage(String siteUrl, Object? data) {
    // A message proves the site reachable again. A snapshot whose load failed
    // is fetched before this message is buffered, so the replay covers it.
    _retryTopicTrackingLoad(siteUrl);
    final filter = _topicTrackingMessageFilters.putIfAbsent(
      siteUrl,
      () => TopicTrackingMessageFilter(clock: _clock),
    );
    if (!filter.accepts(data, user: _instanceAt(siteUrl)?.user)) return;
    _topicTrackingPendingEvents[siteUrl]?.add(data);
    final tracking = _topicTrackingBySite.putIfAbsent(
      siteUrl,
      TopicTrackingState.new,
    );
    var changed = tracking.applyMessage(data);
    // Read/highest updates still apply during a write, but their older level
    // must not replace the latest optimistic selection.
    final topicId = data is Map ? jsonIntOrNull(data['topic_id']) : null;
    final localRead = topicId == null
        ? null
        : _topicReads.lastReadPostNumberFor(siteUrl, topicId);
    if (localRead != null) {
      changed = tracking.markRead(topicId!, localRead) || changed;
    }
    final write = _topicNotificationWrites[_topicKey(siteUrl, topicId ?? 0)];
    if (write != null &&
        !write.result.isCompleted &&
        _isLatestTopicNotification(_topicKey(siteUrl, write.topicId), write)) {
      changed =
          tracking.applyMessage(
            _topicNotificationTrackingMessage(write.topicId, write.level),
          ) ||
          changed;
    }
    _applyTopicDismissal(siteUrl, data, tracking);
    if (changed && currentInstance?.url == siteUrl) {
      _topicTrackingRevisions.update(
        siteUrl,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
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
    TopicTrackingState tracking,
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
        !_topicTrackingLoads.add(siteUrl)) {
      return;
    }
    _topicTrackingPendingEvents[siteUrl] = <Object?>[];
    unawaited(retry.load());
  }

  /// Re-reads a held snapshot after an absence the bus backlog may not
  /// cover. A load already in flight serves as this resume's read. The
  /// buffer opens before the request, as for any load, so what the resume
  /// poll delivers meanwhile reaches the new snapshot too, and
  /// [TopicTrackingState.applyMessage] ignores a message it has passed.
  void _resyncTopicTracking(String siteUrl) {
    final username = _instanceAt(siteUrl)?.user?.username;
    if (username == null ||
        !_topicTrackingSnapshotsLoaded.contains(siteUrl) ||
        !_topicTrackingLoads.add(siteUrl)) {
      return;
    }
    _topicTrackingRetries.remove(siteUrl);
    final events = _topicTrackingPendingEvents[siteUrl] = <Object?>[];
    final lease = lifecycle.capture(siteUrl);
    bool ownsResync() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_topicTrackingPendingEvents[siteUrl], events);
    unawaited(() async {
      String? apiKey;
      String? clientId;
      try {
        apiKey = await credentials.apiKeyFor(siteUrl);
        if (!ownsResync()) return;
        clientId = apiKey == null ? null : await authenticator.clientId();
      } catch (error, stackTrace) {
        if (ownsResync()) {
          _reportOperationalError(
            error,
            stackTrace,
            'topicTracking.readCredentials',
            severity: DiagnosticSeverity.warning,
          );
        }
      }
      if (!ownsResync()) return;
      if (apiKey == null || clientId == null) {
        _topicTrackingLoads.remove(siteUrl);
        _topicTrackingPendingEvents.remove(siteUrl);
        return;
      }
      await _loadTopicTrackingState(
        siteUrl: siteUrl,
        username: username,
        apiKey: apiKey,
        clientId: clientId,
        lease: lease,
      );
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

    final hidePresenceVersion = _hidePresenceVersions[siteUrl] ?? 0;
    final groupedUnreadNotificationVersion =
        _groupedUnreadNotificationVersions[siteUrl] ?? 0;
    final draftCountVersion = _draftCountVersions[siteUrl] ?? 0;
    final categoryPreferenceVersion =
        _categoryNotificationPreferenceVersions[siteUrl] ?? 0;
    final pluginUserOptionVersion = _pluginUserOptionVersions[siteUrl] ?? 0;
    late final Future<DiscourseUser?> request;
    request =
        _readSessionUser(
          siteUrl,
          apiKey,
          session,
          hidePresenceVersion,
          groupedUnreadNotificationVersion,
          draftCountVersion,
          categoryPreferenceVersion,
          pluginUserOptionVersion,
        ).whenComplete(() {
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
    int hidePresenceVersion,
    int groupedUnreadNotificationVersion,
    int draftCountVersion,
    int categoryPreferenceVersion,
    int pluginUserOptionVersion,
  ) async {
    if (!lease.isCurrent || _connectingSiteUrl == siteUrl) return null;

    final DiscourseUser responseUser;
    try {
      responseUser = await api.site.currentUser(
        siteUrl: siteUrl,
        apiKey: apiKey,
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
      hidePresenceVersion,
      groupedUnreadNotificationVersion,
      draftCountVersion,
      categoryPreferenceVersion,
      pluginUserOptionVersion,
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
    int hidePresenceVersion,
    int groupedUnreadNotificationVersion,
    int draftCountVersion,
    int categoryPreferenceVersion,
    int pluginUserOptionVersion,
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
      final accountChanged =
          previousUser != null &&
          !plugins.models.sameCurrentUserAccount(previousUser, user);
      final withPreservedPlugins = plugins.models.preserveUnknownCurrentUser(
        previousUser,
        user,
      );
      final preserveConfirmedPresence =
          !accountChanged &&
          (_hidePresenceWrites.containsKey(siteUrl) ||
              (_hidePresenceVersions[siteUrl] ?? 0) != hidePresenceVersion);
      final groupedCountsAreCurrent =
          (_groupedUnreadNotificationVersions[siteUrl] ?? 0) ==
          groupedUnreadNotificationVersion;
      final draftCountIsCurrent =
          (_draftCountVersions[siteUrl] ?? 0) == draftCountVersion;
      var reconciledUser = preserveConfirmedPresence
          ? withPreservedPlugins.withHidePresence(previousUser?.hidePresence)
          : withPreservedPlugins;
      if (!accountChanged && !groupedCountsAreCurrent && previousUser != null) {
        // The response predates a live snapshot or a local read/dismiss write.
        // Keep accepting its unrelated current-user fields, but do not expose
        // its stale grouped map through the menu's user fallback.
        reconciledUser = reconciledUser.withGroupedUnreadNotifications(
          previousUser.groupedUnreadNotifications,
        );
      }
      if (!accountChanged && !draftCountIsCurrent && previousUser != null) {
        reconciledUser = reconciledUser.withDraftCount(previousUser.draftCount);
      }
      if (!accountChanged &&
          previousUser != null &&
          (_categoryNotificationPreferenceVersions[siteUrl] ?? 0) !=
              categoryPreferenceVersion) {
        reconciledUser = reconciledUser.withCategoryNotificationPreferences(
          trackedCategoryIds: previousUser.trackedCategoryIds,
          watchedCategoryIds: previousUser.watchedCategoryIds,
          watchedFirstPostCategoryIds: previousUser.watchedFirstPostCategoryIds,
          mutedCategoryIds: previousUser.mutedCategoryIds,
          indirectlyMutedCategoryIds: previousUser.indirectlyMutedCategoryIds,
        );
      }
      if (!accountChanged) {
        var data = reconciledUser.plugins;
        for (final write
            in (_pluginUserOptionUpdates[siteUrl]?.values ??
                const <_PluginUserOptionUpdate>[])) {
          if (write.revision > pluginUserOptionVersion) {
            data = write.update(data);
          }
        }
        reconciledUser = reconciledUser.withPlugins(data);
      }
      committedUser = reconciledUser;
      _sessionUsersRefreshed.add(siteUrl);
      _hidePresenceErrors.remove(siteUrl);
      if (previousUser != committedUser || accountChanged) {
        changed = true;
        if (accountChanged) {
          _pluginUserOptionUpdates.remove(siteUrl);
          // Other in-flight reads can still carry the previous account's
          // revision, so the counter stays monotonic until site retirement.
          accountActivity.forget(siteUrl);
          groups.forget(siteUrl);
          userDirectory.forget(siteUrl);
          badges.forget(siteUrl);
          _topicTrackingBySite.remove(siteUrl);
          _topicTrackingMessageFilters.remove(siteUrl);
          _topicTrackingSnapshotsLoaded.remove(siteUrl);
          _topicTrackingRevisions.remove(siteUrl);
          _topicTrackingLoads.remove(siteUrl);
          _topicTrackingRetries.remove(siteUrl);
          _topicTrackingPendingEvents.remove(siteUrl);
        }
        _replaceInstance(
          fresh,
          fresh.copyWith(
            user: committedUser,
            clearNotificationTotals: accountChanged,
          ),
        );
      }
      if (accountChanged || groupedCountsAreCurrent) {
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

    _draftCountVersions.update(
      siteUrl,
      (version) => version + 1,
      ifAbsent: () => 1,
    );

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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final apiKey = credential.value;
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
    _bumpHidePresenceVersion(siteUrl);
    _notify();

    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_hidePresenceWrites[siteUrl], request);

    try {
      final credential = await _credentialForWrite(siteUrl);
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
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !isCurrent()) return;
      await api.site.updateHidePresence(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        username: user.username,
        hidePresence: desired,
        clientId: identity.value,
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
      _bumpHidePresenceVersion(siteUrl);

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

  void _bumpHidePresenceVersion(String siteUrl) {
    _hidePresenceVersions[siteUrl] = (_hidePresenceVersions[siteUrl] ?? 0) + 1;
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
      final credential = await _credentialForWrite(siteUrl);
      if (!ownsWrite()) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!ownsWrite()) return null;
      if (endsAt != null && !endsAt.isAfter(_clock())) {
        return appL10n.chooseATimeInTheFuture;
      }
      await api.site.setUserStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        description: description,
        emoji: emoji,
        endsAt: endsAt,
        clientId: clientId,
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
      final credential = await _credentialForWrite(siteUrl);
      if (!ownsWrite()) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!ownsWrite()) return null;
      await api.site.clearUserStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        clientId: clientId,
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
    _flushPendingAnchorPersist();
    if (_tabSelectionPersistencePending) _persistWorkspaces();
    for (final composer in _composers.values) {
      unawaited(composer.flushDraftOnBackground());
    }
    await Future.wait([_workspacesSaved, _composerDrafts.localWritesSettled()]);
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) _topicPrefetch.validate();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = foreground ? null : _clock();
    // The OS may suspend the process before a debounce timer fires again.
    if (!foreground) {
      _flushPendingAnchorPersist();
      for (final composer in _composers.values) {
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

  final _topicPrefetch = TopicPrefetchController();
  final Set<String> _topicsLoading = {};
  final Set<String> _topicRefreshPending = {};
  final Map<String, int> _topicRefreshPostNumbers = {};
  // A failed forced reconciliation, or a write whose effect on the topic was
  // only projected, must not turn the held topic into a permanent cache hit.
  // The next ordinary open reads it again automatically.
  final Set<String> _topicsStale = {};
  final Set<String> _postsLoading = {};
  final Set<String> _earlierPostsLoading = {};
  final Map<String, List<int>> _topicSummaryStreams = {};
  final Set<String> _topicSummariesLoading = {};
  final Set<(String, int, int, bool)> _postGapsLoading = {};
  final Map<String, _QueuedTopicNotification> _topicNotificationWrites = {};
  final Map<String, Future<void>> _topicNotificationTails = {};
  final Map<String, TopicNotificationLevel> _topicNotificationConfirmed = {};
  final Map<String, _QueuedCategoryNotification> _categoryNotificationWrites =
      {};
  final Map<String, Future<void>> _categoryNotificationTails = {};
  final Map<String, Future<void>> _categoryNotificationSiteTails = {};
  final Map<String, int> _categoryNotificationPreferenceVersions = {};
  final Map<String, int> _pluginUserOptionVersions = {};
  final Map<String, Map<String, _PluginUserOptionUpdate>>
  _pluginUserOptionUpdates = {};
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

  TopicDetail? get currentTopic {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return store.read<TopicDetail>(instance.url, topicId);
  }

  bool get currentTopicSummary {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicSummaryStreams.containsKey(_topicKey(instance.url, topicId));
  }

  bool get currentTopicSummaryLoading {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicSummariesLoading.contains(_topicKey(instance.url, topicId));
  }

  List<int> _topicStream(String siteUrl, TopicDetail detail) =>
      _topicSummaryStreams[_topicKey(siteUrl, detail.id)] ?? detail.stream;

  List<int> get currentTopicStreamIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    return _topicStream(instance.url, detail);
  }

  List<int> get currentPostIds => _currentPostWindow().ids;

  /// The loaded, contiguous run of the open topic's stream, with its bounds.
  ///
  /// The viewport snapshot and the paging flags ask on every shell
  /// notification, so the run is found once per change of its inputs:
  /// finding it reads the store once per loaded post, and every read touches
  /// the store's recency order.
  _PostWindow _currentPostWindow() {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return _emptyPostWindow;
    final stream = _topicStream(instance.url, detail);
    final key = (
      instance.url,
      detail,
      stream,
      currentContent?.postNumber,
      store.generationOf<Post>(instance.url),
    );
    final cacheId = (instance.url, activeTabId);
    final cachedKey = _postWindowCacheKeys[cacheId];
    if (cachedKey != null &&
        cachedKey.$1 == key.$1 &&
        identical(cachedKey.$2, key.$2) &&
        identical(cachedKey.$3, key.$3) &&
        cachedKey.$4 == key.$4 &&
        cachedKey.$5 == key.$5) {
      return _postWindowCaches[cacheId]!;
    }
    final range = _loadedPostRange(instance.url, detail, stream: stream);
    _postWindowCacheKeys[cacheId] = key;
    return _postWindowCaches[cacheId] = (
      stream: stream,
      range: range,
      ids: range == null
          ? const []
          : [for (final id in stream.sublist(range.$1, range.$2 + 1)) id],
    );
  }

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

  (int, int)? _loadedPostRange(
    String siteUrl,
    TopicDetail detail, {
    List<int>? stream,
  }) {
    final effectiveStream = stream ?? _topicStream(siteUrl, detail);
    if (effectiveStream.isEmpty) return null;

    final target = currentContent?.postNumber;
    var anchor = -1;
    if (target != null) {
      for (var i = 0; i < effectiveStream.length; i++) {
        final post = store.read<Post>(siteUrl, effectiveStream[i]);
        if (post != null && post.postNumber >= target) {
          anchor = i;
          break;
        }
      }
    } else {
      anchor = effectiveStream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    // A stale cache or a deliberately minimal test payload may not contain
    // the requested post yet. Keep showing the contiguous data in hand until
    // the around-post request lands instead of flashing an empty topic.
    if (anchor < 0 && target != null) {
      anchor = effectiveStream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    if (anchor < 0) return null;

    var first = anchor;
    while (first > 0 &&
        store.read<Post>(siteUrl, effectiveStream[first - 1]) != null) {
      first--;
    }
    var last = anchor;
    while (last + 1 < effectiveStream.length &&
        store.read<Post>(siteUrl, effectiveStream[last + 1]) != null) {
      last++;
    }
    return (first, last);
  }

  List<int> _pendingPostIds(String siteUrl, TopicDetail detail) {
    final stream = _topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    final start = range == null ? 0 : range.$2 + 1;
    return [
      for (final id in stream.skip(start))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  List<int> _pendingEarlierPostIds(
    String siteUrl,
    TopicDetail detail,
    int batchSize,
  ) {
    final stream = _topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    if (range == null || range.$1 == 0) return const [];
    final start = range.$1 > batchSize ? range.$1 - batchSize : 0;
    return [
      for (final id in stream.sublist(start, range.$1))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  /// The loaded post the open mega topic pages from on the [newer] side of
  /// its window, or null where there is nothing to read past it by post
  /// number.
  ///
  /// A mega topic's stream is only the run read so far
  /// (TopicDetail.isMegaTopic), so past an end of the window that is also an
  /// end of the stream the topic goes on by post number, until the window
  /// holds the topic's last post id or its first post, as on the web client.
  /// A summary stream is read whole and pages by id.
  Post? _currentMegaTopicEdge({required bool newer}) {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null || !detail.isMegaTopic) return null;
    final window = _currentPostWindow();
    final stream = window.stream;
    final range = window.range;
    if (range == null || !identical(stream, detail.stream)) return null;
    if (newer) {
      if (range.$2 + 1 < stream.length ||
          stream[range.$2] == detail.lastPostId) {
        return null;
      }
      return store.read<Post>(instance.url, stream[range.$2]);
    }
    if (range.$1 > 0) return null;
    final first = store.read<Post>(instance.url, stream.first);
    return first != null && first.postNumber > 1 ? first : null;
  }

  /// Whether the stream continues past the loaded window.
  ///
  /// The window is the longest contiguous run of loaded posts, so the post
  /// after it is unloaded by construction, and with no window at all every
  /// post of the stream is still to come.
  bool get currentTopicHasMore {
    final window = _currentPostWindow();
    final range = window.range;
    return range == null
        ? window.stream.isNotEmpty
        : range.$2 + 1 < window.stream.length ||
              _currentMegaTopicEdge(newer: true) != null;
  }

  bool get currentTopicHasEarlier {
    final range = _currentPostWindow().range;
    return range != null &&
        (range.$1 > 0 || _currentMegaTopicEdge(newer: false) != null);
  }

  bool get currentTopicLoading {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicsLoading.contains(_topicKey(instance.url, topicId));
  }

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

  TabOpenResult openTopicFromList(Topic topic, {bool revealInList = false}) {
    final result = _openTopic(
      topic.id,
      topic.slug,
      topic.title,
      postNumber: topic.lastUnreadPostNumber,
      replace: currentContent?.isTopic == true && topicListContent != null,
    );
    if (revealInList && result == TabOpenResult.opened) {
      _topicListRevealRequests.add(topic.id);
    }
    return result;
  }

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
    final categories = _categoriesBySite[targetSiteUrl] ?? const [];
    final byId = <int, TopicCategory>{
      for (final item in categories) item.id: item,
      category.id: category,
    };
    final route = ContentRoute.fromDestination(
      buildCategoryDestination(category, categoriesById: byId),
    );
    if (currentContent?.id == route.id) {
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
    if (currentContent?.id == route.id) return;
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
        contentId: currentContent?.id,
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
          currentContent?.id != source.contentId ||
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
    if (currentContent?.id == route.id) {
      showPluginContent();
      return true;
    }
    pushContent(route);
    unawaited(loadFeed(route.id));
    return true;
  }

  TopicTag _topicTagWithKnownIdentity(String siteUrl, TopicTag topicTag) {
    if (topicTag.id case final id? when id > 0) return topicTag;
    final known = _knownTopicTag(siteUrl, topicTag);
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

  SidebarTag? _knownTopicTag(String siteUrl, TopicTag topicTag) {
    final topicTagId = topicTag.id;
    final topicTagName = topicTag.name.trim().toLowerCase();
    for (final tag in _knownTagsFor(siteUrl)) {
      if ((topicTagId != null && topicTagId > 0 && tag.id == topicTagId) ||
          tag.name.trim().toLowerCase() == topicTagName) {
        return tag;
      }
    }
    return null;
  }

  Iterable<SidebarTag> _knownTagsFor(String siteUrl) sync* {
    yield* _instanceAt(siteUrl)?.user?.sidebarTags ?? const [];
    yield* _siteTopTagsBySite[siteUrl] ?? const [];
    yield* _anonymousDefaultTagsBySite[siteUrl] ?? const [];
    yield* tagDirectoryFeedFor(siteUrl).tags;
  }

  bool _isKnownPrivateMessageOnlyTag(String siteUrl, TopicTag topicTag) {
    return _knownTopicTag(siteUrl, topicTag)?.pmOnly == true;
  }

  void openSearchResult(SearchPostHit hit) {
    search.clear();
    if (currentContent?.topicId == hit.topicId) {
      openCurrentTopicPost(hit.postNumber, loadAroundPost: true);
      return;
    }
    _openTopic(
      hit.topicId,
      hit.topicSlug,
      hit.topicTitle,
      postNumber: hit.postNumber,
    );
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
  }) {
    // A fast double tap on a row pushes the same topic twice — the fetch is
    // deduped below, but the second route still costs a back tap.
    if (currentInstance == null) return TabOpenResult.unsupported;
    if (currentContent?.topicId == topicId) return TabOpenResult.opened;
    SurfaceOpeningTrace.mark('topic.request');
    if (currentInstance case final instance?) {
      _topicSummaryStreams.remove(_topicKey(instance.url, topicId));
    }
    final route = ContentRoute.topic(
      topicId: topicId,
      slug: slug,
      title: title,
      postNumber: postNumber,
    );
    // An explicit post destination supersedes the last reading position from
    // an earlier visit to this topic in the same tab.
    final tab = activeTab;
    if (resetScrollPosition &&
        tab != null &&
        tab.anchors.containsKey(route.id)) {
      _replaceActiveTab(
        tab.copyWith(
          anchors: Map<String, ForumTabAnchor>.of(tab.anchors)
            ..remove(route.id),
        ),
        persist: false,
      );
    }
    if (replace) {
      replaceCurrentContent(route);
    } else {
      pushContent(route);
    }
    unawaited(loadTopic(topicId, slug, force: force, postNumber: postNumber));
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

  /// Resolves the clicked link without selecting its forum, tab, or topic.
  Future<BookmarkLinkAction?> resolveBookmarkLink(
    String url, {
    Bookmark? targetBookmark,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null || !{'http', 'https'}.contains(target.scheme)) {
      return null;
    }
    final instance = _instances
        .where((site) => site.serves(target))
        .firstOrNull;
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
      final version = _bookmarkVersion(siteUrl, link.topicId);
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential?.value == null || !lease.isCurrent) return null;
      final payload = await api.topicContent.topic(
        siteUrl: siteUrl,
        slug: link.slug,
        id: link.topicId,
        postNumber: link.postNumber,
        apiKey: credential!.value,
      );
      if (!lease.isCurrent ||
          payload.detail.id != link.topicId ||
          version != _bookmarkVersion(siteUrl, link.topicId)) {
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
      return BookmarkLinkAction(
        bookmark: bookmark,
        invoke: () async {
          if (!lease.isCurrent ||
              version != _bookmarkVersion(siteUrl, link.topicId)) {
            return BookmarkWriteResult.refused(
              appL10n.bookmarkChangedRefreshMenu,
            );
          }
          final host = bookmarkTarget(type);
          return bookmark == null
              ? host.createBookmark(
                  siteUrl: siteUrl,
                  topicId: link.topicId,
                  targetId: targetId,
                )
              : host.deleteBookmark(
                  siteUrl: siteUrl,
                  topicId: link.topicId,
                  bookmark: bookmark,
                );
        },
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
    return openContentInPanel(destination.route, panel: panel);
  }

  ({ContentRoute route, String siteUrl})? _routeForLink(
    String url, {
    String? title,
  }) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return null;
    final instance = _instances
        .where((site) => site.serves(target))
        .firstOrNull;
    if (instance == null) return null;

    final topic = TopicLink.parse(absolute, siteUrl: instance.url);
    final list = ListLink.parse(absolute, siteUrl: instance.url);
    final group = GroupRoute.parse(absolute, siteUrl: instance.url);
    final badge = instance.config.badgesEnabled
        ? BadgeRoute.parse(absolute, siteUrl: instance.url)
        : null;
    final ContentRoute route;
    if (_ownMessagesRoute(instance, target) case final messages?) {
      route = messages;
    } else if (instance.pathWithin(target) == '/u' &&
        !target.hasQuery &&
        !target.hasFragment) {
      route = ContentRoute(
        id: 'users',
        title: appL10n.users,
        icon: DIcons.user,
      );
    } else if (_coreListRoute(instance, target) case final core?) {
      route = core;
    } else if (instance.pathWithin(target) == '/categories' &&
        !target.hasQuery &&
        !target.hasFragment) {
      route = ContentRoute.allCategories();
    } else if (topic != null) {
      route = ContentRoute.topic(
        topicId: topic.topicId,
        slug: topic.slug,
        title: title ?? topic.placeholderTitle,
        postNumber: topic.postNumber,
      );
    } else if (list != null) {
      final category = list.kind == ListKind.category
          ? categoryFor(list.id, siteUrl: instance.url)
          : null;
      route = ContentRoute.list(
        list,
        title: title,
        color: category == null ? null : Color(category.colorValue),
      ).resolveCategoryLink(filterCategoriesFor(instance.url));
    } else if (badge != null) {
      route = ContentRoute.badges(badge, title: title);
    } else if (group != null) {
      route = ContentRoute.group(
        group,
        feedPath: group.topicFeedPath(instance.user?.username),
      );
    } else {
      return null;
    }
    return (route: route, siteUrl: instance.url);
  }

  /// The native list a core `/latest`, `/new`, `/unread`, `/unseen`, `/top`,
  /// `/hot`, `/filter` or `/tags` link names. A plain link keeps the canonical
  /// id that banners, counters and the sidebar key on; any other parameter
  /// rides along to the server as it does on the web. Null — the browser —
  /// for a list this forum's reader cannot have, as [selectTopicListMode]
  /// refuses it, and for anything the app has no list for.
  ContentRoute? _coreListRoute(DiscourseInstance instance, Uri target) {
    if (target.hasFragment) return null;
    final Map<String, List<String>> query;
    try {
      query = {...target.queryParametersAll}..remove('page');
    } on FormatException {
      return null;
    }
    final user = instance.user;
    final path = instance.pathWithin(target);
    final ContentRoute route;
    switch (path) {
      case '/tags':
        if (!siteConfigFor(instance.url).taggingEnabled) return null;
        return ContentRoute.fromDestination(allTagsDestination);
      case '/filter':
        final filter = query['q']?.firstOrNull?.trim() ?? '';
        route = filter.isEmpty
            ? ContentRoute.topicList(TopicListMode.latest)
            : ContentRoute.topicFilter(filter);
      case '/latest' || '/hot':
        route = ContentRoute.filteredTopicList(
          path == '/hot' ? TopicListMode.popular : TopicListMode.latest,
          query: query,
        );
      case '/unread' || '/unseen' when user != null:
        route = ContentRoute.filteredTopicList(
          path == '/unread' ? TopicListMode.unread : TopicListMode.unseen,
          query: query,
        );
      case '/new' when user != null:
        // The server reads a subset only for a reader on the unified New
        // list; anyone else is served the whole of New.
        final subset = query.remove('subset')?.firstOrNull;
        route = ContentRoute.filteredTopicList(switch (subset) {
          'topics' when user.unifiedNewEnabled => TopicListMode.newTopics,
          'replies' when user.unifiedNewEnabled => TopicListMode.newReplies,
          _ => TopicListMode.newActivity,
        }, query: query);
      case '/top':
        final value = query.remove('period')?.firstOrNull;
        final period = value == null
            ? _defaultTopPeriodFor(instance.url)
            : TopPeriod.values
                  .where((period) => period.queryValue == value)
                  .firstOrNull;
        if (period == null) return null;
        route = ContentRoute.filteredTopicList(
          TopicListMode.top(period),
          query: query,
        );
      default:
        return null;
    }
    final feedPath = route.feedPath;
    if (feedPath != null &&
        feedPath.length > ContentRoute.maximumFeedPathLength) {
      return null;
    }
    return route;
  }

  /// The native inbox a link to the reader's own messages names, spelled as
  /// the web routes it under `/u/{me}/messages` or `/my/messages`: the
  /// personal inbox and its `unread`, `sent` and `archive` folders, and
  /// `group/{name}` with its `unread` and `archive` folders. A group-message
  /// summary notification links to a group inbox. Null — the browser — for
  /// another reader's messages, a group whose messages this account cannot
  /// read, and a folder the app has no list for.
  ContentRoute? _ownMessagesRoute(DiscourseInstance instance, Uri target) {
    final user = instance.user;
    if (user == null || target.hasQuery || target.hasFragment) return null;
    final List<String> inbox;
    switch (DiscourseInstance.pathSegmentsWithin(instance.url, target)) {
      case ['my', 'messages', ...final rest]:
        inbox = rest;
      case ['u', final username, 'messages', ...final rest]
          when username.toLowerCase() == user.username.toLowerCase():
        inbox = rest;
      default:
        return null;
    }
    final (groupName, folder) = switch (inbox) {
      ['group', final name, ...final folder] => (name, folder),
      _ => (null, inbox),
    };
    // The route keeps the server's spelling so it is the same list, under the
    // same id, as the one the inbox selector opens.
    final group = groupName == null
        ? null
        : user.messageGroupNames
              .where((name) => name.toLowerCase() == groupName.toLowerCase())
              .firstOrNull;
    if (groupName != null && group == null) return null;
    final mode = switch (folder) {
      [] => MessageListMode.inbox,
      ['unread'] => MessageListMode.unread,
      ['sent'] => MessageListMode.sent,
      ['archive'] => MessageListMode.archive,
      _ => null,
    };
    if (mode == null || (group != null && !mode.supportsGroup)) return null;
    return ContentRoute.messages(groupName: group, mode: mode);
  }

  TabOpenResult openContentInNewTab(
    ContentRoute route, {
    String? siteUrl,
    ForumPanel? panel,
    int? index,
    bool? select,
    String? rootDestinationId,
    ForumTab? source,
  }) {
    if (!forumTabsEnabled) return TabOpenResult.unsupported;
    final instance = siteUrl == null
        ? currentInstance
        : _instances.where((site) => site.url == siteUrl).firstOrNull;
    if (instance == null) return TabOpenResult.unsupported;
    final workspace = _ensureWorkspace(instance);
    if (workspace.tabs.length >= ForumWorkspace.maximumTabs) {
      return TabOpenResult.limitReached;
    }
    final root = _newDefaultTab();
    final tab =
        (source != null
                ? ForumTab(
                    id: root.id,
                    rootDestinationId: source.rootDestinationId,
                    contentStack: [
                      ...source.contentStack
                          .where(
                            (item) =>
                                item.id != route.id &&
                                (!route.isTopic || !item.isTopic),
                          )
                          .take(ForumTab.maximumContentRoutes - 1),
                      route,
                    ],
                  )
                : root.copyWith(
                    rootDestinationId: rootDestinationId ?? route.id,
                    contentStack: [route],
                  ))
            .copyWith(
              panel: panel ?? workspace.activeTab.panel,
              rootDestinationId: rootDestinationId,
            );
    final activate = select ?? desktopTopicTabs;
    _pendingHomepageTabs.remove(tab.id);
    final tabs = [...workspace.tabs];
    if (index == null) {
      tabs.add(tab);
    } else {
      final destinationTabs = tabs
          .where((item) => item.panel == tab.panel)
          .toList();
      final position = index.clamp(0, destinationTabs.length);
      final insertion = position < destinationTabs.length
          ? tabs.indexOf(destinationTabs[position])
          : destinationTabs.isEmpty
          ? tabs.length
          : tabs.indexOf(destinationTabs.last) + 1;
      tabs.insert(insertion, tab);
    }
    _putWorkspace(
      workspace.copyWith(tabs: tabs, activeTabId: activate ? tab.id : null),
    );
    _rememberRoute(instance.url, workspace.accountIdentity, route);
    if (activate && currentInstance?.url == instance.url) {
      _mobilePane = MobilePane.content;
      _hydrateActiveTab(instance);
    }
    _syncTopicChannels();
    _notify();
    return TabOpenResult.opened;
  }

  TabOpenResult openContentInPanel(
    ContentRoute route, {
    required ForumPanel panel,
    bool resetScrollPosition = false,
  }) {
    final instance = currentInstance;
    final workspace = currentWorkspace;
    final source = activeTab;
    if (instance == null || workspace == null || source == null) {
      return TabOpenResult.unsupported;
    }
    if (source.panel == panel) {
      pushContent(route);
      _hydrateActiveTab(instance);
      return TabOpenResult.opened;
    }
    final selected = workspace.selectedTabIn(panel);
    if (selected == null) {
      return openContentInNewTab(
        route,
        panel: panel,
        select: true,
        source: source,
      );
    }

    final target = selected.navigate(
      rootDestinationId: source.rootDestinationId,
      contentStack: [
        ...source.contentStack
            .where(
              (item) =>
                  item.id != route.id && (!route.isTopic || !item.isTopic),
            )
            .take(ForumTab.maximumContentRoutes - 1),
        route,
      ],
    );
    final updated = resetScrollPosition
        ? target.copyWith(
            anchors: Map<String, ForumTabAnchor>.of(target.anchors)
              ..remove(route.id),
          )
        : target;
    _pendingHomepageTabs.remove(updated.id);
    _putWorkspace(
      workspace.copyWith(
        tabs: [
          for (final tab in workspace.tabs)
            if (tab.id == updated.id) updated else tab,
        ],
        activeTabId: updated.id,
      ),
    );
    _setForumContentRoot();
    _syncTopicChannels();
    _notify();
    _hydrateActiveTab(instance);
    return TabOpenResult.opened;
  }

  bool openBadgeUrl(String url, {String? title, bool refresh = false}) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final index = _instances.indexWhere((instance) => instance.serves(target));
    if (index < 0) return false;
    final instance = _instances[index];
    if (!instance.config.badgesEnabled) return false;
    final route = BadgeRoute.parse(absolute, siteUrl: instance.url);
    if (route == null) return false;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.badgeRoute != route) {
      pushContent(ContentRoute.badges(route, title: title));
    } else if (rootChanged) {
      _notify();
    }
    unawaited(badges.load(instance, route, refresh: refresh));
    return true;
  }

  bool openGroupUrl(String url) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final index = _instances.indexWhere((instance) => instance.serves(target));
    if (index < 0) return false;
    final route = GroupRoute.parse(absolute, siteUrl: _instances[index].url);
    if (route == null) return false;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.groupRoute == route) {
      if (rootChanged) _notify();
      return true;
    }

    final instance = _instances[index];
    final content = ContentRoute.group(
      route,
      feedPath: route.topicFeedPath(instance.user?.username),
    );
    pushContent(content);
    if (content.feedPath != null) unawaited(loadFeed(content.id));
    return true;
  }

  bool _openTopicUrl(String url, {bool refresh = false}) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final index = _instances.indexWhere((i) => i.serves(target));
    if (index < 0) return false;
    final link = TopicLink.parse(absolute, siteUrl: _instances[index].url);
    if (link == null) return false;

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
      link.slug,
      link.placeholderTitle,
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

  ({int topicId, String slug})? _targetCurrentTopicPost(int postNumber) {
    final route = currentContent;
    final tab = activeTab;
    if (route?.topicId case final topicId? when tab != null && postNumber > 0) {
      final anchors = Map<String, ForumTabAnchor>.of(tab.anchors)
        ..remove(route!.id);
      final targeted = ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: route.title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: postNumber,
      );
      _topicNavigationRevisions[activeTabId] = topicNavigationRevision + 1;
      _replaceActiveTab(
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

  int get topicNavigationRevision =>
      _topicNavigationRevisions[activeTabId] ?? 0;

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
        final credential = await _readSessionValue(
          lease,
          () => credentials.apiKeyFor(instance.url),
        );
        if (credential == null || !isCurrent()) return false;
        final bookmarkVersion = _bookmarkVersion(instance.url, topic.id);
        final fetched = await api.topicContent.posts(
          siteUrl: instance.url,
          topicId: topic.id,
          ids: [targetId],
          apiKey: credential.value,
        );
        if (!isCurrent()) return false;
        target = fetched.where((post) => post.id == targetId).firstOrNull;
        if (target == null) return false;
        lease.commit(
          () => _putTopicPosts(instance.url, topic.id, [
            target!,
          ], bookmarkVersionAtDispatch: bookmarkVersion),
        );
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
    // Topics, category and tag lists, badges and groups have their own openers.
    if (TopicListMode.fromRoute(route) == null &&
        !route.isMessages &&
        !const {'users', 'all-categories', 'all-tags'}.contains(route.id)) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    if (index < 0) return false;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.id == route.id) {
      if (rootChanged) _notify();
      return true;
    }
    pushContent(route);
    if (route.isUsers) {
      unawaited(userDirectory.load(_instances[index]));
    } else if (route.id == 'all-categories') {
      unawaited(loadCategories(destination.siteUrl));
    } else if (route.id == 'all-tags') {
      unawaited(loadTags(destination.siteUrl));
    } else {
      unawaited(loadFeed(route.id));
    }
    return true;
  }

  bool openListUrl(String url, {String? title}) {
    final absolute = absoluteUrl(url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final index = _instances.indexWhere((i) => i.serves(target));
    if (index < 0) return false;
    final link = ListLink.parse(absolute, siteUrl: _instances[index].url);
    if (link == null) return false;

    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();

    final category = link.kind == ListKind.category
        ? categoryFor(link.id)
        : null;

    final route = ContentRoute.list(
      link,
      title: title,
      color: category == null ? null : Color(category.colorValue),
    ).resolveCategoryLink(filterCategoriesFor(_instances[index].url));

    if (currentContent?.id == route.id) {
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
    final topicKey = _topicKey(siteUrl, topic.id);
    final postNumber = topic.lastUnreadPostNumber;
    if (_topicsLoading.contains(topicKey) ||
        (!_topicsStale.contains(topicKey) &&
            _hasTopicPost(siteUrl, topic.id, postNumber))) {
      return () {};
    }
    final lease = lifecycle.capture(siteUrl);
    final owner = (activeTabId, currentContent?.id, topicListContent?.id);
    return _topicPrefetch.hover(
      (
        siteUrl: siteUrl,
        session: lease.session,
        topicId: topic.id,
        postNumber: postNumber,
      ),
      intent: intent,
      isCurrent: () =>
          !isDisposed &&
          (isInterested?.call() ?? true) &&
          _foreground &&
          lease.isCurrent &&
          currentInstance?.url == siteUrl &&
          rootMode == ShellRootMode.forum &&
          ((activeTabId, currentContent?.id, topicListContent?.id) == owner ||
              (currentContent?.topicId == topic.id &&
                  currentContent?.postNumber == postNumber)),
      load: (cancellation) async {
        final elapsed = Stopwatch()..start();
        final bookmarkVersion = _bookmarkVersion(siteUrl, topic.id);
        final archiveVersion = _messageArchiveVersion(siteUrl, topic.id);
        final postRemovalVersion = _topicPostRemovalVersion(siteUrl, topic.id);
        try {
          final credential = await _awaitTopicLoadStage(
            Future.any<_SessionValue<String?>?>([
              _readSessionValue(lease, () => credentials.apiKeyFor(siteUrl)),
              cancellation.trigger.then((_) => null),
            ]),
            elapsed,
            'reading credentials for topic prefetch',
          );
          if (credential == null ||
              !lease.isCurrent ||
              cancellation.isCancelled) {
            return null;
          }
          final payload = await _awaitTopicLoadStage(
            api.topicContent.topic(
              siteUrl: siteUrl,
              slug: topic.slug,
              id: topic.id,
              postNumber: postNumber,
              apiKey: credential.value,
              abortTrigger: cancellation.trigger,
            ),
            elapsed,
            'prefetching topic ${topic.id}',
          );
          if (isDisposed || !lease.isCurrent || cancellation.isCancelled) {
            return null;
          }
          return PrefetchedTopic(
            payload,
            bookmarkVersion,
            archiveVersion,
            postRemovalVersion,
          );
        } catch (_) {
          cancellation.cancel();
          return null;
        }
      },
    );
  }

  bool _hasTopicPost(String siteUrl, int topicId, int? postNumber) {
    final held = store.read<TopicDetail>(siteUrl, topicId);
    return held != null &&
        (postNumber == null ||
            held.stream.any(
              (id) => store.read<Post>(siteUrl, id)?.postNumber == postNumber,
            ));
  }

  Future<void> loadTopic(
    int topicId,
    String slug, {
    bool force = false,
    int? postNumber,
  }) => DiagnosticsSink.runOperation(
    'topic.load',
    () => _loadTopic(topicId, slug, force: force, postNumber: postNumber),
  );

  Future<void> _loadTopic(
    int topicId,
    String slug, {
    required bool force,
    int? postNumber,
  }) async {
    final instance = currentInstance;
    if (instance == null) return;
    if (instance.loginRequired && !instance.isConnected) return;
    final requestedPostNumber = postNumber ?? topicScrollPostNumber(topicId);
    final tabId = activeTabId;

    // Start presentation fetches before cache/in-flight guards so failures stay
    // retryable even for topics already in the store.
    unawaited(_presentation.ensureConfig(instance.url));
    unawaited(_presentation.ensureCustomEmojis(instance.url));
    // Hashtags need category colors even when a notification or link opened
    // the topic without first loading a feed.
    unawaited(
      _ensureCategoriesFor(
        instance,
        categoryId: store.read<TopicDetail>(instance.url, topicId)?.categoryId,
      ),
    );

    final key = _topicKey(instance.url, topicId);
    if (_topicsLoading.contains(key)) {
      if (force || requestedPostNumber != null) {
        _topicRefreshPending.add(key);
        if (requestedPostNumber != null) {
          _topicRefreshPostNumbers[key] = requestedPostNumber;
        }
      }
      return;
    }
    final held = store.read<TopicDetail>(instance.url, topicId);
    if (held != null) _ensureMessageListParent(instance.url, tabId, held);
    final heldResumePostNumber = held?.resumePostNumber;
    if (requestedPostNumber == null &&
        !force &&
        !_topicsStale.contains(key) &&
        heldResumePostNumber != null &&
        topicScrollPostNumber(topicId) == null) {
      final target = _targetCurrentTopicPost(heldResumePostNumber);
      if (target != null) {
        await _loadTopic(
          target.topicId,
          target.slug,
          force: false,
          postNumber: heldResumePostNumber,
        );
        return;
      }
    }
    if (held != null && !force && !_topicsStale.contains(key)) {
      final targetHeld = requestedPostNumber == null
          ? true
          : held.stream.any((id) {
              final post = store.read<Post>(instance.url, id);
              return post?.postNumber == requestedPostNumber;
            });
      if (targetHeld) {
        SurfaceOpeningTrace.mark('topic.cacheHit');
        // A link names its topic by a title spelled from the slug, and no read
        // follows to replace it with the one the site holds.
        if (_retitle(instance.url, topicId, held.title)) _notify();
        return;
      }
    }
    final lease = lifecycle.capture(instance.url);
    final elapsed = Stopwatch()..start();
    final prefetchKey = (
      siteUrl: instance.url,
      session: lease.session,
      topicId: topicId,
      postNumber: requestedPostNumber,
    );
    if (force || _topicsStale.contains(key)) {
      _topicPrefetch.discard(prefetchKey);
    }
    final prefetched = _topicPrefetch.take(prefetchKey);
    var bookmarkVersion = _bookmarkVersion(instance.url, topicId);
    var messageArchiveVersion = _messageArchiveVersion(instance.url, topicId);
    var postRemovalVersion = _topicPostRemovalVersion(instance.url, topicId);

    _topicsLoading.add(key);
    _notify();

    int? resumePostNumber;
    var replayRefresh = false;
    int? replayPostNumber;
    try {
      final credential = await _awaitTopicLoadStage(
        _readSessionValue(lease, () => credentials.apiKeyFor(instance.url)),
        elapsed,
        'reading credentials for topic $topicId',
      );
      if (credential == null || !lease.isCurrent) return;
      final warmed = prefetched == null
          ? null
          : await _awaitTopicLoadStage(
              prefetched,
              elapsed,
              'waiting for topic prefetch $topicId',
            );
      if (isDisposed || !lease.isCurrent) return;
      if (warmed != null) {
        SurfaceOpeningTrace.mark('topic.prefetchUsed');
        bookmarkVersion = warmed.bookmarkVersion;
        messageArchiveVersion = warmed.archiveVersion;
        postRemovalVersion = warmed.postRemovalVersion;
      }
      final fetched =
          warmed?.payload ??
          await _awaitTopicLoadStage<TopicPayload>(
            api.topicContent.topic(
              siteUrl: instance.url,
              slug: slug,
              id: topicId,
              postNumber: requestedPostNumber,
              apiKey: credential.value,
            ),
            elapsed,
            'loading topic $topicId',
          );
      if (isDisposed || !lease.isCurrent) return;
      SurfaceOpeningTrace.mark('topic.response');
      try {
        await _awaitTopicLoadStage(
          _ensureCategoryIds(instance, credential.value, [
            ?fetched.detail.categoryId,
            for (final source
                in fetched.detail.recommendations?.sources ??
                    const <TopicRecommendationSource>[])
              for (final topic in source.topics) ?topic.categoryId,
          ]),
          elapsed,
          'loading the category for topic $topicId',
        );
      } on TimeoutException catch (error, stackTrace) {
        if (isDisposed || !lease.isCurrent) return;
        _reportOperationalError(
          error,
          stackTrace,
          'topic.categories',
          severity: DiagnosticSeverity.warning,
        );
      }
      if (isDisposed || !lease.isCurrent) return;
      lease.commit(() {
        SurfaceOpeningTrace.mark('topic.publish');
        final detail = _absorb(
          instance.url,
          fetched,
          bookmarkVersionAtDispatch: bookmarkVersion,
          messageArchiveVersionAtDispatch: messageArchiveVersion,
          postRemovalVersionAtDispatch: postRemovalVersion,
          positioned: requestedPostNumber != null,
        );
        _ensureMessageListParent(instance.url, tabId, detail);
        if (requestedPostNumber == null &&
            currentInstance?.url == instance.url &&
            currentContent?.topicId == topicId &&
            topicScrollPostNumber(topicId) == null) {
          resumePostNumber = detail.resumePostNumber;
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'topic.load', degraded: false);
    } finally {
      lease.commit(() {
        _topicsLoading.remove(key);
        replayRefresh = _topicRefreshPending.remove(key);
        if (replayRefresh) {
          replayPostNumber = _topicRefreshPostNumbers.remove(key);
        }
        _notify();
      });
      if (replayRefresh && lease.isCurrent) {
        var replaySlug = '';
        final fallbackPostNumber = resumePostNumber;
        if (replayPostNumber == null && fallbackPostNumber != null) {
          final target = _targetCurrentTopicPost(fallbackPostNumber);
          if (target != null) {
            replayPostNumber = fallbackPostNumber;
            replaySlug = target.slug;
          }
        }
        unawaited(
          _refetchTopic(
            instance.url,
            topicId,
            replaySlug,
            postNumber: replayPostNumber,
          ),
        );
      }
    }

    final targetPostNumber = resumePostNumber;
    if (!replayRefresh && lease.isCurrent && targetPostNumber != null) {
      final target = _targetCurrentTopicPost(targetPostNumber);
      if (target != null) {
        await _loadTopic(
          target.topicId,
          target.slug,
          force: false,
          postNumber: targetPostNumber,
        );
      }
    }
  }

  void _ensureMessageListParent(
    String siteUrl,
    String? tabId,
    TopicDetail detail,
  ) {
    if (!detail.privateMessage) return;
    final workspace = _forumWorkspaces[siteUrl];
    final tab = workspace?.tabs.where((tab) => tab.id == tabId).firstOrNull;
    if (workspace == null ||
        tab == null ||
        tab.currentContent.topicId != detail.id) {
      return;
    }
    final parent = tab.contentStack.reversed
        .where((route) => !route.isTopic)
        .firstOrNull;
    if (parent?.isMessages == true) return;

    final messages = ContentRoute.messages();
    _putWorkspace(
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
      return ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: route.postNumber,
      );
    });
  }

  void _updateTopicRouteMetadata(
    String siteUrl,
    int topicId,
    String title,
    int? categoryId,
  ) {
    final category = categoryFor(categoryId, siteUrl: siteUrl);
    _rewriteTopicRoutes(siteUrl, topicId, (route) {
      return ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: category == null ? null : Color(category.colorValue),
        postNumber: route.postNumber,
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
    final workspace = _forumWorkspaces[siteUrl];
    if (workspace == null) return false;
    var changed = false;
    final tabs = <ForumTab>[];
    for (final tab in workspace.tabs) {
      final updated = tab.rewriteRoutes(rewrite);
      changed = changed || !identical(updated, tab);
      tabs.add(updated);
    }
    if (changed) _putWorkspace(workspace.copyWith(tabs: tabs));
    return changed;
  }

  /// Advances each time this reader takes a post out of a topic.
  final Map<String, int> _topicPostRemovalVersions = {};

  /// The removal version at which each removed post left its topic.
  final Map<String, Map<int, int>> _removedTopicPosts = {};

  int _topicPostRemovalVersion(String siteUrl, int topicId) =>
      _topicPostRemovalVersions[_topicKey(siteUrl, topicId)] ?? 0;

  /// Advances each time a stream read of a topic is stored.
  final Map<String, int> _topicStreamReadVersions = {};

  int _topicStreamReadVersion(String siteUrl, int topicId) =>
      _topicStreamReadVersions[_topicKey(siteUrl, topicId)] ?? 0;

  void _removeTopicPost(String siteUrl, int topicId, int postId) {
    final key = _topicKey(siteUrl, topicId);
    final version = _topicPostRemovalVersion(siteUrl, topicId) + 1;
    _topicPostRemovalVersions[key] = version;
    (_removedTopicPosts[key] ??= {})[postId] = version;
    store.remove<Post>(siteUrl, postId);
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.withoutPostId(postId),
    );
    // While summarizing, the window is read from the top replies stream, and
    // would otherwise end at the removed post.
    final summary = _topicSummaryStreams[key];
    if (summary != null && summary.contains(postId)) {
      _topicSummaryStreams[key] = List.unmodifiable([
        for (final id in summary)
          if (id != postId) id,
      ]);
    }
  }

  /// A stream read that left before a removal still carries the removed post.
  /// Stored, it would be back as a held post, which paging never reads again,
  /// and `TopicDetail.merge` keeps an omitted id that ends the stream, so the
  /// last post would stay for good. The rest of the read stands; a read that
  /// leaves after the removal, such as the one a recovery starts, restores
  /// the post.
  TopicPayload _withoutPostsRemovedSince(
    String siteUrl,
    TopicPayload payload,
    int? versionAtDispatch,
  ) {
    if (versionAtDispatch == null) return payload;
    final removed = _topicPostsRemovedSince(
      siteUrl,
      payload.detail.id,
      versionAtDispatch,
    );
    if (removed.isEmpty) return payload;
    return (
      detail: removed.fold(
        payload.detail,
        (detail, postId) => detail.withoutPostId(postId),
      ),
      posts: [
        for (final post in payload.posts)
          if (!removed.contains(post.id)) post,
      ],
    );
  }

  Set<int> _topicPostsRemovedSince(
    String siteUrl,
    int topicId,
    int versionAtDispatch,
  ) {
    if (versionAtDispatch == _topicPostRemovalVersion(siteUrl, topicId)) {
      return const {};
    }
    final removals =
        _removedTopicPosts[_topicKey(siteUrl, topicId)] ?? const {};
    return {
      for (final MapEntry(key: postId, value: version) in removals.entries)
        if (version > versionAtDispatch) postId,
    };
  }

  /// Stores a topic read. [positioned] says the read named the post the
  /// reader is going to.
  TopicDetail _absorb(
    String siteUrl,
    TopicPayload response, {
    int? bookmarkVersionAtDispatch,
    int? messageArchiveVersionAtDispatch,
    int? postRemovalVersionAtDispatch,
    bool positioned = false,
  }) {
    final payload = _withoutPostsRemovedSince(
      siteUrl,
      response,
      postRemovalVersionAtDispatch,
    );
    _topicStreamReadVersions.update(
      _topicKey(siteUrl, payload.detail.id),
      (version) => version + 1,
      ifAbsent: () => 1,
    );
    final preserveBookmarks =
        bookmarkVersionAtDispatch != null &&
        bookmarkVersionAtDispatch !=
            _bookmarkVersion(siteUrl, payload.detail.id);
    final heldDetail = store.read<TopicDetail>(siteUrl, payload.detail.id);
    final posts = preserveBookmarks
        ? [
            for (final incoming in payload.posts)
              switch (store.read<Post>(siteUrl, incoming.id)) {
                final held? => incoming.withBookmarkOf(held),
                null => incoming,
              },
          ]
        : payload.posts;
    store.putAll(siteUrl, posts);
    var incomingDetail = preserveBookmarks && heldDetail != null
        ? payload.detail.withBookmarksOf(heldDetail)
        : payload.detail;
    if (heldDetail != null &&
        messageArchiveVersionAtDispatch != null &&
        messageArchiveVersionAtDispatch !=
            _messageArchiveVersion(siteUrl, payload.detail.id)) {
      incomingDetail = incomingDetail.copyWith(
        messageArchived: heldDetail.messageArchived,
      );
    }
    var detail = store.put(siteUrl, incomingDetail);
    // A mega topic keeps its run over a read of another part of it
    // (TopicDetail.merge), but one that names a post is where the reader is
    // going: its page becomes the run.
    if (positioned && detail.isMegaTopic && incomingDetail.stream.isNotEmpty) {
      final run = detail.stream.toSet();
      if (!incomingDetail.stream.any(run.contains)) {
        store.update<TopicDetail>(
          siteUrl,
          detail.id,
          (held) => held.copyWith(stream: incomingDetail.stream),
        );
        detail = store.read<TopicDetail>(siteUrl, detail.id) ?? detail;
      }
    }
    _topicsStale.remove(_topicKey(siteUrl, detail.id));
    store.update<Topic>(
      siteUrl,
      detail.id,
      (row) => row
          .copyWith(
            title: detail.title,
            postsCount: detail.postsCount,
            bookmarked: detail.hasBookmarks,
          )
          .withPlugins(detail.plugins),
    );
    // Routes name the topic in its tab and header, so a read that brings a
    // rename, such as the reload a live `revised` message asks for, has to
    // reach them as well as the stored topic.
    _retitle(siteUrl, detail.id, detail.title);
    _armTopicPostHighlightIfLoaded();
    return detail;
  }

  Future<void> expandPostGap({
    required int anchorPostId,
    required bool before,
  }) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;

    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    final gap = (before ? detail.gapsBefore : detail.gapsAfter)[anchorPostId];
    if (gap == null || gap.isEmpty) return;

    final requestIds = gap.take(TopicDetail.maximumInitialPosts).toList();
    final key = (instance.url, topicId, anchorPostId, before);
    if (!_postGapsLoading.add(key)) return;
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final fetched = await api.topicContent.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: requestIds,
        apiKey: credential.value,
      );
      if (!lease.isCurrent) return;

      final requested = requestIds.toSet();
      final byId = <int, Post>{
        for (final post in fetched)
          if (requested.contains(post.id)) post.id: post,
      };
      final revealed = [
        for (final id in requestIds)
          if (byId.containsKey(id)) id,
      ];
      lease.commit(() {
        _putTopicPosts(instance.url, topicId, [
          for (final id in revealed) byId[id]!,
        ], bookmarkVersionAtDispatch: bookmarkVersion);
        store.update<TopicDetail>(
          instance.url,
          topicId,
          (held) => held.withExpandedGap(
            anchorPostId: anchorPostId,
            before: before,
            consumedIds: requestIds,
            revealedIds: revealed,
          ),
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.expandPostGap',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() => _postGapsLoading.remove(key));
    }
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
    _topicNotificationConfirmed.putIfAbsent(key, () => held.notificationLevel);
    final write = _QueuedTopicNotification(
      siteUrl: siteUrl,
      topicId: topicId,
      level: level,
      lease: lifecycle.capture(siteUrl),
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
          _topicNotificationConfirmed.remove(key);
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
      final credential = await _credentialForWrite(write.siteUrl);
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.failure != null) {
        _rollbackTopicNotification(key, write);
        write.complete(false);
        return;
      }
      final clientId = await authenticator.clientId();
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      await api.topicMutations.updateTopicNotificationLevel(
        siteUrl: write.siteUrl,
        apiKey: credential.apiKey!,
        topicId: write.topicId,
        notificationLevel: write.level,
        clientId: clientId,
      );
      if (!write.lease.isCurrent || isDisposed) {
        write.complete(false);
        return;
      }
      _topicNotificationConfirmed[key] = write.level;
      _projectTopicNotificationLevel(key, write, write.level);
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
    final confirmed = _topicNotificationConfirmed[key];
    if (confirmed == null) return;
    _projectTopicNotificationLevel(key, write, confirmed);
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
    final key = _topicKey(siteUrl, topicId);
    final write = _topicNotificationWrites[key];
    if (write != null &&
        !write.result.isCompleted &&
        _isLatestTopicNotification(key, write)) {
      // This may be an echo of an earlier serialized write. Keep the newest
      // choice visible, but use the server level if that choice is rejected.
      _topicNotificationConfirmed[key] = level;
      _projectTopicNotificationLevel(key, write, write.level);
    } else {
      _setTopicNotificationLevel(siteUrl, topicId, level, lease);
    }
  }

  static Map<String, Object?> _topicNotificationTrackingMessage(
    int topicId,
    TopicNotificationLevel level,
  ) => {
    'topic_id': topicId,
    'message_type': 'notification_level_change',
    'payload': {'notification_level': level.value},
  };

  void _setTopicNotificationLevel(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
    SiteLease lease,
  ) {
    if (!lease.isCurrent || isDisposed) return;
    final message = _topicNotificationTrackingMessage(topicId, level);
    if (_topicTrackingPendingEvents.containsKey(siteUrl) ||
        !_topicTrackingSnapshotsLoaded.contains(siteUrl)) {
      (_topicTrackingPendingEvents[siteUrl] ??= <Object?>[]).add(message);
    }
    // Patch the current row, never a captured snapshot or a made-up read
    // position. Do this before publishing to reentrant store listeners.
    if (_topicTrackingBySite[siteUrl]?.applyMessage(message) == true) {
      _topicTrackingRevisions.update(
        siteUrl,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
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
    final List<int>? indirectlyMuted;
    try {
      final credential = await _credentialForWrite(write.siteUrl);
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
      clientId = await authenticator.clientId();
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      indirectlyMuted = await api.categoryMutations
          .updateCategoryNotificationLevel(
            siteUrl: write.siteUrl,
            apiKey: apiKey,
            categoryId: write.categoryId,
            notificationLevel: write.level,
            clientId: clientId,
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
    final version =
        (_categoryNotificationPreferenceVersions[write.siteUrl] ?? 0) + 1;
    _categoryNotificationPreferenceVersions[write.siteUrl] = version;
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
    _topicTrackingLoads.add(write.siteUrl);
    _topicTrackingRetries.remove(write.siteUrl);
    _topicTrackingPendingEvents[write.siteUrl] = <Object?>[];
    unawaited(
      _loadTopicTrackingState(
        siteUrl: write.siteUrl,
        username: username,
        apiKey: apiKey,
        clientId: clientId,
        lease: write.lease,
        refreshCategoryPreferences:
            indirectlyMuted == null ||
                user?.followedCategoryIds == null ||
                user?.mutedCategoryIds == null
            ? () async {
                final response = await api.site.currentUser(
                  siteUrl: write.siteUrl,
                  apiKey: apiKey,
                  clientId: clientId,
                );
                if (!write.lease.isCurrent ||
                    isDisposed ||
                    _categoryNotificationPreferenceVersions[write.siteUrl] !=
                        version) {
                  return;
                }
                final held = _instanceAt(write.siteUrl)?.user;
                if (held == null ||
                    !plugins.models.sameCurrentUserAccount(held, response)) {
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
    _categorySidebarCache.remove(siteUrl);
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
    final siteUrl = write.siteUrl;
    final held = store.read<TopicCategory>(siteUrl, write.categoryId);
    if (held == null || held.notificationLevel == level) return;
    final category = held.withNotificationLevel(level);
    // Stage the cache before Store Ref listeners can select another level or
    // clear the account. No stale category snapshot may be merged afterwards.
    final byId = <int, TopicCategory>{
      for (final category
          in _categoriesBySite[siteUrl] ?? const <TopicCategory>[])
        category.id: category,
      category.id: category,
    };
    _categoriesBySite[siteUrl] = List.unmodifiable(byId.values);
    _categorySidebarCache.remove(siteUrl);
    store.put(siteUrl, category);
    if (write.lease.isCurrent && !isDisposed) _notify();
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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) {
        rollback();
        return failure.message;
      }
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.topicMutations.updateTopicPinForUser(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        pinned: pinned,
        clientId: clientId,
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
  final Map<String, int> _messageArchiveVersions = {};

  int _messageArchiveVersion(String siteUrl, int topicId) =>
      _messageArchiveVersions[_topicKey(siteUrl, topicId)] ?? 0;

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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      await api.topicMutations.updateMessageArchived(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        archived: archived,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return appL10n.theAccountHasChanged;
      _messageArchiveVersions[key] =
          _messageArchiveVersion(siteUrl, topicId) + 1;
      store.update<TopicDetail>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(messageArchived: archived),
      );
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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.topicMutations.updateTopicStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        status: status,
        enabled: enabled,
        clientId: clientId,
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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      if (deleted) {
        await api.topicMutations.deleteTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        );
      } else {
        await api.topicMutations.recoverTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        );
      }
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        _applyTopicDeletion(siteUrl, topicId, deleted);
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
  void _applyTopicDeletion(String siteUrl, int topicId, bool deleted) {
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return;
    final next = deleted
        ? held.afterDeletion(DateTime.now().toUtc())
        : held.afterRecovery();
    if (identical(next, held)) return;
    store.update<TopicDetail>(siteUrl, topicId, (_) => next);
    if (next.closed != held.closed) {
      store.update<Topic>(
        siteUrl,
        topicId,
        (row) => row.copyWith(closed: next.closed),
      );
    }
    if (!deleted) {
      // Only the server knows whether the recovered topic takes replies again.
      unawaited(_refetchTopic(siteUrl, topicId, ''));
      return;
    }
    // Site settings decide whether an author's deletion withdrew or trashed
    // the topic, and a deleter may no longer be allowed to read a trashed
    // one, so it is read when next opened rather than now.
    _rereadTopicWhenOpened(siteUrl, topicId);
  }

  /// Has [topicId] read again when it is next opened, after a write changed
  /// it on the server without answering with it. A read already on its way
  /// predates the write and is repeated.
  void _rereadTopicWhenOpened(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    if (_topicsLoading.contains(key)) {
      _topicRefreshPending.add(key);
    } else {
      _topicsStale.add(key);
    }
  }

  void _putTopicPosts(
    String siteUrl,
    int topicId,
    Iterable<Post> incoming, {
    required int bookmarkVersionAtDispatch,
  }) {
    final preserveBookmarks =
        bookmarkVersionAtDispatch != _bookmarkVersion(siteUrl, topicId);
    store.putAll(
      siteUrl,
      preserveBookmarks
          ? [
              for (final post in incoming)
                switch (store.read<Post>(siteUrl, post.id)) {
                  final held? => post.withBookmarkOf(held),
                  null => post,
                },
            ]
          : incoming,
    );
  }

  /// A page that leaves out a post it asked for is answered by a site that no
  /// longer serves that post to this reader: deleted, moved or made a whisper
  /// since the stream was read. The loaded window ends at the first post it
  /// does not hold, so kept, the id would stop paging there for good; the web
  /// client steps over it instead. A stream read stored since the page left,
  /// or still out, may carry a recovery the page predates, and settles the
  /// stream itself.
  void _removeOmittedTopicPosts(
    String siteUrl,
    int topicId,
    List<int> requested,
    Iterable<Post> answered, {
    required int streamReadVersionAtDispatch,
  }) {
    if (streamReadVersionAtDispatch !=
            _topicStreamReadVersion(siteUrl, topicId) ||
        _topicsLoading.contains(_topicKey(siteUrl, topicId))) {
      return;
    }
    final stream = store.read<TopicDetail>(siteUrl, topicId)?.stream;
    if (stream == null) return;
    final served = {for (final post in answered) post.id};
    for (final id in requested) {
      if (!served.contains(id) &&
          stream.contains(id) &&
          store.read<Post>(siteUrl, id) == null) {
        _removeTopicPost(siteUrl, topicId, id);
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
      if (_topicTrackingBySite[siteUrl]?.markRead(topicId, position) == true) {
        _topicTrackingRevisions.update(
          siteUrl,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      if (currentInstance?.url == siteUrl) _notifyLiveChange();
    }
    return receipt;
  }

  Future<void> loadMorePosts({int batchSize = 20, String? tabId}) async {
    final instance = currentInstance;
    final route = tabId == null
        ? currentContent
        : currentWorkspace?.tabById(tabId)?.currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null) return;

    final key = _topicKey(instance.url, topicId);
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    if (_postsLoading.contains(key)) return;

    final boundedBatch = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = readTab(tabId, () => _pendingPostIds(instance.url, detail));
    if (pending.isEmpty) {
      final edge = readTab(tabId, () => _currentMegaTopicEdge(newer: true));
      if (edge != null) {
        await _loadMegaTopicPage(instance.url, detail, edge, newer: true);
      }
      return;
    }
    final requestIds = pending.take(boundedBatch).toList();
    // Recommendations are dynamic: resolve them only at the final window and
    // never replace an existing snapshot with a later empty response.
    final resolveRecommendations =
        detail.recommendations == null && requestIds.length == pending.length;
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);
    final streamReadVersion = _topicStreamReadVersion(instance.url, topicId);

    _postsLoading.add(key);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final page = resolveRecommendations
          ? await api.topicContent.topicPosts(
              siteUrl: instance.url,
              topicId: topicId,
              ids: requestIds,
              apiKey: credential.value,
            )
          : (
              posts: await api.topicContent.posts(
                siteUrl: instance.url,
                topicId: topicId,
                ids: requestIds,
                apiKey: credential.value,
              ),
              recommendations: null,
            );
      lease.commit(() {
        _putTopicPosts(
          instance.url,
          topicId,
          page.posts,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        _removeOmittedTopicPosts(
          instance.url,
          topicId,
          requestIds,
          page.posts,
          streamReadVersionAtDispatch: streamReadVersion,
        );
        if (page.recommendations case final recommendations?) {
          store.update<TopicDetail>(
            instance.url,
            topicId,
            // A topic refetch may have supplied a snapshot while this post
            // page was in flight. Paging only fills an unresolved value; it
            // never replaces a recommendation set that arrived later.
            (detail) => detail.recommendations == null
                ? detail.withRecommendations(recommendations)
                : detail,
          );
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.loadMorePosts',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() {
        _postsLoading.remove(key);
        _notify();
      });
    }
  }

  Future<void> loadEarlierPosts({int batchSize = 20, String? tabId}) async {
    final instance = currentInstance;
    final route = tabId == null
        ? currentContent
        : currentWorkspace?.tabById(tabId)?.currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null) return;

    final key = _topicKey(instance.url, topicId);
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    if (_earlierPostsLoading.contains(key)) return;

    final boundedBatch = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = readTab(
      tabId,
      () => _pendingEarlierPostIds(instance.url, detail, boundedBatch),
    );
    if (pending.isEmpty) {
      final edge = readTab(tabId, () => _currentMegaTopicEdge(newer: false));
      if (edge != null) {
        await _loadMegaTopicPage(instance.url, detail, edge, newer: false);
      }
      return;
    }
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);
    final streamReadVersion = _topicStreamReadVersion(instance.url, topicId);

    _earlierPostsLoading.add(key);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final posts = await api.topicContent.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: pending,
        apiKey: credential.value,
      );
      lease.commit(() {
        _putTopicPosts(
          instance.url,
          topicId,
          posts,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        _removeOmittedTopicPosts(
          instance.url,
          topicId,
          pending,
          posts,
          streamReadVersionAtDispatch: streamReadVersion,
        );
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.loadEarlierPosts',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() {
        _earlierPostsLoading.remove(key);
        _notify();
      });
    }
  }

  /// Reads the page of a mega topic past [edge] of its run by post number,
  /// the newer side when [newer], under the loading flag of the page by ids
  /// it stands in for.
  Future<void> _loadMegaTopicPage(
    String siteUrl,
    TopicDetail detail,
    Post edge, {
    required bool newer,
  }) async {
    final topicId = detail.id;
    final key = _topicKey(siteUrl, topicId);
    final loading = newer ? _postsLoading : _earlierPostsLoading;
    final lease = lifecycle.capture(siteUrl);
    final bookmarkVersion = _bookmarkVersion(siteUrl, topicId);
    final removalVersion = _topicPostRemovalVersion(siteUrl, topicId);

    loading.add(key);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final posts = await api.topicContent.postsFromNumber(
        siteUrl: siteUrl,
        topicId: topicId,
        postNumber: edge.postNumber,
        ascending: newer,
        apiKey: credential.value,
      );
      lease.commit(() {
        // Paged in, a post this reader took out while the page was out would
        // be back in the run for good.
        final removed = _topicPostsRemovedSince(
          siteUrl,
          topicId,
          removalVersion,
        );
        final page = [
          for (final post in posts)
            if (!removed.contains(post.id) &&
                (newer
                    ? post.postNumber > edge.postNumber
                    : post.postNumber < edge.postNumber))
              post,
        ];
        _putTopicPosts(
          siteUrl,
          topicId,
          page,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (held) => held.withMegaTopicPage(
            anchorPostId: edge.id,
            newer: newer,
            postIds: [for (final post in page) post.id],
            lastPostIdAtDispatch: detail.lastPostId,
          ),
        );
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        newer ? 'topic.loadMorePosts' : 'topic.loadEarlierPosts',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() {
        loading.remove(key);
        _notify();
      });
    }
  }

  bool get loadingMorePosts {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _postsLoading.contains(_topicKey(instance.url, topicId));
  }

  bool get loadingEarlierPosts {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _earlierPostsLoading.contains(_topicKey(instance.url, topicId));
  }

  Future<String?> toggleTopicSummary() async {
    final instance = currentInstance;
    final topic = currentTopic;
    if (instance == null || topic == null || !topic.hasSummary) return null;

    final key = _topicKey(instance.url, topic.id);
    if (_topicSummaryStreams.remove(key) != null) {
      _notify();
      return null;
    }
    if (!_topicSummariesLoading.add(key)) return null;
    final lease = lifecycle.capture(instance.url);
    final postRemovalVersion = _topicPostRemovalVersion(instance.url, topic.id);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return null;
      final response = await api.topicContent.topic(
        siteUrl: instance.url,
        slug: currentContent?.slug ?? '',
        id: topic.id,
        summary: true,
        apiKey: credential.value,
      );
      lease.commit(() {
        final payload = _withoutPostsRemovedSince(
          instance.url,
          response,
          postRemovalVersion,
        );
        store.putAll(instance.url, payload.posts);
        _topicSummaryStreams[key] = List.unmodifiable(payload.detail.stream);
      });
      return null;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.loadSummary',
          severity: DiagnosticSeverity.warning,
        );
      }
      return appL10n.couldnTLoadThisTopicSSummary;
    } finally {
      lease.commit(() {
        _topicSummariesLoading.remove(key);
        _notify();
      });
    }
  }

  final Map<String, ComposerController> _composers = {};
  // Creation results belong to the submitting tab, even if navigation changes
  // while the request or its reconciliation is in flight.
  final Expando<String> _composerSubmissionTabs = Expando();

  // Commands target the selected forum; async continuations keep the exact
  // composer that started them even if the user changes forums or drafts.
  ComposerController? get _composer {
    final instance = currentInstance;
    if (instance == null) return null;
    return _composers[instance.url];
  }

  void _setComposer(ComposerController composer) {
    SurfaceOpeningTrace.mark('composer.publish');
    final target = composer.target;
    _composers[target.siteUrl] = composer;
  }

  bool _ownsComposer(ComposerController? composer) {
    if (composer == null) return false;
    final target = composer.target;
    return identical(_composers[target.siteUrl], composer);
  }

  void _removeComposer(ComposerController composer) {
    if (!_ownsComposer(composer)) return;
    final target = composer.target;
    _composers.remove(target.siteUrl);
    _composerDrafts.detach(composer);
  }

  Iterable<ComposerController> _composersForSite(String siteUrl) =>
      _composers.values.where((composer) => composer.target.siteUrl == siteUrl);

  /// Each forum retains one active composer independently of its tabs.
  Iterable<ComposerController> get liveComposers =>
      List.unmodifiable(_composers.values);

  // Reported after every frame the reader moves; kept off the facade so a
  // resize or dock drag does not re-run every shell selector.
  final _readerContentBounds = FrameSafeValueNotifier<Rect?>(null);

  late final ComposerDraftCoordinator _composerDrafts =
      ComposerDraftCoordinator(
        localStore: drafts,
        persistence: api.composerPersistence,
        draftsApi: api.drafts,
        lifecycle: lifecycle,
        readCredential: _credentialForWrite,
        readClientId: authenticator.clientId,
        isDisposed: () => isDisposed,
        isCurrentComposer: _ownsComposer,
        readCachedDraft: (target) => target.createsTopic
            ? null
            : store.read<TopicDetail>(target.siteUrl, target.topicId)?.draft,
        readCachedSequence: (target) => target.createsTopic
            ? 0
            : store
                      .read<TopicDetail>(target.siteUrl, target.topicId)
                      ?.draftSequence ??
                  0,
        writeCachedDraft: (target, draft, sequence) {
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
            (!target.createsTopic &&
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

  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

  ComposerController _buildTextComposer(
    ComposerTarget target, {
    bool persistsDraft = false,
    int minimumRequiredTags = 0,
  }) {
    SurfaceOpeningTrace.mark('composer.create');
    final config = siteConfigFor(target.siteUrl);
    final draftSession = persistsDraft
        ? _composerDrafts.openSession(target)
        : null;
    ComposerPluginState readPluginState() {
      final currentUser = currentUserFor(target.siteUrl);
      final freshCurrentUser = freshCurrentUserFor(target.siteUrl);
      final editingPostId = target.editingPostId;
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
        editingPostNumber: target.editingPostNumber ?? editingPost?.postNumber,
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
              target.policy?.emojiUsageContext ?? CoreEmojiUsageContexts.topic,
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
      imageUploader: !(target.policy?.uploadsEnabled ?? true)
          ? null
          : (file, {required onProgress, required abortTrigger}) =>
                _uploadComposerImage(
                  target,
                  file,
                  onProgress: onProgress,
                  abortTrigger: abortTrigger,
                ),
      prepareUpload: (file, {required abortTrigger}) =>
          ComposerImageOptimizer().prepare(
            file,
            settings: config.composerImageOptimization,
            canUpload: (filename) => config.canUploadImage(
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
      ComposerTarget.plugin(
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

    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: appL10n.newMessage,
      mode: ComposerMode.privateMessage,
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
      _mergeCategories(instance.url, [selectedCategory]);
    }
    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: appL10n.newTopic,
      mode: ComposerMode.newTopic,
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
      if (!_categorised.contains(siteUrl)) loadCategories(siteUrl),
    ]);
    if (!isCurrent()) return;

    String? apiKey;
    var apiKeyRead = false;
    Future<String?> readApiKey() async {
      if (apiKeyRead) return apiKey;
      apiKeyRead = true;
      final credential = await _credentialForWrite(siteUrl);
      if (!isCurrent() || credential.failure != null) return null;
      return apiKey = credential.apiKey;
    }

    final loadedCategory = categoryFor(categoryId, siteUrl: siteUrl);
    final stillHasPlaceholder =
        placeholderCategory != null &&
        identical(loadedCategory, placeholderCategory);
    if (categoryId != null && (loadedCategory == null || stillHasPlaceholder)) {
      final key = await readApiKey();
      if (!isCurrent()) return;
      if (key != null) {
        try {
          final found = await api.categories.findCategories(
            siteUrl: siteUrl,
            ids: [categoryId],
            apiKey: key,
          );
          if (!isCurrent()) return;
          if (found.isNotEmpty) {
            _mergeCategories(siteUrl, found);
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
      final key = await readApiKey();
      if (!isCurrent()) return;
      if (key != null) {
        try {
          final result = await api.topicComposerQueries.searchTopicTags(
            siteUrl: siteUrl,
            apiKey: key,
            term: link!.slug,
            categoryId: categoryId,
          );
          if (!isCurrent()) return;
          final exact = result.results.where(
            (tag) =>
                tag.id == link.id ||
                tag.name.toLowerCase() == link.slug.toLowerCase() ||
                tag.slug?.toLowerCase() == link.slug.toLowerCase(),
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
      target = ComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicId: 0,
        slug: '',
        topicTitle: appL10n.newMessage,
        mode: ComposerMode.privateMessage,
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
      target = ComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicId: 0,
        slug: '',
        topicTitle: appL10n.newTopic,
        mode: ComposerMode.newTopic,
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
        currentContent?.id != sourceRouteId ||
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
          currentContent?.id != sourceRouteId ||
          !sourceIsCurrent() ||
          activeTabId != tabId ||
          currentFeedId != feedId) {
        return OpenComposerResult.sourceChanged;
      }
      if (!_replaceComposer()) return OpenComposerResult.unavailable;
      final target = ComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicId: 0,
        slug: '',
        topicTitle: appL10n.newTopic,
        mode: ComposerMode.newTopic,
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
        currentContent?.id != sourceRouteId ||
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
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(target.siteUrl),
    );
    if (held == null || !lease.isCurrent || !_ownsComposer(composer)) {
      return const TopicTagSearch();
    }
    if (held.value.failure case final failure?) {
      throw failure;
    }
    return api.topicComposerQueries.searchTopicTags(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      categoryId: composer.categoryId,
      selectedTagIds: composer.tags.map((tag) => tag.id).whereType<int>(),
      // Core rejects a page larger than the site's own setting outright, so
      // the site sets this and the client only caps what it will render.
      limit: siteConfigFor(
        target.siteUrl,
      ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
    );
  }

  Future<TopicTagSearch> searchTopicTagsForEditor({
    required String siteUrl,
    required int? categoryId,
    required Iterable<TopicTag> selectedTags,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(siteUrl),
    );
    if (held == null || !lease.isCurrent) return const TopicTagSearch();
    if (held.value.failure case final failure?) throw failure;
    return api.topicComposerQueries.searchTopicTags(
      siteUrl: siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      categoryId: categoryId,
      selectedTagIds: selectedTags.map((tag) => tag.id).whereType<int>(),
      limit: siteConfigFor(
        siteUrl,
      ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
    );
  }

  Future<List<TopicCategory>> searchTopicCategoriesForEditor({
    required String siteUrl,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(siteUrl),
    );
    if (held == null || !lease.isCurrent) return const [];
    if (held.value.failure case final failure?) throw failure;

    final categories = await api.categories.searchCategories(
      siteUrl: siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      includeUncategorized: siteConfigFor(siteUrl).allowUncategorizedTopics,
    );
    if (!lease.isCurrent) return const [];
    lease.commit(() {
      _mergeCategories(siteUrl, categories);
      _notify();
    });
    return categories;
  }

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
  }) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !canReplyHere) return;
    final targetsWhisper =
        replyingToWhisper ?? _replyTargetsWhisper(replyToPostNumber);

    final existing = _composer;
    if (existing?.discarding == true) return;
    if (existing != null &&
        !existing.closing &&
        !existing.target.isEdit &&
        existing.target.topicId == topicId &&
        existing.target.siteUrl == instance.url) {
      existing.retarget(
        replyToPostNumber: replyToPostNumber,
        replyToUsername: replyToUsername,
        replyingToWhisper: targetsWhisper,
      );
      existing.focus.requestFocus();
      return;
    }

    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: currentTopic?.title ?? route?.title ?? '',
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper: targetsWhisper,
      privateMessageTopic: currentTopic?.privateMessage ?? false,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _setComposer(composer);
    _notify();

    _composerDrafts.startRestore(composer, listedDraft: listedDraft);
  }

  bool _replyTargetsWhisper(int? postNumber) {
    if (postNumber == null) return false;
    final instance = currentInstance;
    final topic = currentTopic;
    if (instance == null || topic == null) return false;
    for (final postId in topic.stream) {
      final post = store.read<Post>(instance.url, postId);
      if (post?.postNumber == postNumber) return post!.isWhisper;
    }
    return false;
  }

  Future<void> openQuote(Post post, String quote) async {
    final sourceTabId = activeTabId;
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null ||
        topicId == null ||
        !canReplyHere ||
        quote.trim().isEmpty) {
      return;
    }

    var composer = _composer;
    final reusesOpenReply =
        composer != null &&
        !composer.target.isEdit &&
        !composer.target.createsTopic &&
        !composer.target.isPlugin &&
        composer.target.topicId == topicId &&
        composer.target.siteUrl == instance.url;

    if (!reusesOpenReply) {
      openReply(
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
        currentContent?.topicId != topicId ||
        activeTabId != sourceTabId) {
      return;
    }
    if (!composer.insertBlock(expectedValue: composer.value, markdown: quote)) {
      return;
    }
    composer.focus.requestFocus();
  }

  void openEdit(Post post, {String? focusText}) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !post.canEdit) return;
    unawaited(_ensureTopicComposerCapabilities(instance.url));

    if (!_replaceComposer()) return;
    final detail = currentTopic;
    final editsTopic = post.postNumber == 1 && detail?.canEdit == true;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      // The site rejects a topic edit whose `original_title` is not the title
      // it holds, which is the stored topic's; a route can still carry the
      // title a link spelled from its slug until a read replaces it.
      topicTitle: detail?.title ?? route?.title ?? '',
      editingPostId: post.id,
      editingPostNumber: post.postNumber,
      mode: editsTopic ? ComposerMode.topicEdit : ComposerMode.postEdit,
      initialCategoryId: editsTopic ? detail?.categoryId : null,
      initialTags: editsTopic ? detail?.tags ?? const [] : const [],
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

    final key = _postKey(siteUrl, post.id);
    final lease = lifecycle.capture(siteUrl);
    if (!_beginPostWrite(key)) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent ||
          !_fastEditContextCurrent(siteUrl, topicId, post.id)) {
        return appL10n.theTopicChangedBeforeTheEditCouldBeSaved;
      }
      if (credential.failure case final failure?) return failure.message;

      final fetched = await api.topicContent.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [post.id],
        includeRaw: true,
        apiKey: credential.apiKey!,
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

      final updated = await api.composerPersistence.updatePost(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        postId: post.id,
        raw: nextRaw,
        originalText: raw,
      );
      if (!lease.isCurrent ||
          !_fastEditContextCurrent(siteUrl, topicId, post.id)) {
        return appL10n.theTopicChangedBeforeTheEditCouldBeSaved;
      }
      lease.commit(() {
        _storeEditedPost(siteUrl, updated, raw: nextRaw);
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
      lease.commit(() => _endPostWrite(siteUrl, post.id));
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
  }) async {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail?.canEdit != true) {
      return appL10n.thisTopicCanNoLongerBeEdited;
    }
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) return appL10n.aTopicTitleIsRequired;
    if (nextTitle == detail!.title.trim()) return null;

    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheTitleSaved;
    if (credential.failure case final failure?) return failure.message;

    final TopicUpdate update;
    try {
      update = await api.topicMutations.updateTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        title: nextTitle,
        originalTitle: detail.title,
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
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheCategorySaved;
    if (credential.failure case final failure?) return failure.message;

    final tags = await _tagsAllowedInCategory(
      siteUrl: siteUrl,
      apiKey: credential.apiKey!,
      categoryId: categoryId,
      selected: detail.tags,
    );
    if (!lease.isCurrent) return appL10n.theForumChangedBeforeTheCategorySaved;

    final TopicUpdate update;
    try {
      update = await api.topicMutations.updateTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        title: detail.title,
        originalTitle: detail.title,
        categoryId: categoryId,
        tags: tags,
        originalTags: detail.tags,
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
    required String apiKey,
    required int categoryId,
    required List<TopicTag> selected,
  }) async {
    if (selected.isEmpty) return selected;
    final kept = <TopicTag>[];
    for (final tag in selected) {
      try {
        final result = await api.topicComposerQueries.searchTopicTags(
          siteUrl: siteUrl,
          apiKey: apiKey,
          term: tag.name,
          categoryId: categoryId,
          selectedTagIds: selected.map((item) => item.id).whereType<int>(),
          limit: siteConfigFor(
            siteUrl,
          ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
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

  void openTagsEdit() {
    final instance = currentInstance;
    final route = currentContent;
    final detail = currentTopic;
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
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: route!.topicId!,
      slug: route.slug ?? '',
      topicTitle: detail.title,
      editingPostId: heldFirstPost ? firstId : null,
      editingPostNumber: 1,
      mode: ComposerMode.tagsEdit,
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
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return appL10n.theSiteChangedBeforeTagsWereSaved;
    if (credential.failure case final failure?) return failure.message;
    try {
      await api.topicMutations.updateTopicTags(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        tags: next,
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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || credential.failure != null) return;
      final capabilities = await api.topicComposerQueries
          .topicComposerCapabilities(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
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

    final mentionTopicId = target.isPlugin
        ? target.policy!.mentionTopicId
        : target.topicId;
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
    if (post.raw case final raw?) {
      composer.loadedBody(raw, caretOffset: _editCaretOffset(raw, focusText));
      return;
    }

    composer.beginLoadingBody();
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(target.siteUrl),
      );
      if (credential == null || !lease.isCurrent || !_ownsComposer(composer)) {
        return;
      }
      final fetched = await api.topicContent.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: [post.id],
        includeRaw: true,
        apiKey: credential.value,
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
    final credential = await _credentialForWrite(siteUrl);
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
      final results = await api.search.searchPosts(
        siteUrl: siteUrl,
        term: trimmed,
        typeFilter: target.privateMessage ? 'private_messages' : 'topic',
        searchForId: true,
        restrictToArchetype: target.privateMessage
            ? 'private_message'
            : 'regular',
        apiKey: credential.apiKey,
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
        () => _rereadTopicWhenOpened(siteUrl, destinationTopicId),
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
    if (!_beginPostWrite(_postKey(siteUrl, postId))) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // The write guard notifies listeners. Recheck the opening account and
      // current target records both there and after acquiring credentials.
      if (refusal() case final error?) return error;
      final credential = await _credentialForWrite(siteUrl);
      if (refusal() case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      await api.postMutations.changePostOwners(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: target.topicId,
        postIds: [postId],
        username: trimmedUsername,
      );
      if (!_ownsTopicPostOwnerTarget(target)) return _obsoleteTopicPostOwner;
      await _refreshPost(
        siteUrl,
        target.topicId,
        postId,
        credential.apiKey,
        lease,
      );
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
      lease.commit(() => _endPostWrite(siteUrl, postId));
    }
  }

  Future<String?> deletePost(Post post) async {
    if (!post.canDelete) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null &&
        _postWritesInFlight.containsKey(_postKey(siteUrl, post.id))) {
      return null;
    }
    final editing = _composer?.target.editingPostId == post.id
        ? _composer
        : null;

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
      final credential = await _credentialForWrite(target.siteUrl);
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      final result = await api.postMutations.checkPermanentPostDeletion(
        siteUrl: target.siteUrl,
        apiKey: credential.apiKey!,
        postId: target.postId,
        clientId: clientId,
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
    if (target.deletesTopic) {
      if (!_topicDeletionWrites.add(topicKey)) {
        return appL10n.anotherTopicActionIsStillFinishing;
      }
      _notify();
    } else if (!_beginPostWrite(_postKey(siteUrl, postId))) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // The write guard notifies listeners. Retain the opening account even
      // if a listener replaces it before credentials are read.
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      final credential = await _credentialForWrite(siteUrl);
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      if (!target.deletesTopic) {
        await api.postMutations.permanentlyDeletePost(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          postId: postId,
        );
        if (!lease.isCurrent || isDisposed) {
          return _obsoletePermanentPostDeletion;
        }
        await _refreshPost(siteUrl, topicId, postId, credential.apiKey, lease);
        return lease.isCurrent && !isDisposed
            ? null
            : _obsoletePermanentPostDeletion;
      }

      final clientId = await authenticator.clientId();
      if (_permanentPostDeletionRefusal(target) case final error?) return error;
      final topic = store.read<TopicDetail>(siteUrl, topicId)!;
      await api.topicMutations.permanentlyDeleteTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }
      lease.commit(() {
        for (final postId in topic.stream) {
          store.remove<Post>(siteUrl, postId);
        }
        store.remove<TopicDetail>(siteUrl, topicId);
        store.remove<Topic>(siteUrl, topicId);
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
          _endPostWrite(siteUrl, postId);
        }
      });
    }
  }

  Future<String?> recoverPost(Post post) async {
    if (!post.canRecover) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null &&
        _postWritesInFlight.containsKey(_postKey(siteUrl, post.id))) {
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
          ? (siteUrl, topicId) => _applyTopicDeletion(siteUrl, topicId, false)
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
    final trimmed = notice?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (next == store.read<Post>(siteUrl, postId)?.notice?.raw) return null;
    if (!_beginPostWrite(_postKey(siteUrl, postId))) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }

    try {
      // Acquiring the write guard notifies listeners, which may retire the
      // opening account. Keep that lease through credential reads and refresh.
      if (_postNoticeRefusal(target) case final error?) return error;
      final credential = await _credentialForWrite(siteUrl);
      if (_postNoticeRefusal(target) case final error?) return error;
      if (credential.failure case final failure?) return failure.message;
      if (next == store.read<Post>(siteUrl, postId)?.notice?.raw) return null;

      await api.postMutations.updatePostNotice(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        postId: postId,
        notice: next,
      );
      if (!lease.isCurrent) return _obsoletePostNotice;
      await _refreshPost(
        siteUrl,
        target.topicId,
        postId,
        credential.apiKey,
        lease,
      );
      return lease.isCurrent ? null : _obsoletePostNotice;
    } on WriteException catch (error) {
      return lease.isCurrent ? error.message : _obsoletePostNotice;
    } catch (error, stackTrace) {
      if (!lease.isCurrent) return _obsoletePostNotice;
      _reportOperationalError(error, stackTrace, 'post.setNotice');
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() => _endPostWrite(siteUrl, postId));
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

    final key = _postKey(siteUrl, held.id);
    final lease = lifecycle.capture(siteUrl);
    if (!_beginPostWrite(key)) {
      return appL10n.anotherActionOnThisPostIsStillBeingSaved;
    }
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        final fresh = await api.postMutations.createPostFlag(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          postId: held.id,
          postActionTypeId: currentType.id,
          message: submittedMessage,
        );
        if (!lease.isCurrent) {
          return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
        }
        lease.commit(() {
          final current = store.read<Post>(siteUrl, fresh.id);
          store.put(
            siteUrl,
            current == null ? fresh : fresh.withBookmarkOf(current),
          );
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
      lease.commit(() => _endPostWrite(siteUrl, held.id));
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
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        await api.postMutations.createTopicFlag(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: held.id,
          postActionTypeId: currentType.id,
          message: submittedMessage,
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
        !_postBookmarkWritesInFlight.contains(key)) {
      return appL10n.anotherPostActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    String? apiKey;
    late final PostChecklistWrite operation;
    operation = PostChecklistWrite(
      post: held,
      isCurrent: () =>
          lease.isCurrent && identical(_postChecklistWrites[key], operation),
      publish: (previous, next) {
        final current = store.read<Post>(siteUrl, post.id);
        if (current == null ||
            current.cooked != previous.cooked ||
            current.version != previous.version ||
            current.updatedAt != previous.updatedAt ||
            current.canEdit != previous.canEdit ||
            current.isLocalized != previous.isLocalized ||
            current.isDeleted != previous.isDeleted) {
          return false;
        }
        store.put(
          siteUrl,
          current.copyWith(
            cooked: next.cooked,
            raw: next.raw,
            updatedAt: next.updatedAt,
            version: next.version,
            canEdit: next.canEdit,
            isLocalized: next.isLocalized,
          ),
        );
        _notify();
        return true;
      },
      load: () async {
        final posts = await api.topicContent.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: [post.id],
          includeRaw: true,
          apiKey: apiKey,
        );
        final fresh = posts.where((item) => item.id == post.id).firstOrNull;
        if (fresh == null || fresh.raw == null || fresh.updatedAt == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
        return fresh;
      },
      save: (baseline, toggles) => api.postMutations.togglePostChecklist(
        siteUrl: siteUrl,
        apiKey: apiKey!,
        postId: post.id,
        toggles: toggles,
        expectedRaw: baseline.raw!,
        expectedUpdatedAt: baseline.updatedAt!,
        mutationId:
            'native-${DateTime.now().microsecondsSinceEpoch}-${_checklistMutationSequence++}',
      ),
    );
    _postChecklistWrites[key] = operation;
    _holdPostWrite(key);
    try {
      if (!operation.toggle(post, target, checked)) return null;
      if (!lease.isCurrent) return null;
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) {
        operation.reject();
        return failure.message;
      }
      apiKey = credential.apiKey!;
      return await operation.run();
    } finally {
      if (identical(_postChecklistWrites[key], operation)) {
        _postChecklistWrites.remove(key);
      }
      lease.commit(() => _endPostWrite(siteUrl, post.id));
    }
  }

  Future<String?> toggleLike(Post post, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || !post.canToggleLike) return null;

    final key = _postKey(targetSite, post.id);
    // One at a time per post. Without this a double tap sends a like and an
    // undo at once — the second reads the guess the first just wrote — and
    // whichever answer lands last decides what is drawn, which is not
    // necessarily the one the site ended up believing.
    final lease = lifecycle.capture(targetSite);
    if (!_beginPostWrite(key)) return null;

    try {
      return await _writeLike(targetSite, post, lease);
    } finally {
      lease.commit(() => _endPostWrite(targetSite, post.id));
    }
  }

  Future<String?> _writeLike(String siteUrl, Post post, SiteLease lease) async {
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return null;
    if (credential.failure case final failure?) return failure.message;
    final apiKey = credential.apiKey!;

    final liked = !post.liked;
    // Apply the guess to the current store value: a re-read can land during
    // credential lookup, and a 204 response will not correct a stale put.
    final applied = lease.commit(() {
      store.update<Post>(siteUrl, post.id, (held) => held.withLike(liked));
      _notify();
    });
    if (!applied || !lease.isCurrent) return null;

    void revert() {
      lease.commit(() {
        // Undo only this reader's own guess, and only where it still stands.
        // A re-read that landed during the request already carries the
        // site's count; the tap-time snapshot would rewind other readers'
        // likes with it.
        store.update<Post>(
          siteUrl,
          post.id,
          (held) => held.liked == liked ? held.withLike(post.liked) : held,
        );
        _notify();
      });
    }

    try {
      final fresh = liked
          ? await api.postMutations.likePost(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: post.id,
            )
          : await api.postMutations.unlikePost(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: post.id,
            );
      // A route that answered with nothing still did the thing it was asked to
      // — the guess above stands until the post is read again.
      if (fresh != null) {
        lease.commit(() {
          final held = store.read<Post>(siteUrl, fresh.id);
          store.put(siteUrl, held == null ? fresh : fresh.withBookmarkOf(held));
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
        _postWritesInFlight.containsKey(_postKey(targetSite, postId));
  }

  final Map<String, int> _postWritesInFlight = {};
  final Set<String> _postBookmarkWritesInFlight = {};
  final Map<String, Set<int>> _topicPostSelections = {};
  final Set<String> _topicPostSelectionWrites = {};
  final Set<String> _topicFlagWrites = {};

  final Set<String> _topicBookmarkWritesInFlight = {};
  final Set<String> _pluginBookmarkWritesInFlight = {};
  final Map<BookmarkTargetType, _ShellCoreBookmarkTargetHost>
  _coreBookmarkTargetHosts = {};
  final Map<BookmarkTargetType, _ShellPluginBookmarkTargetHost>
  _pluginBookmarkTargetHosts = {};
  final Map<String, int> _bookmarkVersions = {};
  final Map<String, int> _siteBookmarkVersions = {};

  @override
  BookmarkTargetHost bookmarkTarget(BookmarkTargetType targetType) {
    if (targetType != BookmarkTargetType.post &&
        targetType != BookmarkTargetType.topic) {
      throw ArgumentError.value(
        targetType,
        'targetType',
        'Plugin bookmark targets require a plugin-scoped host.',
      );
    }
    return _coreBookmarkTargetHosts.putIfAbsent(
      targetType,
      () => _ShellCoreBookmarkTargetHost(this, targetType),
    );
  }

  _ShellPluginBookmarkTargetHost _pluginBookmarkTargetHost(
    BookmarkTargetType targetType,
  ) => _pluginBookmarkTargetHosts.putIfAbsent(
    targetType,
    () => _ShellPluginBookmarkTargetHost(this, targetType),
  );

  int _bookmarkVersion(String siteUrl, int topicId) =>
      _bookmarkVersions[_topicKey(siteUrl, topicId)] ?? 0;

  int _siteBookmarkVersion(String siteUrl) =>
      _siteBookmarkVersions[siteUrl] ?? 0;

  void _advanceBookmarkVersion(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    _bookmarkVersions[key] = _bookmarkVersion(siteUrl, topicId) + 1;
    _siteBookmarkVersions[siteUrl] = _siteBookmarkVersion(siteUrl) + 1;
  }

  Topic _prepareTopicForStore(
    String siteUrl,
    Topic incoming,
    int? versionAtDispatch,
  ) {
    incoming = _projectTopicTracking(
      siteUrl,
      _topicReads.project(siteUrl, incoming),
    );
    if (versionAtDispatch == null ||
        versionAtDispatch == _siteBookmarkVersion(siteUrl)) {
      return incoming;
    }
    final held = store.read<Topic>(siteUrl, incoming.id);
    final heldDetail = store.read<TopicDetail>(siteUrl, incoming.id);
    if (held == null && heldDetail == null) return incoming;
    return incoming.copyWith(
      bookmarked: held?.bookmarked ?? heldDetail?.hasBookmarks ?? false,
    );
  }

  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
  );

  bool _pluginBookmarkWriteInFlight({
    required String siteUrl,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    siteUrl: siteUrl,
    context: _pluginBookmarkWriteContext,
    targetType: targetType,
    targetId: targetId,
  );

  bool _bookmarkWriteInFlight({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
  }) {
    if (targetType == BookmarkTargetType.post) {
      return _postBookmarkWriteInFlight(_postKey(siteUrl, targetId));
    }
    if (targetType == BookmarkTargetType.topic) {
      if (context case _TopicBookmarkWriteContext(:final topicId)) {
        return _topicBookmarkWritesInFlight.contains(
          _topicKey(siteUrl, topicId),
        );
      }
      return false;
    }
    return _pluginBookmarkWritesInFlight.contains(
      _pluginBookmarkKey(siteUrl, targetType, targetId),
    );
  }

  bool _postBookmarkWriteInFlight(String key) =>
      _postBookmarkWritesInFlight.contains(key) ||
      (_postWritesInFlight.containsKey(key) &&
          _postChecklistWrites[key]?.isCurrent() != true);

  PluginBookmarkTargetStrategy? _pluginBookmarkStrategy(
    BookmarkTargetType targetType,
  ) {
    PluginBookmarkTargetStrategy? owner;
    for (final candidate
        in _pluginSession.capabilities<PluginBookmarkTargetStrategy>()) {
      if (candidate.pluginBookmarkTarget != targetType) continue;
      if (owner != null) {
        throw StateError('Duplicate bookmark target ${targetType.id}.');
      }
      owner = candidate;
    }
    return owner;
  }

  BookmarkTargetType? _bookmarkTargetFor(Bookmark bookmark) {
    final core = bookmark.coreTargetType;
    if (core != null) return core;
    PluginBookmarkTargetStrategy? owner;
    for (final candidate
        in _pluginSession.capabilities<PluginBookmarkTargetStrategy>()) {
      if (candidate.pluginBookmarkTarget.wireName !=
          bookmark.bookmarkableType) {
        continue;
      }
      if (owner != null) {
        throw StateError(
          'Duplicate bookmark wire type ${bookmark.bookmarkableType}.',
        );
      }
      owner = candidate;
    }
    return owner?.pluginBookmarkTarget;
  }

  bool _bookmarkContextMatches(
    BookmarkTargetType targetType,
    _BookmarkWriteContext context,
  ) {
    final coreTarget =
        targetType == BookmarkTargetType.post ||
        targetType == BookmarkTargetType.topic;
    return switch (context) {
      _TopicBookmarkWriteContext(:final topicId) => coreTarget && topicId > 0,
      _PluginBookmarkWriteContext() => !coreTarget,
    };
  }

  final Map<String, Object> _postRefreshRequests = {};

  final Set<String> _postRefreshPending = {};

  final Map<String, int> _postRefreshTopics = {};

  /// Posts named by a core deletion whose next committed re-read decides
  /// whether they are still visible.
  final Set<String> _postRefreshDeletions = {};

  bool _beginPostWrite(String key) {
    if (_postWritesInFlight.containsKey(key)) return false;
    _holdPostWrite(key);
    _notify();
    return true;
  }

  /// A live invalidation may already be reading the pre-write snapshot. It
  /// must not land over the optimistic write or the write's own re-read, so
  /// its request is disowned here and replayed when the write ends.
  void _holdPostWrite(String key) {
    // Bookmark and checklist writes can overlap. Keep refreshes deferred until
    // both finish, while other post mutations still require exclusive access.
    _postWritesInFlight.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (_postRefreshRequests.remove(key) != null) {
      _postRefreshPending.add(key);
    }
  }

  void _endPostWrite(String siteUrl, int postId, {bool notify = true}) {
    final key = _postKey(siteUrl, postId);
    final count = _postWritesInFlight[key] ?? 0;
    if (count > 1) {
      _postWritesInFlight[key] = count - 1;
      if (notify) _notify();
      return;
    }
    _postWritesInFlight.remove(key);
    if (notify) _notify();
    if (!_postRefreshPending.remove(key)) return;
    final topicId = _postRefreshTopics.remove(key);
    if (topicId != null) _refreshPosts(siteUrl, topicId, {postId});
  }

  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _createBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _createBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) async {
    final instance = _instanceAt(siteUrl);
    final refreshTarget = targetType.refreshLabel;
    if (instance == null || !instance.isConnected) {
      return BookmarkWriteResult.refused(
        appL10n.reconnectToThisForumToBookmarkIt,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    if (targetType != BookmarkTargetType.post &&
        targetType != BookmarkTargetType.topic &&
        _pluginBookmarkStrategy(targetType) == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetIsNotAvailableInThisBuild,
      );
    }
    final lease = lifecycle.capture(siteUrl);
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final preference =
          autoDeletePreference ??
          instance.user?.bookmarkAutoDeletePreference ??
          BookmarkAutoDeletePreference.clearReminder;
      final int id;
      try {
        id = await api.bookmarks.createBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          targetType: targetType,
          targetId: targetId,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: preference,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.create');
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmWhetherTheBookmarkWasCreatedTheIsBeing(
            (refreshTarget).toString(),
          ),
        );
      }
      final postNumber = targetType == BookmarkTargetType.post
          ? store.read<Post>(siteUrl, targetId)?.postNumber
          : null;
      final bookmark = Bookmark(
        id: id,
        bookmarkableId: targetId,
        bookmarkableType: targetType.wireName,
        postNumber: postNumber,
        name: name,
        reminderAt: reminderAt?.toUtc(),
        autoDeletePreference: preference,
      );
      final applied = lease.commit(() {
        _applyBookmark(siteUrl, context, bookmark);
      });
      if (!applied) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasSavedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        lease,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(bookmark);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _updateBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _updateBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) async {
    final instance = _instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkCannotBeEditedHere,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    final refreshTarget = targetType.refreshLabel;
    final lease = lifecycle.capture(siteUrl);
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await api.bookmarks.updateBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          bookmarkId: bookmark.id,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: autoDeletePreference,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.update');
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheBookmarkChangesTheIsBeingRefreshed(
            (refreshTarget).toString(),
          ),
        );
      }
      final updated = bookmark.copyWith(
        name: name,
        clearName: name == null,
        reminderAt: reminderAt?.toUtc(),
        clearReminder: reminderAt == null,
        autoDeletePreference: autoDeletePreference,
      );
      final applied = lease.commit(() {
        _applyBookmark(siteUrl, context, updated);
      });
      if (!applied) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasUpdatedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        lease,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(updated);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => updateBookmark(
    siteUrl: siteUrl,
    topicId: topicId,
    bookmark: bookmark,
    name: bookmark.name,
    autoDeletePreference: bookmark.autoDeletePreference,
  );

  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => _deleteBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
  );

  Future<BookmarkWriteResult> _deleteBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
  }) async {
    final instance = _instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkCannotBeDeletedHere,
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return BookmarkWriteResult.refused(
        appL10n.thisBookmarkTargetRequiresItsOwningContext,
      );
    }
    final refreshTarget = targetType.refreshLabel;
    final lease = lifecycle.capture(siteUrl);
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return BookmarkWriteResult.refused(
        appL10n.anotherActionOnThisBookmarkIsStillFinishing,
      );
    }
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarkFinished,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final bool? topicBookmarked;
      try {
        topicBookmarked = await api.bookmarks.deleteBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          bookmarkId: bookmark.id,
          targetType: targetType,
        );
        if (targetType.updatesTopicBookmarkState && topicBookmarked == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
              (refreshTarget).toString(),
            ),
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.delete');
          _reconcileBookmarks(
            instance,
            context,
            lease,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheIsBeingRefreshed(
            (refreshTarget).toString(),
          ),
        );
      }
      final applied = lease.commit(() {
        _removeBookmark(
          siteUrl,
          context,
          bookmark,
          topicBookmarked: topicBookmarked,
        );
      });
      if (!applied) {
        return BookmarkWriteResult.reconciled(
          appL10n.theBookmarkWasDeletedOnTheForum,
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        lease,
        targetType: targetType,
        targetId: targetId,
      );
      return const BookmarkWriteResult.saved();
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  @override
  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required String siteUrl,
    required int topicId,
  }) async {
    final context = _TopicBookmarkWriteContext(topicId);
    final instance = _instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) {
      return BookmarkWriteResult.refused(
        appL10n.reconnectToThisForumToDeleteItsBookmarks,
      );
    }
    final key = _topicKey(siteUrl, topicId);
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final postIds =
        detail?.postBookmarks
            .map((bookmark) => bookmark.bookmarkableId)
            .whereType<int>()
            .toSet() ??
        const <int>{};
    final postKeys = {for (final postId in postIds) _postKey(siteUrl, postId)};
    if (_topicBookmarkWritesInFlight.contains(key) ||
        postKeys.any(_postBookmarkWriteInFlight)) {
      return BookmarkWriteResult.refused(
        appL10n.anotherBookmarkActionIsStillFinishing,
      );
    }
    final lease = lifecycle.capture(siteUrl);
    _topicBookmarkWritesInFlight.add(key);
    _postBookmarkWritesInFlight.addAll(postKeys);
    postKeys.forEach(_holdPostWrite);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return BookmarkWriteResult.reconciled(
          appL10n.theForumChangedBeforeTheBookmarksWereDeleted,
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await api.bookmarks.deleteTopicBookmarks(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(instance, context, lease);
          return BookmarkWriteResult.reconciled(
            appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.deleteAll');
          _reconcileBookmarks(instance, context, lease);
        }
        return BookmarkWriteResult.reconciled(
          appL10n.couldnTConfirmTheDeletionTheTopicIsBeingRefreshed,
        );
      }
      lease.commit(() => _removeAllBookmarks(siteUrl, topicId));
      _reconcileBookmarks(instance, context, lease);
      return const BookmarkWriteResult.saved();
    } finally {
      lease.commit(() {
        _topicBookmarkWritesInFlight.remove(key);
        for (final postId in postIds) {
          _postBookmarkWritesInFlight.remove(_postKey(siteUrl, postId));
          _endPostWrite(siteUrl, postId, notify: false);
        }
        _notify();
      });
    }
  }

  bool _beginBookmarkWrite(
    String siteUrl,
    _BookmarkWriteContext context,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    if (targetType == BookmarkTargetType.post) {
      final key = _postKey(siteUrl, targetId);
      if (_postBookmarkWriteInFlight(key)) return false;
      _postBookmarkWritesInFlight.add(key);
      _holdPostWrite(key);
      _notify();
      return true;
    }
    if (targetType == BookmarkTargetType.topic) {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      return _beginTopicBookmarkWrite(_topicKey(siteUrl, topicId));
    }
    final key = _pluginBookmarkKey(siteUrl, targetType, targetId);
    if (!_pluginBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  bool _beginTopicBookmarkWrite(String key) {
    if (!_topicBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  void _endBookmarkWrite(
    String siteUrl,
    _BookmarkWriteContext context,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    if (targetType == BookmarkTargetType.post) {
      _postBookmarkWritesInFlight.remove(_postKey(siteUrl, targetId));
      _endPostWrite(siteUrl, targetId);
      return;
    }
    if (targetType == BookmarkTargetType.topic) {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      _topicBookmarkWritesInFlight.remove(_topicKey(siteUrl, topicId));
      _notify();
      return;
    }
    _pluginBookmarkWritesInFlight.remove(
      _pluginBookmarkKey(siteUrl, targetType, targetId),
    );
    _notify();
  }

  void _applyBookmark(
    String siteUrl,
    _BookmarkWriteContext context,
    Bookmark bookmark,
  ) {
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    final plugin = targetType == null
        ? null
        : _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) {
        plugin.putPluginBookmark(siteUrl, targetId, bookmark);
      }
      _notify();
      return;
    }
    final topicId = (context as _TopicBookmarkWriteContext).topicId;
    _advanceBookmarkVersion(siteUrl, topicId);
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.withBookmark(bookmark),
    );
    final postId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.post && postId != null) {
      store.update<Post>(
        siteUrl,
        postId,
        (post) => post.withBookmark(bookmark),
      );
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: true),
    );
    _notify();
  }

  void _removeBookmark(
    String siteUrl,
    _BookmarkWriteContext context,
    Bookmark bookmark, {
    required bool? topicBookmarked,
  }) {
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    final plugin = targetType == null
        ? null
        : _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) plugin.removePluginBookmark(siteUrl, targetId);
      _notify();
      return;
    }
    final topicId = (context as _TopicBookmarkWriteContext).topicId;
    _advanceBookmarkVersion(siteUrl, topicId);
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.withoutBookmark(bookmark.id),
    );
    final postId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.post && postId != null) {
      store.update<Post>(siteUrl, postId, (post) => post.withBookmark(null));
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: topicBookmarked == true),
    );
    _notify();
  }

  void _removeAllBookmarks(String siteUrl, int topicId) {
    _advanceBookmarkVersion(siteUrl, topicId);
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail != null) {
      for (final postId in detail.stream) {
        store.update<Post>(siteUrl, postId, (post) => post.withBookmark(null));
      }
      store.put(siteUrl, detail.withoutBookmarks());
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: false),
    );
    _notify();
  }

  void _reconcileBookmarks(
    DiscourseInstance instance,
    _BookmarkWriteContext context,
    SiteLease lease, {
    BookmarkTargetType targetType = BookmarkTargetType.topic,
    int? targetId,
  }) {
    if (isDisposed || !lease.isCurrent) return;
    final plugin = _pluginBookmarkStrategy(targetType);
    if (plugin != null && targetId != null) {
      _observePluginLifecycle(
        Future.sync(
          () => plugin.reconcilePluginBookmark(instance.url, targetId),
        ),
        'plugins.session.reconcileBookmark',
      );
    } else {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      final route = currentContent;
      final row = store.read<Topic>(instance.url, topicId);
      unawaited(
        _refreshTopicBookmarks(
          instance.url,
          topicId,
          route?.topicId == topicId ? route?.slug ?? '' : row?.slug ?? '',
          lease,
        ),
      );
    }
    if (isDisposed || !lease.isCurrent) return;
    unawaited(accountActivity.loadBookmarks(instance, force: true));
    unawaited(accountActivity.refreshLoadedBookmarkList(instance));
  }

  Future<void> _refreshTopicBookmarks(
    String siteUrl,
    int topicId,
    String slug,
    SiteLease lease,
  ) async {
    // Reconciliation owns bookmark metadata only. A full topic replacement
    // could erase a checklist's optimistic state or its newer saved content.
    _advanceBookmarkVersion(siteUrl, topicId);
    final version = _bookmarkVersion(siteUrl, topicId);
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final payload = await api.topicContent.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        apiKey: credential.value,
      );
      lease.commit(() {
        if (version != _bookmarkVersion(siteUrl, topicId)) return;
        for (final incoming in payload.posts) {
          store.update<Post>(
            siteUrl,
            incoming.id,
            (held) => held.withBookmarkOf(incoming),
          );
        }
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (held) => held.withBookmarksOf(payload.detail),
        );
        store.update<Topic>(
          siteUrl,
          topicId,
          (held) => held.copyWith(bookmarked: payload.detail.hasBookmarks),
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'bookmark.refreshAfterWrite',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  static String _postKey(String siteUrl, int postId) => '$siteUrl~$postId';

  static String _pluginBookmarkKey(
    String siteUrl,
    BookmarkTargetType targetType,
    int targetId,
  ) => '$siteUrl~${targetType.id}~$targetId';

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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(targetSite),
      );
      if (credential == null || !lease.isCurrent) return;
      final fetched = await api.topicContent.postLikers(
        siteUrl: targetSite,
        postId: postId,
        // Keep credential reads inside the guarded try: macOS entitlement
        // failures must not strand the fetch in [likerRequests].
        apiKey: credential.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return null;
      final fetched = await api.topicContent.postRevision(
        siteUrl: siteUrl,
        postId: postId,
        revision: revision,
        apiKey: credential.value,
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
    void Function(String siteUrl, int topicId)? accepted,
  }) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;

    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    final key = _postKey(siteUrl, post.id);
    if (!_beginPostWrite(key)) return null;

    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final apiKey = credential.apiKey!;

      try {
        await write(siteUrl, apiKey);
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
          accepted(siteUrl, topicId);
          _notify();
        });
      }
      await _refreshPost(siteUrl, topicId, post.id, apiKey, lease);
      return null;
    } finally {
      lease.commit(() => _endPostWrite(siteUrl, post.id));
    }
  }

  Future<String?> _mutateSelectedTopicPosts(
    String siteUrl,
    int topicId,
    List<Post> posts,
    Future<void> Function(String apiKey, List<int> ids) write,
  ) async {
    final topicKey = _topicKey(siteUrl, topicId);
    final postKeys = [for (final post in posts) _postKey(siteUrl, post.id)];
    if (_topicPostSelectionWrites.contains(topicKey) ||
        postKeys.any(_postWritesInFlight.containsKey)) {
      return null;
    }
    final lease = lifecycle.capture(siteUrl);
    _topicPostSelectionWrites.add(topicKey);
    postKeys.forEach(_holdPostWrite);
    _notify();

    var succeeded = false;
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final ids = List<int>.unmodifiable(posts.map((post) => post.id));
      try {
        await write(credential.apiKey!, ids);
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
      await _refreshSelectedTopicPosts(
        siteUrl,
        topicId,
        ids,
        credential.apiKey,
        lease,
      );
      succeeded = true;
      return null;
    } finally {
      lease.commit(() {
        _topicPostSelectionWrites.remove(topicKey);
        if (succeeded) _topicPostSelections.remove(topicKey);
        for (final post in posts) {
          _endPostWrite(siteUrl, post.id, notify: false);
        }
        _notify();
      });
    }
  }

  Future<void> _refreshSelectedTopicPosts(
    String siteUrl,
    int topicId,
    List<int> postIds,
    String? apiKey,
    SiteLease lease,
  ) async {
    final freshById = <int, Post>{};
    try {
      for (var start = 0; start < postIds.length; start += 20) {
        if (isDisposed || !lease.isCurrent) return;
        final end = start + 20 < postIds.length ? start + 20 : postIds.length;
        final fetched = await api.topicContent.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: postIds.sublist(start, end),
          apiKey: apiKey,
        );
        if (isDisposed || !lease.isCurrent) return;
        for (final post in fetched) {
          if (postIds.contains(post.id)) freshById[post.id] = post;
        }
      }
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.selectedPosts.refreshAfterWrite',
          severity: DiagnosticSeverity.warning,
        );
      }
      return;
    }

    lease.commit(() {
      for (final postId in postIds) {
        final fresh = freshById[postId];
        if (fresh == null) {
          _removeTopicPost(siteUrl, topicId, postId);
        } else {
          store.put(siteUrl, fresh);
          store.update<TopicDetail>(
            siteUrl,
            topicId,
            (detail) => detail.withPostId(postId),
          );
        }
      }
      _notify();
    });
  }

  Future<void> _refreshPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) async {
    if (isDisposed || !lease.isCurrent) return;
    List<Post> fetched;
    try {
      fetched = await api.topicContent.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [postId],
        apiKey: apiKey,
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.refreshAfterWrite',
          severity: DiagnosticSeverity.warning,
        );
      }
      return;
    }

    lease.commit(() {
      final fresh = fetched.where((p) => p.id == postId).firstOrNull;
      if (fresh == null) {
        _removeTopicPost(siteUrl, topicId, postId);
      } else {
        store.put(siteUrl, fresh);
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (detail) => detail.withPostId(postId),
        );
      }
      _notify();
    });
  }

  bool _replaceComposer() {
    final existing = _composer;
    if (existing == null) return true;
    if (existing.discarding) return false;
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
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(target.siteUrl),
    );
    if (held == null) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    if (held.value.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    final identity = await _readSessionValue(lease, authenticator.clientId);
    if (identity == null || !lease.isCurrent) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    final forPrivateMessage = _uploadsForPrivateMessage(target);
    return api.composerPersistence.uploadComposerImage(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      clientId: identity.value,
      file: file,
      onProgress: onProgress,
      abortTrigger: abortTrigger,
      uploadType: target.policy?.uploadType ?? ComposerUploadType.composer,
      forPrivateMessage: forPrivateMessage,
      sizeLimit: siteConfigFor(target.siteUrl).uploadSizeLimit(
        file.name,
        staff: currentUserFor(target.siteUrl)?.staff == true,
        privateMessage: forPrivateMessage,
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
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(target.siteUrl),
    );
    if (held == null) return const {};
    if (held.value.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    final identity = await _readSessionValue(lease, authenticator.clientId);
    if (identity == null || !lease.isCurrent) return const {};
    return api.composerPersistence.lookupUploadUrls(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      clientId: identity.value,
      shortUrls: urls,
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
    if (target.createsTopic) {
      _composerSubmissionTabs[composer] =
          _forumWorkspaces[target.siteUrl]?.activeTabId;
    }

    if (target.isEdit) {
      return _submitEdit(composer, target, composer.editRaw, lease);
    }

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

    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;
    final PostCreation creation;
    try {
      creation = target.createsTopic
          ? await api.composerPersistence.createTopic(
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
            )
          : await api.composerPersistence.createPost(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              topicId: target.topicId,
              raw: raw,
              replyToPostNumber: target.replyToPostNumber,
              whisper: whisper,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              draftKey: target.draftKey,
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
        if (target.createsTopic) {
          await _reconcileNewTopic(target, sent, composer, e, lease: lease);
        } else {
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
      if (target.createsTopic) {
        await _reconcileNewTopic(
          target,
          sent,
          composer,
          const WriteException(WriteFailure.unreachable),
          lease: lease,
        );
      } else {
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

    if (target.createsTopic) {
      lease.commit(
        () => _applyTopicCreation(target, creation, composer, lease),
      );
    } else {
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
    if (template != null && composer.raw == template.trim()) {
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
    ComposerTarget target,
    String raw,
    SiteLease lease,
  ) async {
    if (target.isCategoryEdit) {
      return _submitCategoryEdit(composer, target);
    }
    if (target.isTagsEdit) {
      return _submitTagsEdit(composer, target);
    }
    final key = _postKey(target.siteUrl, target.editingPostId!);
    if (!_beginPostWrite(key)) {
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
      lease.commit(() => _endPostWrite(target.siteUrl, target.editingPostId!));
    }
  }

  Future<void> _submitEditNow(
    ComposerController composer,
    ComposerTarget target,
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
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;

    if (target.editsTopicMetadata && composer.metadataChanged) {
      final TopicUpdate update;
      try {
        update = await api.topicMutations.updateTopic(
          siteUrl: target.siteUrl,
          apiKey: apiKey,
          topicId: target.topicId,
          title: composer.title.text.trim(),
          originalTitle: composer.originalTitle,
          categoryId: composer.categoryId,
          tags: composer.tags,
          originalTags: composer.originalTags,
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
      updated = await api.composerPersistence.updatePost(
        siteUrl: target.siteUrl,
        apiKey: apiKey,
        postId: target.editingPostId!,
        raw: raw,
        originalText: composer.originalRaw,
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
      _storeEditedPost(target.siteUrl, updated, raw: raw);
      _closeSubmittedComposer(composer);
    });
  }

  void _storeEditedPost(String siteUrl, Post updated, {required String raw}) {
    final held = store.read<Post>(siteUrl, updated.id);
    // The answer carries the raw the site stored, whitespace normalized; it is
    // the next edit's `original_text`, so it wins over the text that was sent.
    final withRaw = updated.raw == null ? updated.withRaw(raw) : updated;
    // Edit responses omit reader-specific actions and plugin state; preserve
    // those values from the held post.
    store.put(
      siteUrl,
      held == null
          ? withRaw
          : withRaw
                .copyWith(isLocalized: held.isLocalized)
                .withLikesOf(held)
                .withPostActionsOf(held)
                .withBookmarkOf(held)
                .withPlugins(
                  api.models.mergeAfterPostEdit(
                    held: held.plugins,
                    incoming: updated.plugins,
                  ),
                ),
    );
  }

  Future<void> _submitTagsEdit(
    ComposerController composer,
    ComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await api.topicMutations.updateTopicTags(
        siteUrl: target.siteUrl,
        apiKey: credential.apiKey!,
        topicId: target.topicId,
        tags: composer.tags,
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
    ComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await api.topicMutations.updateTopic(
        siteUrl: target.siteUrl,
        apiKey: credential.apiKey!,
        topicId: target.topicId,
        title: target.topicTitle,
        originalTitle: target.topicTitle,
        categoryId: composer.categoryId,
        tags: composer.tags,
        originalTags: composer.originalTags,
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
    if (composer.target.createsTopic) {
      await _reconcileNewTopic(
        composer.target,
        sent,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    } else {
      await _reconcile(
        composer.target,
        sent.raw,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    }
  }

  static const int _reconcileWindow = 5;

  static final RegExp _unicodeSpace = RegExp(
    '[\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]',
  );

  /// Raw as the site stores it: PostCreator keeps
  /// `TextCleaner.normalize_whitespaces(raw)` right-stripped, and the composer
  /// sends it trimmed, so both ends go.
  static String _storedRaw(String raw) =>
      raw.replaceAll(_unicodeSpace, ' ').trim();

  /// A key that survives `TextCleaner.clean_title`: prettifying changes case,
  /// collapses repeated `!`/`?` and runs of spaces, and drops trailing
  /// periods. It only narrows which topics are read; the first post's raw is
  /// what identifies ours.
  static String _titleKey(String title) => title
      .replaceAll(_unicodeSpace, ' ')
      .replaceAll('\u200B', '')
      .toLowerCase()
      .replaceAll(RegExp(r'!+'), '!')
      .replaceAll(RegExp(r'\?+'), '?')
      .replaceAll(RegExp(r'[\s.!?]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _reconcileNewTopic(
    ComposerTarget target,
    ComposerSubmission sent,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;
    final credential = await _credentialForWrite(target.siteUrl);
    if (!session.isCurrent || credential.failure != null) {
      session.commit(composer.unresolved);
      return;
    }
    final apiKey = credential.apiKey!;

    try {
      final retained = await api.composerPersistence.draft(
        siteUrl: target.siteUrl,
        apiKey: apiKey,
        draftKey: target.draftKey,
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
      final recentPath = target.isPrivateMessage
          ? '/topics/private-messages-sent/${Uri.encodeComponent(username)}.json'
          : '/topics/created-by/${Uri.encodeComponent(username)}.json';
      final recent = await api.topicFeeds.topicList(
        siteUrl: target.siteUrl,
        path: recentPath,
        apiKey: apiKey,
      );
      final matches = <TopicPayload>[];
      final titleKey = _titleKey(sent.title);
      final storedRaw = _storedRaw(sent.raw);
      for (final row
          in recent.topics
              .where((topic) => _titleKey(topic.title) == titleKey)
              .take(_reconcileWindow)) {
        final payload = await api.topicContent.topic(
          siteUrl: target.siteUrl,
          slug: row.slug,
          id: row.id,
          apiKey: apiKey,
        );
        final firstId = payload.detail.stream.firstOrNull;
        if (firstId == null) continue;
        final posts = await api.topicContent.posts(
          siteUrl: target.siteUrl,
          topicId: row.id,
          ids: [firstId],
          includeRaw: true,
          apiKey: apiKey,
        );
        if (posts.firstOrNull?.raw case final landed?
            when _storedRaw(landed) == storedRaw) {
          matches.add(payload);
        }
      }
      if (!session.isCurrent) return;
      if (matches.length == 1) {
        final payload = matches.single;
        session.commit(() {
          _absorb(target.siteUrl, payload);
          _finishCreatedTopic(
            target,
            composer,
            session,
            payload.detail.id,
            recent.topics
                    .where((topic) => topic.id == payload.detail.id)
                    .firstOrNull
                    ?.slug ??
                '',
            payload.detail.title,
          );
        });
      } else {
        session.commit(composer.unresolved);
      }
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
    ComposerTarget target,
    String raw,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;

    final username = _instanceAt(target.siteUrl)?.user?.username;
    final credential = await _credentialForWrite(target.siteUrl);
    if (!session.isCurrent) return;
    if (credential.failure != null) {
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }
    final apiKey = credential.apiKey;

    late TopicPayload topic;
    late List<Post> posts;
    Post? landed;
    try {
      topic = await api.topicContent.topic(
        siteUrl: target.siteUrl,
        slug: target.slug,
        id: target.topicId,
        apiKey: apiKey,
      );

      // Ours would be at the end, and a topic answers with its first chunk of
      // posts — so the tail has to be asked for by id.
      final stream = topic.detail.stream;
      final tail = stream.length <= _reconcileWindow
          ? stream
          : stream.sublist(stream.length - _reconcileWindow);

      posts = await api.topicContent.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: tail,
        includeRaw: true,
        apiKey: apiKey,
      );
      final storedRaw = _storedRaw(raw);
      for (final post in posts) {
        if (post.username == username &&
            post.raw != null &&
            _storedRaw(post.raw!) == storedRaw) {
          landed = post;
          break;
        }
      }
    } catch (error, stackTrace) {
      if (session.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.reconcile',
          severity: DiagnosticSeverity.warning,
        );
      }
      // Still unknown, and saying "it failed" would invite the second post
      // this whole path exists to prevent.
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }

    session.commit(() {
      _absorb(target.siteUrl, topic);
      store.putAll(target.siteUrl, posts);
      if (landed == null) {
        composer.checkedNotPosted(failure);
        _notify();
        return;
      }

      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.withPostId(landed!.id),
      );
      // Found posted is accepted as surely as a creation that answered: the
      // site dropped its draft, so the local copy goes too. Kept, it restores
      // into the next reply, whose first save puts the posted text back.
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
    ComposerTarget target,
    PostCreation creation,
    ComposerController composer,
    SiteLease lease,
  ) {
    final post = creation.post;
    if (post != null) {
      store.put(target.siteUrl, post);
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.withPostId(post.id),
      );
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

    // The appended post is what the author sees immediately; this repairs the
    // stream and the count, and picks up whatever landed while they typed.
    unawaited(_refetchTopic(target.siteUrl, target.topicId, target.slug));
  }

  void _applyTopicCreation(
    ComposerTarget target,
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
    if (creation.post case final post?) store.put(target.siteUrl, post);
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
    ComposerTarget target,
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
    final workspace = _forumWorkspaces[target.siteUrl];
    final submittedTabId = _composerSubmissionTabs[composer];
    final tabId =
        workspace?.tabById(submittedTabId ?? '')?.id ?? workspace?.activeTabId;
    if (currentInstance?.url == target.siteUrl && activeTabId == tabId) {
      _openTopic(topicId, slug, title);
      if (origin != null && target.isNewTopic) {
        unawaited(loadFeed(origin, force: true));
      }
    } else if (tabId != null) {
      final tab = _forumWorkspaces[target.siteUrl]?.tabById(tabId);
      if (tab != null) {
        _replaceTab(
          target.siteUrl,
          tab.push(
            ContentRoute.topic(topicId: topicId, slug: slug, title: title),
          ),
        );
        _notify();
      }
    }
  }

  Future<void> _refetchTopic(
    String siteUrl,
    int topicId,
    String slug, {
    int? postNumber,
  }) async {
    final key = _topicKey(siteUrl, topicId);
    if (_topicsLoading.contains(key)) {
      // A live echo can start a read while an Assign write is still landing.
      // Remember the later invalidation so the pre-write snapshot cannot be
      // the last answer stored.
      _topicRefreshPending.add(key);
      if (postNumber != null) {
        _topicRefreshPostNumbers[key] = postNumber;
      }
      return;
    }
    final lease = lifecycle.capture(siteUrl);
    final bookmarkVersion = _bookmarkVersion(siteUrl, topicId);
    final messageArchiveVersion = _messageArchiveVersion(siteUrl, topicId);
    final postRemovalVersion = _topicPostRemovalVersion(siteUrl, topicId);
    _topicsLoading.add(key);

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final topic = await api.topicContent.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        postNumber: postNumber,
        apiKey: credential.value,
      );
      lease.commit(
        () => _absorb(
          siteUrl,
          topic,
          bookmarkVersionAtDispatch: bookmarkVersion,
          messageArchiveVersionAtDispatch: messageArchiveVersion,
          postRemovalVersionAtDispatch: postRemovalVersion,
          positioned: postNumber != null,
        ),
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      lease.commit(() => _topicsStale.add(key));
      _reportOperationalError(
        error,
        stackTrace,
        'topic.refetchAfterWrite',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      var replayRefresh = false;
      int? replayPostNumber;
      lease.commit(() {
        _topicsLoading.remove(key);
        replayRefresh = _topicRefreshPending.remove(key);
        if (replayRefresh) {
          replayPostNumber = _topicRefreshPostNumbers.remove(key);
        }
        _notify();
      });
      if (replayRefresh && lease.isCurrent) {
        unawaited(
          _refetchTopic(siteUrl, topicId, '', postNumber: replayPostNumber),
        );
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(targetSite),
      );
      if (credential == null || !lease.isCurrent) return;
      final card = await api.site.userCard(
        siteUrl: targetSite,
        username: username,
        // Read inside the guard, the way `loadLikers` does: storage that
        // throws would otherwise strand the fetch in [userCardRequests].
        apiKey: credential.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) return const [];
      found = await api.search.searchHashtags(
        siteUrl: siteUrl,
        term: term,
        order: _composerHashtagTypes(),
        apiKey: credential.value,
        clientId: identity.value,
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
        unawaited(
          _resolveMentions(
            siteUrl,
            target.isPlugin ? target.policy!.mentionTopicId : target.topicId,
            usernames,
          ),
        );
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) return;
      final found = await api.lookups.lookupHashtags(
        siteUrl: siteUrl,
        refs: ask,
        order: _composerHashtagTypes(),
        apiKey: credential.value,
        clientId: identity.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) return;
      final real = await api.lookups.checkMentions(
        siteUrl: siteUrl,
        names: ask,
        topicId: topicId,
        apiKey: credential.value,
        clientId: identity.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return const FoundUsersAndGroups();
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) {
        return const FoundUsersAndGroups();
      }
      final found = await api.search.searchUsersAndGroups(
        siteUrl: siteUrl,
        term: term,
        limit: 20,
        apiKey: credential.value,
        clientId: identity.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return const FoundUsersAndGroups();
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) {
        return const FoundUsersAndGroups();
      }
      found = await api.search.searchMentions(
        siteUrl: siteUrl,
        term: term,
        topicId: topicId,
        apiKey: credential.value,
        clientId: identity.value,
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
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readClientIdFor(lease, credential.value);
      if (identity == null || !lease.isCurrent) return const [];
      found = await api.lookups.searchUsers(
        siteUrl: siteUrl,
        term: term,
        topicId: topicId,
        apiKey: credential.value,
        clientId: identity.value,
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

  Future<void> loadCategories(String siteUrl, {bool force = false}) async {
    final instance = _instanceAt(siteUrl);
    if (force && !categoryFeedFor(siteUrl).loading) {
      _categorised.remove(siteUrl);
    }
    if (instance != null) await _ensureCategoriesFor(instance);
  }

  Future<void> loadTags(String siteUrl, {bool force = false}) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      return;
    }
    if (!siteConfigFor(siteUrl).taggingEnabled) {
      final held = tagDirectoryFeedFor(siteUrl);
      if (!held.loaded || held.tags.isNotEmpty || held.error != null) {
        _tagDirectoryFeeds[siteUrl] = const TagDirectoryFeed(loaded: true);
        _notify();
      }
      return;
    }
    final held = tagDirectoryFeedFor(siteUrl);
    if (!force && held.loaded) return;
    if (_tagDirectoryRequests.containsKey(siteUrl)) return;
    final request = Object();
    _tagDirectoryRequests[siteUrl] = request;

    final lease = lifecycle.capture(siteUrl);
    _tagDirectoryFeeds[siteUrl] = held.refreshing();
    _notify();
    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final identity = credential.value == null
          ? null
          : await _readSessionValue(lease, authenticator.clientId);
      if (credential.value != null && (identity == null || !lease.isCurrent)) {
        return;
      }
      final tags = await api.tags.tags(
        siteUrl: siteUrl,
        apiKey: credential.value,
        clientId: identity?.value,
      );
      final visibleTags = instance.user == null
          ? tags.where((tag) => !tag.pmOnly)
          : tags;
      lease.commit(() {
        _tagDirectoryFeeds[siteUrl] = held.withTags(visibleTags);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'tags.load',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _tagDirectoryFeeds[siteUrl] = held.withError(
          appL10n.couldnTLoadTagsFrom((instance.host).toString()),
        );
        _notify();
      });
    } finally {
      if (identical(_tagDirectoryRequests[siteUrl], request)) {
        _tagDirectoryRequests.remove(siteUrl);
      }
    }
  }

  Future<void> _ensureCategoryIds(
    DiscourseInstance instance,
    String? apiKey,
    Iterable<int> categoryIds,
  ) async {
    if (instance.loginRequired && !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    String? clientId;
    try {
      var pending = categoryIds.toSet();
      final visited = <int>{};
      while (pending.isNotEmpty) {
        final cached = [
          for (final id in pending)
            ?store.read<TopicCategory>(instance.url, id),
        ];
        if (cached.isNotEmpty) {
          pending.removeAll(cached.map((category) => category.id));
          visited.addAll(cached.map((category) => category.id));
          pending.addAll([
            for (final category in cached)
              if (category.parentCategoryId case final parentId?
                  when !visited.contains(parentId))
                parentId,
          ]);
          continue;
        }
        final batch = <int>[];
        final requested = <int>{};
        final requests = <Future<List<TopicCategory>>>{};
        for (final id in pending) {
          if (batch.length == 100) break;
          requested.add(id);
          final active = _categoryIdRequests[(instance.url, id)];
          if (active == null) {
            batch.add(id);
          } else {
            requests.add(active);
          }
        }
        if (batch.isNotEmpty) {
          // Register ownership before yielding for credentials so another
          // topic can join this lookup instead of publishing without labels.
          final result = Completer<List<TopicCategory>>();
          for (final id in batch) {
            _categoryIdRequests[(instance.url, id)] = result.future;
          }
          requests.add(result.future);
          unawaited(() async {
            try {
              if (apiKey != null) clientId ??= await authenticator.clientId();
              if (isDisposed || !lease.isCurrent) {
                result.complete(const []);
                return;
              }
              final found = await api.categories.findCategories(
                siteUrl: instance.url,
                ids: batch,
                apiKey: apiKey,
                clientId: clientId,
              );
              if (!isDisposed) {
                lease.commit(() {
                  _mergeCategories(instance.url, found);
                  _notify();
                });
              }
              result.complete(found);
            } catch (error, stackTrace) {
              result.completeError(error, stackTrace);
            } finally {
              for (final id in batch) {
                final key = (instance.url, id);
                if (identical(_categoryIdRequests[key], result.future)) {
                  final _ = _categoryIdRequests.remove(key);
                }
              }
            }
          }());
        }
        final found = (await Future.wait(requests)).expand((batch) => batch);
        if (isDisposed || !lease.isCurrent) return;
        pending.removeAll(requested);
        visited.addAll(requested);
        pending.addAll([
          for (final category in found)
            if (category.parentCategoryId case final parentId?
                when !visited.contains(parentId))
              parentId,
        ]);
      }
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.find',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  Future<void> _ensureCategoriesFor(
    DiscourseInstance instance, {
    int? categoryId,
  }) async {
    if (instance.loginRequired && !instance.isConnected) return;

    final lease = lifecycle.capture(instance.url);
    try {
      final apiKey = instance.isConnected
          ? await credentials.apiKeyFor(instance.url)
          : null;
      if (!lease.isCurrent) return;
      final clientId = apiKey == null ? null : await authenticator.clientId();
      if (!lease.isCurrent) return;
      await _ensureCategories(
        instance,
        apiKey,
        clientId: clientId,
        lease: lease,
      );
      if (lease.isCurrent && categoryId != null) {
        await _ensureCategoryIds(instance, apiKey, [categoryId]);
      }
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.readCredentials',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        final held = categoryFeedFor(instance.url);
        _categoryFeeds[instance.url] = held.withError(
          appL10n.couldnTLoadCategoriesFrom((instance.host).toString()),
        );
        _notify();
      });
    }
  }

  Future<void> _ensureCategories(
    DiscourseInstance instance,
    String? apiKey, {
    String? clientId,
    SiteLease? lease,
  }) {
    final active = _categoryRequests[instance.url];
    if (active != null) return active;
    late final Future<void> request;
    request =
        _loadCategories(
          instance,
          apiKey,
          clientId: clientId,
          lease: lease,
        ).whenComplete(() {
          if (identical(_categoryRequests[instance.url], request)) {
            final _ = _categoryRequests.remove(instance.url);
          }
        });
    _categoryRequests[instance.url] = request;
    return request;
  }

  Future<void> _loadCategories(
    DiscourseInstance instance,
    String? apiKey, {
    String? clientId,
    SiteLease? lease,
  }) async {
    if (!_categorised.add(instance.url)) return;
    final session = lease ?? lifecycle.capture(instance.url);
    final existingFeed = categoryFeedFor(instance.url);
    _categoryFeeds[instance.url] = existingFeed.refreshing();
    _notify();

    try {
      final result = await api.categories.loadCategories(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (isDisposed || !session.isCurrent) return;
      // Category and tag navigation depend on these ordering and visibility
      // settings. Publish their first snapshot together.
      await _presentation.ensureConfig(instance.url);
      if (isDisposed || !session.isCurrent) return;
      session.commit(() {
        _mergeCategories(instance.url, result.categories);

        final held = categoryFeedFor(instance.url);
        final roots = <int>{...result.rootCategoryIds, ...held.categoryIds};
        final nextPage = existingFeed.loaded && existingFeed.error == null
            ? held.nextPage
            : result.rootCategoryIds.isNotEmpty
            ? 2
            : null;
        _categoryFeeds[instance.url] = CategoryFeed(
          categoryIds: List.unmodifiable(roots),
          loaded: true,
          nextPage: nextPage,
          canCreateTopic: result.canCreateTopic,
        );
        if (result.postActionCatalog case final catalog?) {
          _postActionCatalogs[instance.url] = catalog;
        }
        if (result.siteTopTags case final tags?) {
          _siteTopTagsBySite[instance.url] = tags;
          _tagSidebarCache.remove(instance.url);
        }
        if (result.anonymousDefaultTags case final tags?) {
          _anonymousDefaultTagsBySite[instance.url] = tags;
          _tagSidebarCache.remove(instance.url);
        }
        if (!result.complete) _categorised.remove(instance.url);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !session.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.load',
        severity: DiagnosticSeverity.warning,
      );
      session.commit(() {
        _categorised.remove(instance.url);
        final held = categoryFeedFor(instance.url);
        _categoryFeeds[instance.url] = held.withError(
          appL10n.couldnTLoadCategoriesFrom((instance.host).toString()),
        );
        _notify();
      });
    }
  }

  void _mergeCategories(String siteUrl, Iterable<TopicCategory> incoming) {
    final stored = store.putAll(siteUrl, incoming);
    final byId = <int, TopicCategory>{
      for (final category
          in _categoriesBySite[siteUrl] ?? const <TopicCategory>[])
        category.id: category,
      for (final category in stored) category.id: category,
    };
    _categoriesBySite[siteUrl] = List.unmodifiable(byId.values);
    _categorySidebarCache.remove(siteUrl);
    _rewriteContentRoutes(
      siteUrl,
      (route) => route.resolveCategoryLink(byId.values),
    );
  }

  final Map<String, Object> _categoryPageRequests = {};

  Future<void> loadMoreCategories(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final feed = categoryFeedFor(siteUrl);
    final page = feed.nextPage;
    if (instance == null || page == null || feed.loadingMore) return;
    if (_categoryPageRequests.containsKey(siteUrl)) return;

    final lease = lifecycle.capture(siteUrl);
    final request = Object();
    _categoryPageRequests[siteUrl] = request;
    _categoryFeeds[siteUrl] = feed.loadingNextPage();
    _notify();

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_categoryPageRequests[siteUrl], request);

    try {
      final credential = await _readSessionValue(
        lease,
        () => credentials.apiKeyFor(siteUrl),
      );
      if (credential == null || !requestIsCurrent()) return;
      final identity = credential.value == null
          ? null
          : await _readSessionValue(lease, authenticator.clientId);
      if (credential.value != null &&
          (identity == null || !requestIsCurrent())) {
        return;
      }

      final result = await api.categories.loadCategories(
        siteUrl: siteUrl,
        apiKey: credential.value,
        clientId: identity?.value,
        page: page,
      );
      if (!requestIsCurrent()) return;

      lease.commit(() {
        if (!identical(_categoryPageRequests[siteUrl], request)) return;
        _categoryPageRequests.remove(siteUrl);
        _mergeCategories(siteUrl, result.categories);
        final held = categoryFeedFor(siteUrl);
        _categoryFeeds[siteUrl] = held.withPage(
          result.rootCategoryIds,
          hasMore: result.rootCategoryIds.isNotEmpty,
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (!identical(_categoryPageRequests[siteUrl], request)) return;
        _categoryPageRequests.remove(siteUrl);
        final held = categoryFeedFor(siteUrl);
        _categoryFeeds[siteUrl] = held.withError(
          appL10n.couldnTLoadMoreCategoriesFrom((instance.host).toString()),
          page: true,
        );
        _notify();
      });
    }
  }

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
          unawaited(
            _refreshCustomSidebarSections(instance.url, result.apiKey!),
          );
        case AccountConnectionOutcome.cancelled:
          _connectErrors.remove(instance.url);
        case AccountConnectionOutcome.failed:
          _connectErrors[instance.url] = result.message!;
          if (result.refreshSignedOutPresentation &&
              currentInstance?.url == instance.url) {
            unawaited(_presentation.ensureAppearance(instance.url));
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
    final workspace = _rotatedWorkspaces[siteUrl] ?? _forumWorkspaces[siteUrl];
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
    if (restoredWorkspace != null) _putWorkspace(restoredWorkspace);

    _replaceInstance(held, applied);
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
    _topicPrefetch.clear();
    cooking.forget(siteUrl);
    if (invalidateLifecycle) lifecycle.invalidate(siteUrl);
    siteImages.forget(siteUrl);
    videoThumbnails.forget(siteUrl);
    pdfThumbnails.forget(siteUrl);
    _removeWorkspace(siteUrl);
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
    _postWritesInFlight.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _postBookmarkWritesInFlight.removeWhere(
      (key) => key.startsWith('$siteUrl~'),
    );
    _postChecklistWrites.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _topicPostSelections.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicPostSelectionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicFlagWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicBookmarkWritesInFlight.removeWhere(
      (key) => key.startsWith('$siteUrl#'),
    );
    _pluginBookmarkWritesInFlight.removeWhere(
      (key) => key.startsWith('$siteUrl~'),
    );
    _bookmarkVersions.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _siteBookmarkVersions.remove(siteUrl);
    _postRefreshRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _postRefreshPending.removeWhere((key) => key.startsWith('$siteUrl~'));
    _postRefreshTopics.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _postRefreshDeletions.removeWhere((key) => key.startsWith('$siteUrl~'));
    _queuedPostRefreshes.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _deferredTopicPostsCounts.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicRefreshPending.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicRefreshPostNumbers.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicsStale.removeWhere((key) => key.startsWith('$siteUrl#'));
    _postsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _earlierPostsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _postGapsLoading.removeWhere((key) => key.$1 == siteUrl);
    _topicSummaryStreams.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicSummariesLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicNotificationWrites.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicNotificationConfirmed.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _categoryNotificationWrites.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    _categoryNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    final _ = _categoryNotificationSiteTails.remove(siteUrl);
    _categoryNotificationPreferenceVersions.remove(siteUrl);
    _pluginUserOptionVersions.remove(siteUrl);
    _pluginUserOptionUpdates.remove(siteUrl);
    _categoryNotificationConfirmed.removeWhere(
      (key, _) => key.startsWith('$siteUrl^'),
    );
    _topicPinWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicStatusWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _messageArchiveWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _messageArchiveVersions.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicPostRemovalVersions.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _removedTopicPosts.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicStreamReadVersions.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicDeletionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicJumpRuns.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicReads.forget(siteUrl);

    _categorised.remove(siteUrl);
    final _ = _categoryRequests.remove(siteUrl);
    _categoriesBySite.remove(siteUrl);
    _topicTrackingBySite.remove(siteUrl);
    _topicTrackingMessageFilters.remove(siteUrl);
    _topicTrackingSnapshotsLoaded.remove(siteUrl);
    _topicTrackingRevisions.remove(siteUrl);
    _topicTrackingLoads.remove(siteUrl);
    _topicTrackingRetries.remove(siteUrl);
    _topicTrackingPendingEvents.remove(siteUrl);
    _categoryFeeds.remove(siteUrl);
    _categoryIdRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _categoryPageRequests.remove(siteUrl);
    _categorySidebarCache.remove(siteUrl);
    _siteTopTagsBySite.remove(siteUrl);
    _anonymousDefaultTagsBySite.remove(siteUrl);
    _tagSidebarCache.remove(siteUrl);
    _topicListFilterTagsCache.remove(siteUrl);
    _tagDirectoryFeeds.remove(siteUrl);
    _tagDirectoryRequests.remove(siteUrl);
    _topicComposerCapabilities.remove(siteUrl);
    _postActionCatalogs.remove(siteUrl);
    _customSidebarSections.remove(siteUrl);
    _sidebarSectionsCache.remove(siteUrl);
    _customSidebarSectionsLoaded.remove(siteUrl);
    _customSidebarSectionAttemptedAt.remove(siteUrl);
    _customSidebarSectionRequests.remove(siteUrl)?.ignore();
    _customSidebarSectionVersions.remove(siteUrl);
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
    _hidePresenceVersions.remove(siteUrl);
    _groupedUnreadNotificationVersions.remove(siteUrl);
    _draftCountVersions.remove(siteUrl);
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

    _ensureWorkspace(instance);
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

    _putWorkspace(_newWorkspace(instance));
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
      unawaited(_presentation.ensureAppearance(instance.url));
    }
    // Category navigation is first-class shell state. It cannot depend on the
    // default topic feed succeeding, and its ordering/defaults live in the
    // client settings payload. Selection warms rather than ensures because
    // topic opens may already have spent every attempt during an outage.
    if (canRead) {
      unawaited(_presentation.warmConfig(instance.url));
      unawaited(_presentation.warmCustomEmojis(instance.url));
      if (!instance.isConnected) {
        unawaited(_refreshCustomSidebarSections(instance.url, null));
      }
      // Warm the emoji catalog with the first feed to avoid a second title frame.
      unawaited(_presentation.warmEmojiCatalog(instance.url));
      unawaited(_ensureCategoriesFor(instance));
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
    if (isDisposed ||
        currentInstance?.url != instance.url ||
        !_pendingHomepageTabs.contains(initialTab.id) ||
        !identical(currentWorkspace?.tabById(initialTab.id), initialTab)) {
      return;
    }
    _pendingHomepageTabs.remove(initialTab.id);
    _replaceTab(
      instance.url,
      initialTab.navigate(
        rootDestinationId: initialTab.rootDestinationId,
        contentStack: [_homepageFor(instance)],
      ),
    );
    _notify();
    _hydrateActiveTab(instance);
  }

  void _hydrateActiveTab(DiscourseInstance instance) {
    if (desktopPanelsEnabled) {
      for (final panel in ForumPanel.values) {
        final tab = selectedTabIn(panel);
        if (tab != null) readTab(tab.id, () => _hydrateTab(instance));
      }
    } else {
      _hydrateTab(instance);
    }
  }

  void _hydrateTab(DiscourseInstance instance) {
    final initialTab = activeTab;
    if (initialTab != null && _pendingHomepageTabs.contains(initialTab.id)) {
      unawaited(_hydrateHomepage(instance, initialTab));
      return;
    }
    _rewriteContentRoutes(
      instance.url,
      (route) => route.resolveCategoryLink(filterCategoriesFor(instance.url)),
    );
    final tab = activeTab;
    if (tab == null || currentInstance?.url != instance.url) return;

    final root = tab.contentStack.first;
    if (!root.isNewTab) {
      if (root.id == 'all-categories') {
        unawaited(loadCategories(instance.url));
      } else if (root.isUsers) {
        unawaited(userDirectory.load(instance));
      } else {
        unawaited(
          loadFeed(
            root.feedPath == null && !root.isMessages
                ? tab.rootDestinationId
                : root.id,
          ),
        );
      }
    }
    final source = topicListContent;
    if (source != null && source.id != root.id) {
      unawaited(loadFeed(source.id));
    }
    final route = tab.currentContent;
    final hydrator = _pluginSession
        .capabilities<PluginRouteHydrator>()
        .where((candidate) => candidate.handlesPluginRoute(route.id))
        .firstOrNull;
    if (hydrator != null) {
      _observePluginLifecycle(
        Future.sync(() => hydrator.hydratePluginRoute(instance.url, route.id)),
        'plugins.session.hydrateRoute',
      );
    } else if (route.topicId case final topicId?) {
      final anchor = tab.anchors[route.id];
      unawaited(
        loadTopic(
          topicId,
          route.slug ?? '',
          postNumber: anchor?.kind == 'topic'
              ? anchor!.itemId
              : route.postNumber,
        ),
      );
    } else if (route.isBadges) {
      unawaited(
        badges.load(instance, route.badgeRoute ?? const BadgeRoute.directory()),
      );
    } else if (route.isUsers && route.id != root.id) {
      unawaited(userDirectory.load(instance));
    } else if (route.feedPath != null && route.id != root.id) {
      unawaited(loadFeed(route.id));
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
    if (!desktopPanelsEnabled) _preparePluginPaneForRoute(destination.id);
    final instance = currentInstance;
    if (instance == null) return;
    final workspace = _ensureWorkspace(instance);
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
    _replaceActiveTab(updated);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();

    if (destination.id == 'badges') {
      unawaited(
        badges.load(instance, const BadgeRoute.directory(), refresh: refresh),
      );
    } else if (destination.id == 'user-bookmarks') {
      unawaited(accountActivity.loadBookmarkList(instance, refresh: true));
    } else if (destination.id == 'users') {
      unawaited(userDirectory.load(instance, refresh: refresh));
    } else if (destination.id == 'all-tags') {
      if (refresh) unawaited(loadTags(instance.url, force: true));
    } else if (!content.isNewTab) {
      if (content.id == 'all-categories') {
        unawaited(loadCategories(instance.url, force: refresh));
      } else {
        unawaited(loadFeed(content.id, force: refresh));
      }
    }
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
  }) async {
    final instance = currentInstance;
    final user = instance?.user;
    final tab = activeTab;
    final currentMode = currentTopicListMode;
    if (instance == null || tab == null || currentMode == null) return;
    if (user == null &&
        (mode.isNew ||
            mode == TopicListMode.unread ||
            mode == TopicListMode.unseen)) {
      return;
    }
    if (mode.isSubset && user?.unifiedNewEnabled != true) return;
    if (mode == currentMode &&
        topicListContent?.isAdvancedTopicFilter != true) {
      return;
    }

    final source = topicListContent;
    final tags = _topicListFilterTagNames(instance.url, source);
    final route =
        _topicListFilterRoute(
          siteUrl: instance.url,
          mode: mode,
          category: categoryFor(source?.categoryId),
          tagName: tags.firstOrNull,
          tags: tags,
        ).withTopicListQueryFrom(
          source?.isAdvancedTopicFilter == true ? null : source,
        );
    _replaceTopicListContent(route, keepTopicOpen: keepTopicOpen);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    await loadFeed(route.id);
  }

  Future<void> sortTopicList(String column) async {
    final source = topicListContent;
    if (currentInstance == null ||
        source?.canSortTopicList != true ||
        !ContentRoute.topicListSortColumns.contains(column)) {
      return;
    }
    final same = source!.topicListOrder == column;
    final route = source.withTopicListSort(
      same && source.topicListAscending ? null : column,
      ascending: same && !source.topicListAscending,
    );
    _replaceTopicListContent(route, keepTopicOpen: true);
    _syncTopicChannels();
    _notify();
    await loadFeed(route.id);
  }

  void selectTopicListCategory(
    TopicCategory? category, {
    bool keepTopicOpen = false,
  }) {
    final route = topicListContent;
    final siteUrl = currentInstance?.url;
    if (route?.isTopicListFilter != true || siteUrl == null) return;
    final tags = _topicListFilterTagNames(siteUrl, route);
    _selectTopicListFilter(
      category: category,
      tagName: tags.firstOrNull,
      tags: tags,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void selectTopicListTag(String? tagName, {bool keepTopicOpen = false}) {
    final route = topicListContent;
    if (route?.isTopicListFilter != true) return;
    _selectTopicListFilter(
      category: categoryFor(route!.categoryId),
      tagName: tagName,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void selectTopicListTags(List<String> tags, {bool keepTopicOpen = false}) {
    final route = topicListContent;
    if (route?.isTopicListFilter != true) return;
    _selectTopicListFilter(
      category: categoryFor(route!.categoryId),
      tagName: tags.firstOrNull,
      tags: tags,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void clearTopicListFilters() {
    if (currentContent?.isTopicListFilter != true) return;
    _selectTopicListFilter(category: null, tagName: null);
  }

  void _selectTopicListFilter({
    required TopicCategory? category,
    required String? tagName,
    List<String>? tags,
    bool keepTopicOpen = false,
  }) {
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return;

    final normalizedTag = switch (tagName?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    final route = _topicListFilterRoute(
      siteUrl: instance.url,
      category: category,
      tagName: normalizedTag,
      tags: tags,
      mode: currentTopicListMode ?? TopicListMode.latest,
    ).withTopicListQueryFrom(topicListContent);
    if (route.id == topicListContent?.id &&
        route.feedPath == topicListContent?.feedPath) {
      return;
    }

    _replaceTopicListContent(route, keepTopicOpen: keepTopicOpen);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    unawaited(loadFeed(route.id));
  }

  void _replaceTopicListContent(
    ContentRoute route, {
    required bool keepTopicOpen,
  }) {
    final tab = activeTab;
    if (tab == null) return;
    final sourceIndex = tab.contentStack.lastIndexWhere(
      (item) => !item.isTopic,
    );
    final retainReader =
        !desktopPanelsEnabled &&
        keepTopicOpen &&
        tab.currentContent.isTopic &&
        sourceIndex >= 0 &&
        tab.contentStack[sourceIndex].isTopicList;
    _replaceActiveTab(
      tab.navigate(
        rootDestinationId: route.isMessages ? 'messages' : 'latest',
        contentStack: retainReader
            ? [
                ...tab.contentStack.take(sourceIndex),
                route,
                ...tab.contentStack.skip(sourceIndex + 1),
              ]
            : [route],
      ),
    );
    if (mobileNavigationEnabled && tab.currentContent.isTopicList) {
      mobileNavigation.replaceCurrent(activeTab!.location);
    }
  }

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
    for (final tag in _knownTagsFor(siteUrl)) {
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
    if (mode != TopicListMode.latest || selectedTags.length > 1) {
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
        id: 'topic-list-filter-$tagPath',
        title: tagName,
        icon: DIcons.tag,
        feedPath: '/$tagPath.json',
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
      id: 'topic-list-filter-$combinedPath',
      title: selectedCategory.name,
      icon: categoryDestination.icon,
      color: categoryDestination.routeColor,
      feedPath: '/$combinedPath.json',
    );
  }

  /// Switches sidebar panels in a fresh tab, retaining both pane histories.
  void switchSidebarPanel(VoidCallback switchPanel) {
    if (!forumTabsEnabled || desktopPanelsEnabled) {
      switchPanel();
      return;
    }
    final instance = currentInstance;
    final workspace = currentWorkspace;
    final source = activeTab;
    if (!canCreateTab ||
        instance == null ||
        workspace == null ||
        source == null) {
      return;
    }

    final id = _nextTabId();
    ForumTab copyTab(ForumTab tab) => ForumTab(
      id: id,
      panel: tab.panel,
      rootDestinationId: tab.rootDestinationId,
      contentStack: tab.contentStack,
      backHistory: tab.backHistory,
      forwardHistory: tab.forwardHistory,
      anchors: tab.anchors,
    );

    for (final panes in [_mainPaneTabs, _pluginPaneTabs]) {
      final entries = panes.entries
          .where(
            (entry) =>
                entry.key.siteUrl == instance.url &&
                entry.key.tabId == source.id,
          )
          .toList();
      for (final entry in entries) {
        panes[(siteUrl: instance.url, tabId: id, owner: entry.key.owner)] =
            copyTab(entry.value);
      }
    }
    final sourceKey = (siteUrl: instance.url, tabId: source.id);
    final targetKey = (siteUrl: instance.url, tabId: id);
    if (_activePluginPanes[sourceKey] case final owner?) {
      _activePluginPanes[targetKey] = owner;
    }
    if (_coldPluginPanes.contains(sourceKey)) {
      _coldPluginPanes.add(targetKey);
    }
    _putWorkspace(
      workspace.copyWith(
        tabs: [...workspace.tabs, copyTab(source)],
        activeTabId: id,
      ),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    switchPanel();
  }

  void createTab({ForumPanel? panel}) {
    if (!canCreateTab) return;
    final instance = currentInstance;
    if (instance == null) return;
    final workspace = _ensureWorkspace(instance);
    final tab = _newDefaultTab().copyWith(
      panel: panel ?? workspace.activeTab.panel,
    );
    _putWorkspace(
      workspace.copyWith(tabs: [...workspace.tabs, tab], activeTabId: tab.id),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    _hydrateActiveTab(instance);
  }

  void selectTab(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace?.tabById(id) == null) return;
    if (workspace!.activeTabId != id) {
      _putWorkspace(workspace.copyWith(activeTabId: id), persist: false);
      _tabSelectionPersistencePending = true;
      _mobilePane = MobilePane.content;
      _notify();
      _scheduleTabSelectionSettlement(instance.url, id);
    }
  }

  /// Moves a tab without replacing its route, history, anchors or identity.
  void moveTabToPanel(String id, ForumPanel panel, {int? index}) {
    if (!desktopTopicTabs || !forumTabsEnabled) return;
    final workspace = currentWorkspace;
    final tab = workspace?.tabById(id);
    if (workspace == null || tab == null) return;
    final sourceWillBeEmpty =
        tab.panel != panel && workspace.tabsIn(tab.panel).length == 1;
    if (sourceWillBeEmpty &&
        workspace.tabs.length >= ForumWorkspace.maximumTabs) {
      return;
    }
    final tabs = [...workspace.tabs]..removeWhere((item) => item.id == id);
    final destinationTabs = tabs.where((item) => item.panel == panel).toList();
    final offset = (index ?? destinationTabs.length).clamp(
      0,
      destinationTabs.length,
    );
    final insertion = offset < destinationTabs.length
        ? tabs.indexOf(destinationTabs[offset])
        : destinationTabs.isEmpty
        ? tabs.length
        : tabs.indexOf(destinationTabs.last) + 1;
    tabs.insert(insertion, tab.copyWith(panel: panel));
    if (sourceWillBeEmpty) {
      tabs.add(_newDefaultTab().copyWith(panel: tab.panel));
    }
    _putWorkspace(workspace.copyWith(tabs: tabs, activeTabId: id));
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance?) _hydrateActiveTab(instance);
  }

  void moveTab(String id, int newIndex) {
    if (!forumTabsEnabled) return;
    final workspace = currentWorkspace;
    if (workspace == null || workspace.tabs.length < 2) return;
    final oldIndex = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (oldIndex < 0) return;
    final destination = newIndex.clamp(0, workspace.tabs.length - 1);
    if (oldIndex == destination) return;

    final reordered = List<ForumTab>.of(workspace.tabs);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(destination, moved);
    _putWorkspace(workspace.copyWith(tabs: reordered));
    _notify();
  }

  void _scheduleTabSelectionSettlement(String siteUrl, String tabId) {
    _pendingTabSelection = (siteUrl: siteUrl, tabId: tabId);

    // Controller-only consumers have nothing to paint. Preserve their
    // synchronous hydration/persistence semantics rather than leaving a task
    // waiting for a test or headless binding to produce a frame.
    if (!hasListeners) {
      _settlePendingTabSelection();
      return;
    }
    if (_tabSelectionSettlementScheduled) return;
    _tabSelectionSettlementScheduled = true;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final needsAnotherFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
    unawaited(() async {
      // endOfFrame schedules a frame when called while idle. Unlike a zero
      // duration timer, it guarantees the selected indicator, header and
      // cached viewport have had an opportunity to paint first.
      await SchedulerBinding.instance.endOfFrame;
      // A selection raised while layout/paint or another post-frame callback
      // is running cannot notify its widgets until the following frame.
      if (needsAnotherFrame) await SchedulerBinding.instance.endOfFrame;
      if (!isDisposed) _settlePendingTabSelection();
    }());
  }

  void _settlePendingTabSelection() {
    final target = _pendingTabSelection;
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    if (_tabSelectionPersistencePending) _persistWorkspaces();
    if (target == null ||
        currentInstance?.url != target.siteUrl ||
        activeTabId != target.tabId) {
      return;
    }

    final instance = _instanceAt(target.siteUrl);
    if (instance == null) return;
    _syncTopicChannels();
    _hydrateActiveTab(instance);
  }

  void closeTab(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null) return;
    final index = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;

    final closedActive = workspace.activeTabId == id;
    final closedVisible = isTabVisible(id);
    _rememberClosedForumTab(
      siteUrl: workspace.siteUrl,
      accountIdentity: workspace.accountIdentity,
      tab: workspace.tabs[index],
      index: index,
    );
    late ForumWorkspace replacement;
    if (workspace.tabs.length == 1) {
      final fresh = _newDefaultTab().copyWith(
        panel: workspace.tabs[index].panel,
      );
      replacement = workspace.copyWith(tabs: [fresh], activeTabId: fresh.id);
    } else {
      final remaining = [
        for (final tab in workspace.tabs)
          if (tab.id != id) tab,
      ];
      final neighbours = [
        ...workspace.tabs.skip(index + 1),
        ...workspace.tabs.take(index).toList().reversed,
      ];
      final neighbour = neighbours
          .where((tab) => tab.panel == workspace.tabs[index].panel)
          .firstOrNull;
      final fresh = neighbour == null
          ? _newDefaultTab().copyWith(panel: workspace.tabs[index].panel)
          : null;
      if (fresh != null) remaining.add(fresh);
      final activeId = closedActive
          ? (neighbour ?? fresh ?? remaining.first).id
          : workspace.activeTabId;
      replacement = workspace.copyWith(
        tabs: remaining,
        activeTabId: activeId,
        mainTabId: workspace.selectedTabIn(ForumPanel.main)?.id == id
            ? (neighbour ?? fresh)?.id
            : null,
        secondaryTabId: workspace.selectedTabIn(ForumPanel.secondary)?.id == id
            ? (neighbour ?? fresh)?.id
            : null,
      );
    }

    _putWorkspace(replacement);
    if (closedVisible) {
      _syncTopicChannels();
      _hydrateActiveTab(instance);
    }
    _notify();
  }

  bool reopenClosedTab([String? id]) {
    if (!forumTabsEnabled || !canCreateTab) return false;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null) return false;

    for (var index = _closedForumTabs.length - 1; index >= 0; index--) {
      final closed = _closedForumTabs[index];
      if (closed.siteUrl != workspace.siteUrl ||
          closed.accountIdentity != workspace.accountIdentity ||
          (id != null && closed.tab.id != id)) {
        continue;
      }
      _closedForumTabs.removeAt(index);
      if (workspace.tabById(closed.tab.id) != null) continue;

      final tabs = List<ForumTab>.of(workspace.tabs);
      tabs.insert(closed.index.clamp(0, tabs.length), closed.tab);
      _putWorkspace(workspace.copyWith(tabs: tabs, activeTabId: closed.tab.id));
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      _hydrateActiveTab(instance);
      return true;
    }
    return false;
  }

  void _rememberClosedForumTab({
    required String siteUrl,
    required String accountIdentity,
    required ForumTab tab,
    required int index,
  }) {
    _closedForumTabs.removeWhere(
      (closed) =>
          closed.siteUrl == siteUrl &&
          closed.accountIdentity == accountIdentity &&
          closed.tab.id == tab.id,
    );
    _closedForumTabs.add((
      siteUrl: siteUrl,
      accountIdentity: accountIdentity,
      tab: tab,
      index: index,
    ));
    if (_closedForumTabs.length > ForumWorkspace.maximumTabs) {
      _closedForumTabs.removeAt(0);
    }
  }

  void closeOtherTabs(String id, {bool? reading, ForumPanel? panel}) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null || workspace.tabs.length == 1) {
      return;
    }
    final kept = workspace.tabById(id);
    if (kept == null) return;

    // Remembered right to left so that reopening restores the leftmost tab
    // first, and every reopen lands at the position it left.
    for (var index = workspace.tabs.length - 1; index >= 0; index--) {
      final tab = workspace.tabs[index];
      if (tab.id == id ||
          (panel != null
              ? tab.panel != panel
              : reading != null && tab.currentContent.isTopic != reading)) {
        continue;
      }
      _rememberClosedForumTab(
        siteUrl: workspace.siteUrl,
        accountIdentity: workspace.accountIdentity,
        tab: tab,
        index: index,
      );
    }
    final activeChanged = workspace.activeTabId != id;
    final remaining = [
      for (final tab in workspace.tabs)
        if (tab.id == id ||
            (panel != null
                ? tab.panel != panel
                : reading != null && tab.currentContent.isTopic != reading))
          tab,
    ];
    for (final panel in ForumPanel.values) {
      if (workspace.tabsIn(panel).isNotEmpty &&
          !remaining.any((tab) => tab.panel == panel)) {
        remaining.add(_newDefaultTab().copyWith(panel: panel));
      }
    }
    _putWorkspace(workspace.copyWith(tabs: remaining, activeTabId: id));
    if (activeChanged) {
      _syncTopicChannels();
      _hydrateActiveTab(instance);
    }
    _notify();
  }

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
    if (currentContent?.id == 'summary') return;
    pushContent(
      ContentRoute(id: 'summary', title: appL10n.summary, icon: DIcons.user),
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
        currentContent?.id == 'activity') {
      return;
    }
    pushContent(ContentRoute.userActivity());
  }

  Future<void> resumeDraft(
    String siteUrl,
    UserDraft draft, {
    bool Function()? sourceIsCurrent,
  }) async {
    bool isCurrent() => sourceIsCurrent?.call() ?? true;
    if (!draft.canResume || !isCurrent()) return;
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    final instance = currentInstance;
    if (instance == null || instance.url != siteUrl) return;

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
  void pushContent(ContentRoute route, {bool newTab = false}) {
    final requestedPanel = route.openInMainPanel
        ? ForumPanel.main
        : route.openInSecondaryPanel
        ? ForumPanel.secondary
        : null;
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
    final startsPluginPane = _preparePluginPaneForRoute(route.id);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _replaceActiveTab(
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
  void replaceCurrentContent(ContentRoute route) {
    final startsPluginPane = _preparePluginPaneForRoute(route.id);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _replaceActiveTab(
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

  @override
  bool activatePluginPane(PluginId owner) {
    if (mobileNavigationEnabled || desktopPanelsEnabled) return false;
    final instance = currentInstance;
    var tab = activeTab;
    if (instance == null || tab == null) return false;

    var stateKey = (siteUrl: instance.url, tabId: tab.id);
    var activeOwner = _activePluginPanes[stateKey];
    if (activeOwner == null) {
      final currentRouteId = tab.currentContent.id;
      final restoredPolicy = _pluginSession
          .capabilities<PluginPaneRoutePolicy>()
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (restoredPolicy != null) {
        activeOwner = restoredPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = activeOwner;
      }
    }
    if (activeOwner == owner) {
      return !_coldPluginPanes.contains(stateKey);
    }
    if (activeOwner != null) {
      _deactivatePluginPane(activeOwner, notifyAndHydrate: false);
      tab = activeTab;
      if (tab == null) return false;
      stateKey = (siteUrl: instance.url, tabId: tab.id);
    }
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    _activePluginPanes[stateKey] = owner;
    _mainPaneTabs[key] = tab;
    final pluginTab = _pluginPaneTabs[key];
    if (pluginTab == null) {
      _coldPluginPanes.add(stateKey);
      return false;
    }

    _coldPluginPanes.remove(stateKey);
    _restorePluginPaneTab(instance, pluginTab);
    return true;
  }

  @override
  void deactivatePluginPane(PluginId owner) {
    if (mobileNavigationEnabled) {
      handleBack();
      return;
    }
    if (desktopPanelsEnabled) {
      final instance = currentInstance;
      final active = activeTab;
      if (instance == null || active == null) return;
      final policies = _pluginSession.capabilities<PluginPaneRoutePolicy>();
      final source = tabsForCurrentForum.reversed
          .where(
            (tab) =>
                tab.panel == activeTab?.panel &&
                policies.every(
                  (policy) =>
                      !policy.ownsPluginPaneRoute(tab.currentContent.id),
                ),
          )
          .firstOrNull;
      _replaceActiveTab(
        active.navigate(
          rootDestinationId:
              source?.rootDestinationId ?? instance.defaultDestination.id,
          contentStack: [source?.currentContent ?? _homepageFor(instance)],
        ),
      );
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      _hydrateActiveTab(instance);
      return;
    }
    _deactivatePluginPane(owner, notifyAndHydrate: true);
  }

  void _deactivatePluginPane(PluginId owner, {required bool notifyAndHydrate}) {
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final activeOwner = _activePluginPanes[stateKey];
    if (activeOwner != null && activeOwner != owner) return;
    _activePluginPanes.remove(stateKey);
    final wasCold = _coldPluginPanes.remove(stateKey);
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    if (!wasCold) _pluginPaneTabs[key] = tab;
    final mainTab =
        _mainPaneTabs.remove(key) ??
        ForumTab(
          id: tab.id,
          rootDestinationId: instance.defaultDestination.id,
          contentStack: [
            ContentRoute.fromDestination(instance.defaultDestination),
          ],
        );
    _restorePluginPaneTab(
      instance,
      mainTab,
      notifyAndHydrate: notifyAndHydrate,
    );
  }

  bool _preparePluginPaneForRoute(String routeId) {
    if (mobileNavigationEnabled || desktopPanelsEnabled) return false;
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return false;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final policies = _pluginSession
        .capabilities<PluginPaneRoutePolicy>()
        .toList(growable: false);
    var owner = _activePluginPanes[stateKey];
    if (owner == null) {
      final currentRouteId = tab.currentContent.id;
      final currentPolicy = policies
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (currentPolicy != null) {
        owner = currentPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = owner;
      }
    }

    if (owner != null) {
      final staysInPane = policies.any(
        (policy) =>
            policy.pluginPaneOwner == owner &&
            policy.ownsPluginPaneRoute(routeId) &&
            policy.separatesPluginPane(routeId),
      );
      if (staysInPane) return _coldPluginPanes.remove(stateKey);
      _deactivatePluginPane(owner, notifyAndHydrate: false);
    }

    final targetPolicy = policies
        .where(
          (policy) =>
              policy.ownsPluginPaneRoute(routeId) &&
              policy.separatesPluginPane(routeId),
        )
        .firstOrNull;
    if (targetPolicy != null) {
      activatePluginPane(targetPolicy.pluginPaneOwner);
      return _coldPluginPanes.remove(stateKey);
    }
    return false;
  }

  void _restorePluginPaneTab(
    DiscourseInstance instance,
    ForumTab tab, {
    bool notifyAndHydrate = true,
  }) {
    _setForumContentRoot();
    _replaceActiveTab(tab);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    if (notifyAndHydrate) {
      _notify();
      _hydrateActiveTab(instance);
    }
  }

  bool handleBack({bool canReturnToSidebar = true}) {
    if (mobileNavigationEnabled) {
      if (mobileNavigation.closeSidebar()) {
        _notify();
        return true;
      }
      if (!mobileNavigation.goBack()) return false;
      _restoreMobileLocation();
      return true;
    }
    if (canPopContent) {
      final tab = activeTab!;
      _replaceActiveTab(tab.goBack());
      _syncTopicChannels();
      _notify();
      if (currentInstance case final instance?) _hydrateActiveTab(instance);
      return true;
    }
    if (canReturnToSidebar && _mobilePane == MobilePane.content) {
      _mobilePane = MobilePane.sidebar;
      _notify();
      return true;
    }
    return false;
  }

  bool handleForward() {
    if (mobileNavigationEnabled) {
      if (!mobileNavigation.goForward()) {
        return false;
      }
      _restoreMobileLocation();
      return true;
    }
    final tab = activeTab;
    if (_rootMode != ShellRootMode.forum || tab?.canGoForward != true) {
      return false;
    }
    _replaceActiveTab(tab!.goForward());
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance?) _hydrateActiveTab(instance);
    return true;
  }

  void _notify() {
    readTab(null, _notifyCurrentWorkspace);
  }

  void _notifyCurrentWorkspace() {
    if (loaded && forumTabs.selectedSiteUrl != currentInstance?.url) {
      _persistWorkspaces();
    }
    _rememberCurrentContent();
    _topicPrefetch.validate();
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
      _replaceActiveTab(
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
    _topicPrefetch.clear();
    // Queue the final local draft before lifecycle invalidation without
    // entering the normal remote-sync callback.
    for (final composer in _composers.values) {
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
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    _topicPostHighlightTimer?.cancel();
    _topicPostHighlightTimer = null;
    _topicPostHighlight = null;
    _topicPostHighlightVisible = false;
    if (_tabSelectionPersistencePending || _anchorPersistencePending) {
      _persistWorkspaces();
    }
    _topicPropertyRequests.dispose();
    unawaited(_topicListRevealRequests.close());
    _topicNotificationWrites.clear();
    _closedForumTabs.clear();
    _topicNotificationTails.clear();
    _topicNotificationConfirmed.clear();
    _categoryNotificationWrites.clear();
    _categoryNotificationTails.clear();
    _categoryNotificationConfirmed.clear();
    _categoryNotificationSiteTails.clear();
    _categoryNotificationPreferenceVersions.clear();
    _pluginUserOptionVersions.clear();
    _pluginUserOptionUpdates.clear();
    _topicPinWrites.clear();
    _topicStatusWrites.clear();
    _messageArchiveWrites.clear();
    _messageArchiveVersions.clear();
    _userStatusWrites.clear();
    _optimisticHidePresence.clear();
    _hidePresenceWrites.clear();
    _hidePresenceErrors.clear();
    _hidePresenceVersions.clear();
    _groupedUnreadNotificationVersions.clear();
    _draftCountVersions.clear();
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
    _topicListFilterTagsCache.clear();
    for (final instance in _instances) {
      lifecycle.invalidate(instance.url);
    }
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
    for (final host in _coreBookmarkTargetHosts.values) {
      host.dispose();
    }
    _coreBookmarkTargetHosts.clear();
    for (final host in _pluginBookmarkTargetHosts.values) {
      host.dispose();
    }
    _pluginBookmarkTargetHosts.clear();
    for (final listenable in _pluginSiteConfigListenables.values) {
      listenable.dispose();
    }
    _pluginSiteConfigListenables.clear();
    final presentation = _sitePresentation;
    if (presentation != null) {
      presentation.removeListener(_notify);
      presentation.dispose();
    }
    for (final composer in _composers.values) {
      composer.dispose();
    }
    _composers.clear();
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
  _CookingWatch({
    required this.siteUrl,
    required this.read,
    required this.onChanged,
  }) : _stamp = read();

  final String siteUrl;
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
    final apiKey = await _shell.credentials.apiKeyFor(siteUrl);
    return PluginRequestCredentials(
      apiKey: apiKey,
      clientId: apiKey == null ? '' : await _shell.credentials.clientId(),
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
  void pushContent(ContentRoute route, {bool newTab = false}) =>
      _shell.pushContent(route, newTab: newTab);

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
    implements PluginRouteNavigationHost {
  const _ShellPluginRouteNavigationHost(this._shell);

  final ShellController _shell;

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
    if (route.feedPath == null || _shell.currentContent?.id == route.id) return;
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
    return _shell._pluginBookmarkTargetHost(targetType);
  }
}

final class _ShellBookmarkSession implements BookmarkSession {
  _ShellBookmarkSession(this._shell, String siteUrl)
    : _lease = _shell.lifecycle.capture(siteUrl),
      siteContext = _shell.bookmarkSiteContextFor(siteUrl);

  final ShellController _shell;
  final SiteLease _lease;

  @override
  final BookmarkSiteContext siteContext;

  @override
  bool get isCurrent => !_shell.accountSessionDisposed && _lease.isCurrent;
}

final class _ShellCoreBookmarkTargetHost implements BookmarkTargetHost {
  _ShellCoreBookmarkTargetHost(this._shell, this._targetType);

  final ShellController _shell;
  final BookmarkTargetType _targetType;
  final Map<
    ({String siteUrl, int topicId, int targetId}),
    _BookmarkWriteListenable
  >
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _shell._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    appL10n.thisBookmarkDoesNotBelongTo((_targetType.refreshLabel).toString()),
  );

  @override
  BookmarkSession captureSession(String siteUrl) =>
      _ShellBookmarkSession(_shell, siteUrl);

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) =>
      _shell.bookmarkSiteContextFor(siteUrl);

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) => _shell.bookmarkWriteInFlight(
    siteUrl: siteUrl,
    topicId: topicId,
    targetType: _targetType,
    targetId: targetId,
  );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, topicId: topicId, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _shell,
        () => bookmarkWriteInFlight(
          siteUrl: siteUrl,
          topicId: topicId,
          targetId: targetId,
        ),
        onUnused: (listenable) {
          if (identical(_writeListenables[key], listenable)) {
            _writeListenables.remove(key);
          }
        },
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _shell.createBookmark(
    siteUrl: siteUrl,
    topicId: topicId,
    targetType: _targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.updateBookmark(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.clearBookmarkReminder(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
    );
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.deleteBookmark(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
    );
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

final class _ShellPluginBookmarkTargetHost implements PluginBookmarkHost {
  _ShellPluginBookmarkTargetHost(this._shell, this._targetType);

  final ShellController _shell;
  final BookmarkTargetType _targetType;
  final Map<({String siteUrl, int targetId}), _BookmarkWriteListenable>
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _shell._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    appL10n.thisBookmarkDoesNotBelongTo((_targetType.refreshLabel).toString()),
  );

  @override
  BookmarkSession captureSession(String siteUrl) =>
      _ShellBookmarkSession(_shell, siteUrl);

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) =>
      _shell.bookmarkSiteContextFor(siteUrl);

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int targetId,
  }) => _shell._pluginBookmarkWriteInFlight(
    siteUrl: siteUrl,
    targetType: _targetType,
    targetId: targetId,
  );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _shell,
        () => bookmarkWriteInFlight(siteUrl: siteUrl, targetId: targetId),
        onUnused: (listenable) {
          if (identical(_writeListenables[key], listenable)) {
            _writeListenables.remove(key);
          }
        },
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _shell._createBookmark(
    siteUrl: siteUrl,
    context: _pluginBookmarkWriteContext,
    targetType: _targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._updateBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._updateBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
      name: bookmark.name,
      autoDeletePreference: bookmark.autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._deleteBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
    );
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

/// A per-target busy flag derived from the shell.
///
/// Every message tile asks for one, and each one is a listener on the shell
/// facade that runs on every shell notification. So an instance lives only
/// while something listens to it: when the last listener leaves, the host
/// forgets it and it lets go of the shell, and the next request builds a
/// fresh one. Otherwise every message ever scrolled past would keep a
/// listener on the facade for the life of the app.
final class _BookmarkWriteListenable extends ChangeNotifier
    implements ValueListenable<bool> {
  _BookmarkWriteListenable(
    Listenable source,
    bool Function() read, {
    required void Function(_BookmarkWriteListenable listenable) onUnused,
  }) : _source = source,
       _read = read,
       _release = onUnused,
       _value = read() {
    _source.addListener(_refresh);
  }

  final Listenable _source;
  final bool Function() _read;
  final void Function(_BookmarkWriteListenable listenable) _release;
  bool _value;
  bool _released = false;

  @override
  bool get value => _value;

  void _refresh() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners || _released) return;
    _released = true;
    _release(this);
    // A listener may leave from inside a notification, when disposing is
    // not allowed; the shell listener goes once this notification is over.
    scheduleMicrotask(dispose);
  }

  @override
  void dispose() {
    _released = true;
    _source.removeListener(_refresh);
    super.dispose();
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
  });

  final String siteUrl;
  final int topicId;
  final TopicNotificationLevel level;
  final SiteLease lease;
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
