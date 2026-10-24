import 'dart:async';
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
import '../data/current_user_refresh.dart';
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
import '../data/update_store.dart';
import '../data/updater.dart';
import '../data/user_directory_api.dart';

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
import '../models/forum_about.dart';
import '../models/forum_workspace.dart';
import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../models/incoming_topics.dart';
import '../models/json.dart';
import '../models/live_refresh_id.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../models/post.dart';
import '../models/post_checklist.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/post_mutation_outcome.dart';
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
import '../plugin_api/discourse_model_codec.dart';
import '../plugin_api/emoji_preferences.dart';
import '../plugin_api/plugin_runtime.dart';
import '../plugin_api/site_plugin_api.dart';
import '../site_preference_inventory.g.dart';
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'account_new_topic_dismissals.dart';
import 'app_settings_controller.dart';
import 'badges_controller.dart';
import 'bookmark_link_resolver.dart';
import 'bookmark_transactions.dart';
import 'checklist_transactions.dart';
import 'composer/autocomplete.dart';
import 'composer/components/quote.dart';
import 'composer/controller.dart';
import 'composer/draft_coordinator.dart';
import 'composer/existing_topic_opening_owner.dart';
import 'composer/opening_owner.dart';
import 'composer/pills.dart';
import 'composer/recipient_lookup.dart';
import 'composer/triggers.dart';
import 'content_page_contract.dart';
import 'cooking_context_owner.dart';
import 'core_link_resolver.dart';
import 'do_not_disturb_controller.dart';
import 'draft_list_controller.dart';
import 'flag_transactions.dart';
import 'forum_settings_controller.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'groups_controller.dart';
import 'hashtag.dart';
import 'mobile_navigation.dart';
import 'notification_feed_refresh_owner.dart';
import 'notification_preference_transactions.dart';
import 'plugin_background_retention.dart';
import 'post_quote.dart';
import 'preferences_controller.dart';
import 'preview_requests.dart';
import 'profile_write_transactions.dart';
import 'recent_search_history.dart';
import 'shell_search_controller.dart';
import 'site_live_sessions.dart';
import 'site_presentation_controller.dart';
import 'site_url.dart';
import 'topic_category_path.dart' as category_path;
import 'topic_data_owner.dart';
import 'topic_feed_controller.dart';
import 'topic_list_transitions.dart';
import 'topic_prefetch_controller.dart';
import 'topic_read_controller.dart';
import 'topic_reader_projections.dart';
import 'topic_tracking_directory.dart';
import 'unread_topic_feed.dart';
import 'update_controller.dart';
import 'user_directory_controller.dart';
import 'user_status_overrides.dart';
import 'user_summary_controller.dart';

part 'composer_identity_resolution.dart';
part 'composer_registry.dart';
part 'composer_submission.dart';
part 'core_link_navigation.dart';
part 'current_user_directory.dart';
part 'instance_rail_transactions.dart';
part 'post_commands.dart';

part 'selected_post_moderation.dart';
part 'post_mutation_policy.dart';
part 'topic_action_transactions.dart';
part 'message_archive_transactions.dart';
part 'topic_metadata_transactions.dart';
part 'topic_navigation_attempts.dart';
part 'shell_tab_context.dart';
part 'taxonomy_directory_controller.dart';
part 'workspace_controller.dart';
part 'site_live_composition.dart';

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
typedef _ShellWriteCredential = ({
  String? apiKey,
  AccountRequestCredentials? request,
  WriteException? failure,
});
typedef _PluginPaneKey = ({String siteUrl, String tabId, PluginId owner});
typedef _PluginPaneStateKey = ({String siteUrl, String tabId});
typedef _ClosedForumTab = ({
  String siteUrl,
  String accountIdentity,
  ForumTab tab,
  int index,
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
        AccountSessionHost,
        _CurrentUserRefreshHost {
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
  CookingContextOwner? _cookingContextOwner;
  CookingContextOwner get _cookingContext =>
      _cookingContextOwner ??= CookingContextOwner(
        cooking: cooking,
        store: store,
        presentation: _presentation,
        timezones: TimezoneEnvironment.instance,
        currentUserFor: currentUserFor,
        identitiesFor: (siteUrl) => (
          mentions: _composerIdentities[siteUrl]?.mentions ?? const {},
          hashtags: _composerIdentities[siteUrl]?.hashtags ?? const {},
        ),
      );

  /// Original request identity is retained for host preflight decisions.
  bool cookingRequestIsCurrent(CookingRequest request) =>
      !isDisposed && (_cookingContextOwner?.isCurrent(request) ?? false);

  VoidCallback watchCooking({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  }) => isDisposed
      ? () {}
      : _cookingContext.watch(siteUrl: siteUrl, raw: raw, onChanged: onChanged);

  CookingRequest cookingRequest({
    required String siteUrl,
    required String raw,
    CookingProfile profile = CookingProfile.post,
    CookingContext context = const CookingContext(),
    CookingCachedMetadata? cachedMetadata,
  }) => _cookingContext.request(
    siteUrl: siteUrl,
    raw: raw,
    profile: profile,
    context: context,
    cachedMetadata: cachedMetadata,
  );

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
      );
  final SiteImageRepository? _providedSiteImages;
  final SiteVideoThumbnailRepository? _providedVideoThumbnails;
  final SitePdfThumbnailRepository? _providedPdfThumbnails;
  final InstalledPlugins plugins;
  final bool _ownsPlugins;

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
            final updated = _currentUsers
                .reconcilerFor(siteUrl)
                .updatePluginOption(field, previous: user, update: update);
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
      final tracker = _liveSessions.trackerFor(siteUrl);
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
    } catch (error) {
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

  void _observePluginLifecycle(Future<void> task) {
    unawaited(task.onError((Object error, StackTrace stackTrace) {}));
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
    } catch (error) {
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
    onSnapshotInvalidated: (siteUrl) =>
        _currentUsers.reconcilerFor(siteUrl).doNotDisturbChanged(),
    clock: _clock,
  );

  late final UserStatusOverrides userStatuses = UserStatusOverrides();

  late final PreviewLoadingOwner _previews = PreviewLoadingOwner(
    site: api.site,
    topicContent: api.topicContent,
    credentials: credentials,
    lifecycle: lifecycle,
    store: store,
    userStatuses: userStatuses,
    onStatusAccepted: (siteUrl, userId, status) {
      final lease = lifecycle.capture(siteUrl);
      if (_applyOwnUserStatus(siteUrl, userId, status)) {
        _notify();
        if (lease.isCurrent) instanceStore.save(List.of(_instances)).ignore();
      }
    },
  );

  /// Profile-card fetches by lowercase username; the cards live in [store].
  PreviewRequests<String> get userCardRequests => _previews.userCardRequests;

  /// Post-likers fetches by post ID; the likers live in [store].
  PreviewRequests<int> get likerRequests => _previews.likerRequests;

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
      prepareFeed:
          (instance, apiKey, categories, categoryIds, isCurrent) async {
            if (!isCurrent()) return;
            if (categories.isNotEmpty) {
              _taxonomy.mergeCategories(
                instance.url,
                categories,
                isCurrent: isCurrent,
              );
              if (!isCurrent()) return;
              _notify();
            }
            if (!isCurrent()) return;
            unawaited(
              RequestIntent.background().run(
                () => _taxonomy.ensureCategoriesFor(instance),
              ),
            );
            unawaited(
              _taxonomy.ensureCategoryIds(
                instance,
                categoryIds,
                isCurrent: isCurrent,
              ),
            );
          },
      readPersonalizationStamp: (siteUrl) => (
        bookmarks: _bookmarks.forSite(siteUrl).epoch,
        actions: _topicData.forSite(siteUrl).actionEpoch,
      ),
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
  );

  late final GlobalSearchApi _globalSearchApi = GlobalSearchApi(
    transport: api.pluginTransport,
  );
  late final RecentSearchHistory _searchHistory = RecentSearchHistory(
    api: _globalSearchApi,
    server: api.search,
    credentials: credentials,
    lifecycle: lifecycle,
  );
  late final ShellSearchController search = ShellSearchController(
    history: _searchHistory,
  );

  late final GlobalSearchController globalSearch = GlobalSearchController(
    api: _globalSearchApi,
    credentials: credentials,
    lifecycle: lifecycle,
    history: _searchHistory,
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
    final destination = _routeForLink(absolute);
    return destination != null &&
        _openResolvedCoreLink(destination, _CoreLinkIntent.notification) &&
        _revealNotificationTarget();
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

  late final _instanceRail = _InstanceRailTransactions(this);

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
        } catch (error) {
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
    final tracking = _topicTracking.existing(siteUrl)?.reconciler;
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
      (Object error, StackTrace stack) {},
    );
    final List<DiscourseInstance> stored;
    try {
      stored = await instanceStore.load();
    } catch (error) {
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
      forumSettings.restoreSavedForums([
        for (final instance in stored) instance.url,
      ], initialMode: appSettings.themeMode),
      for (final instance in stored) topicSidebar.ensure(siteUrl: instance.url),
      // Only forums on the rail keep their preferences: a removal may have
      // ended before they were dropped, and older builds kept them.
      _forgetStoredPreferences(),
    ]);
    if (isDisposed) return;
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

    return _instanceRail.settleAddition(
      instance,
      rollback: () {
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
      },
    );
  }

  Future<bool> moveInstance(DiscourseInstance instance, int newIndex) =>
      _instanceRail.move(instance, newIndex);

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

  Future<bool> removeInstance(DiscourseInstance instance) async {
    if (!_instances.contains(instance)) return false;

    // Try revoking the old key and its native push registration, but an
    // unreachable forum must not prevent the user from removing it locally.
    final disconnected = await _accountSessions.disconnect(
      instance.url,
      waitForRemoteRevocation: false,
    );
    final lease = switch (disconnected) {
      AccountDisconnected(:final lease) => lease,
      AccountDisconnectionFailed() ||
      AccountDisconnectionStale() ||
      AccountDisconnectionMissing() => null,
    };
    if (isDisposed || lease == null || !lease.isCurrent) {
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

    return _instanceRail.settleRemoval(
      held.url,
      stillOwnsRemoval: () => removal.isCurrent,
      rollback: () {
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
      },
      forgetDurableRemoval: () {
        // Start page visits name private messages and direct chats, and stored
        // preferences name the forum, its usernames and what was used there, so
        // both leave with the forum for every account. Only a durable removal
        // drops them: a rollback restores the forum with them, and a re-add that
        // landed during the save owns the URL's again.
        unawaited(
          destinationBookmarks
              .forgetSite(held.url)
              .catchError((Object error, StackTrace stack) {}),
        );
        if (recentDestinations.forgetSite(held.url)) {
          unawaited(recentDestinations.save());
        }
        unawaited(_forgetStoredPreferences(removed: held.url));
      },
    );
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
        : _topicTracking.existing(instance.url)?.reconciler;
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
      _topicTracking.existing(siteUrl)?.reconciler.revision ?? 0;

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
      await _liveSessions.starting(instance.url);
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
      await _currentUsers.refresh(
        instance.url,
        apiKey,
        lease: lease,
        force: force,
      );
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
    _currentUsers.reconcilerFor(siteUrl).groupedUnreadChanged();
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
      } catch (_) {}
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
    } catch (_) {}
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
      );
    }
  }

  NotificationFeed notificationsFor(String siteUrl) =>
      accountActivity.notificationsFor(siteUrl);

  Future<void> loadNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadNotifications(instance);
  }

  Future<void> markAllNotificationsRead(String siteUrl) =>
      _notificationFeeds.markAllNotificationsRead(siteUrl);

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

  Future<void> loadOtherNotifications(String siteUrl) =>
      _notificationFeeds.loadOtherNotifications(siteUrl);

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

  late final _notificationFeeds = NotificationFeedRefreshOwner(
    api: api.site,
    credentials: credentials,
    lifecycle: lifecycle,
    activity: accountActivity,
    instanceFor: _instanceAt,
    claimedTypes: (instance) =>
        _claimedUserMenuNotificationTypes(_pluginUserMenuSectionsFor(instance)),
    groupedAuthorityAdvanced: _onGroupedUnreadAuthorityAdvanced,
    refreshDebounce: pluginNotificationFeedRefreshDebounce,
  );

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

  late final _topicTracking = TopicTrackingDirectory(
    lifecycle: lifecycle,
    store: store,
    models: plugins.models,
    userFor: (siteUrl) => _instanceAt(siteUrl)?.user,
    configFor: siteConfigFor,
    changed: (siteUrl) {
      if (currentInstance?.url == siteUrl) _notifyLiveChange();
    },
    retryBeforeAccept: (siteUrl) => _liveSessions.retryTracking(siteUrl),
    clock: _clock,
  );
  bool _liveChangeNotifyPending = false;

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
      final tracking = _topicTracking.existing(instance!.url)?.reconciler;
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
        _topicTracking.existing(siteUrl)?.reconciler.hasSnapshot != true) {
      return null;
    }
    final tracking = _topicTracking.existing(siteUrl)?.reconciler;
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

  void changeSidebarScope({int? categoryId, String? tag}) => unawaited(
    focusedTabContext._transitionTopicList(
      SelectTopicListScope(category: categoryFor(categoryId), tagName: tag),
    ),
  );

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

  late final _newTopicDismissals = NewTopicDismissals(
    api: api.topicFeeds,
    credentials: credentials,
    lifecycle: lifecycle,
    trackingFor: (siteUrl, lease) =>
        _topicTracking.capture(siteUrl, lease: lease),
    reloadSource: (command, lease) async {
      if (!lease.isCurrent || isDisposed) return;
      await topicFeeds.load(
        instance: command.instance,
        destinationId: command.route.id,
        path: command.route.feedPath!,
        incoming: _liveSessions.trackerFor(command.instance.url)?.incoming,
        force: true,
      );
    },
    changed: _notify,
  );

  bool get dismissingNewTopics =>
      _newTopicDismissals.isBusy(currentInstance?.url);

  bool get canDismissNewTopics => focusedTabContext.canDismissNewTopics;

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
      incoming: _liveSessions.trackerFor(instance.url)?.incoming,
      force: force,
    );
  }

  String filterQueryFor(String siteUrl) => topicFeeds.filterQueryFor(siteUrl);

  Future<List<TopicFilterOption>> loadTopicFilterOptions(String siteUrl) =>
      _filterLookup(
        siteUrl,

        (apiKey, clientId) async => (await api.topicFeeds.topicList(
          siteUrl: siteUrl,
          path: '/filter.json',
          apiKey: apiKey,
          clientId: clientId,
        )).filterOptions,
      );

  String topicListFilterEditorQuery(ContentRoute route) =>
      route.topicFilterEditorQuery(
        resolvedTags: _topicListFilterTagNames(currentInstance!.url, route),
      );

  Future<void> applyTopicListFilterQuery(String query) =>
      focusedTabContext.applyTopicListFilterQuery(query);

  Future<void> submitTopicFilter(String query) =>
      focusedTabContext.submitTopicFilter(query);

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
    } catch (error) {
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

  late final SiteLiveSessions _liveSessions = SiteLiveSessions(
    lifecycle: lifecycle,
    credentials: credentials,
    api: api.site,
    trackers: trackers,
    topicTracking: _topicTracking,
    currentUsers: _ShellSiteLiveCurrentUsers(this),
    composition: _ShellSiteLiveComposition(this),
    demandSnapshot: () => {
      for (final site in _instances)
        site.url: SiteLiveDemand(
          foreground: _foreground,
          selected: currentInstance?.url == site.url,
          connected: site.isConnected,
          loginRequired: site.loginRequired,
          retained: _backgroundRetention.retains(site.url),
        ),
    },
  );
  late final _profileWrites = ProfileWriteTransactions(
    currentUser: _ShellProfileCurrentUser(this),
    api: api.site,
    credentials: credentials,
    lifecycle: lifecycle,
    userStatuses: userStatuses,
    doNotDisturb: doNotDisturb,
    changed: _notify,
    clock: _clock,
  );
  late final _currentUsers = _CurrentUserDirectory(
    lifecycle: lifecycle,
    models: plugins.models,
    statuses: userStatuses,
    host: this,
  );

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
    return _liveSessions
            .trackerFor(instance.url)
            ?.incoming
            .count(destinationId) ??
        0;
  }

  Future<void> showIncoming(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final tracker = _liveSessions.trackerFor(instance.url);
    final path = _feedPath(destinationId, instance);
    if (tracker == null || path == null) return;
    await topicFeeds.showIncoming(
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: tracker.incoming,
    );
  }

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
    _liveSessions
        .trackerFor(siteUrl)
        ?.incoming
        .track(
          topicFeeds.incomingFiltersFor(siteUrl),
          parentCategoryOf: (categoryId) =>
              categoryFor(categoryId, siteUrl: siteUrl)?.parentCategoryId,
        );
  }

  void _syncTracking() => _liveSessions.synchronize();

  void _syncTopicChannels() {
    final instance = currentInstance;
    if (instance == null) return;
    final tracker = _liveSessions.trackerFor(instance.url);
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
    final tracking = _topicTracking.capture(siteUrl, lease: lease);
    if (tracking == null) return;
    bool ownsTopic() =>
        !isDisposed &&
        tracking.isCurrent &&
        identical(_liveSessions.trackerFor(siteUrl), tracker);
    tracker.watchTopic(
      routes.keys.first,
      channelsByTopic.values.expand((channels) => channels).toSet().toList(),
      (channel, data) {
        if (!ownsTopic()) {
          return;
        }
        for (final entry in channelsByTopic.entries) {
          if (!ownsTopic()) return;
          if (!entry.value.contains(channel)) continue;
          final topicId = entry.key;
          final coreChannel = '/topic/$topicId';
          if (channel == coreChannel) {
            _notificationPreferences.observeTopicMessage(
              siteUrl,
              topicId,
              data,
              lease,
            );
            if (!ownsTopic()) return;
            _applyTopicStatsMessage(siteUrl, topicId, data, lease);
            if (!ownsTopic()) return;
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
  ) => _notificationFeeds.acceptLiveState(siteUrl, data, lease);

  final Map<String, Set<String>> _serverPluginNames = {};

  bool supportsComposerColors(String siteUrl) =>
      _serverPluginNames[siteUrl]?.contains('discourse-bbcode-color') ?? false;

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

    final user = await _currentUsers.refresh(siteUrl, apiKey, lease: lease);
    if (!lease.isCurrent) return null;
    // A stored id is stable enough to keep this account's private counters
    // connected after a failed refresh, but its capabilities remain unknown.
    return user?.id ?? _instanceAt(siteUrl)?.user?.id;
  }

  @override
  bool _canAcceptCurrentUser(String siteUrl) =>
      !isDisposed && _connectingSiteUrl != siteUrl;

  @override
  Future<DiscourseUser?> _readSessionUser(
    String siteUrl,
    String apiKey,
    SiteLease lease,
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
    } catch (error) {
      if (isDisposed || !lease.isCurrent) return null;

      if (error is ApiKeyRejectedException) {
        await _expireRejectedAccount(siteUrl, apiKey, lease);
        return null;
      }
      lease.commit(() {
        _profileWrites.currentUserReadFailed(siteUrl);
      });
      return null;
    }
    return responseUser;
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
    if (isDisposed) return;
    switch (result) {
      case AccountDisconnected(:final lease):
        lease.commit(() {
          _connectErrors[siteUrl] = message;
          _notify();
        });
      case AccountDisconnectionFailed() ||
          AccountDisconnectionStale() ||
          AccountDisconnectionMissing():
        break;
    }
  }

  @override
  bool _publishFreshCurrentUser(
    String siteUrl,
    SiteLease lease,
    DiscourseInstance previous,
    CurrentUserReconciliation accepted,
  ) {
    bool ownsPublication() => _canAcceptCurrentUser(siteUrl) && lease.isCurrent;

    final finishTrackingChange = accepted.accountChanged
        ? _topicTracking.beginAccountChange(siteUrl)
        : () {};
    try {
      if (accepted.accountChanged) {
        _notificationPreferences.forget(siteUrl);
        _newTopicDismissals.forget(siteUrl);
        _liveSessions.clearRetry(siteUrl);
      }
      final user = accepted.user;
      final changed = previous.user != user || accepted.accountChanged;
      _profileWrites.currentUserAccepted(siteUrl, user);
      if (!ownsPublication()) return false;
      if (changed) {
        if (accepted.accountChanged) {
          accountActivity.forget(siteUrl);
          if (!ownsPublication()) return false;
          groups.forget(siteUrl);
          if (!ownsPublication()) return false;
          userDirectory.forget(siteUrl);
          if (!ownsPublication()) return false;
          badges.forget(siteUrl);
          if (!ownsPublication()) return false;
        }
        if (!ownsPublication() || !identical(_instanceAt(siteUrl), previous)) {
          return false;
        }
        _replaceInstance(
          previous,
          previous.copyWith(
            user: user,
            clearNotificationTotals: accepted.accountChanged,
          ),
        );
        if (!ownsPublication()) return true;
        if (accepted.accountChanged) {
          _liveSessions.accountChanged(siteUrl, lease);
        }
        if (!ownsPublication()) return true;
      }
      if (accepted.seedGroupedUnreadCounts) {
        _seedGroupedUnreadNotifications(siteUrl, user);
        if (!ownsPublication()) return true;
      }
      _notify();
      if (!ownsPublication()) return true;
      if (changed) instanceStore.save(List.of(_instances)).ignore();
      for (final observer
          in _pluginSession.capabilities<PluginCurrentUserObserver>()) {
        if (!ownsPublication()) break;
        _observePluginLifecycle(
          Future.sync(() => observer.pluginCurrentUserRefreshed(siteUrl)),
        );
      }
      return true;
    } finally {
      finishTrackingChange();
    }
  }

  void _applyUserDraftsMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?>) return;
    final count = jsonIntOrNull(data['draft_count']);
    if (count == null || count < 0) return;

    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null) return;

    _currentUsers.reconcilerFor(siteUrl).draftCountChanged();

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

  @override
  DiscourseUser _acceptDoNotDisturbSnapshot(
    String siteUrl,
    DiscourseUser user, {
    required bool isCurrent,
  }) {
    final until = doNotDisturb.acceptSnapshot(
      siteUrl,
      user.doNotDisturbUntil,
      isCurrent: isCurrent,
    );
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
      _profileWrites.hidePresenceFor(siteUrl);

  bool hidePresenceWriteInFlight(String siteUrl) =>
      _profileWrites.presenceInFlight(siteUrl);

  String? hidePresenceErrorFor(String siteUrl) =>
      _profileWrites.presenceErrorFor(siteUrl);

  Future<void> retryHidePresence(String siteUrl) =>
      _profileWrites.retryPresence(siteUrl);

  Future<void> toggleHidePresence(String siteUrl) =>
      _profileWrites.togglePresence(siteUrl);

  bool userStatusWriteInFlight(String siteUrl) =>
      _profileWrites.statusInFlight(siteUrl);

  Future<String?> setUserStatus(
    String siteUrl, {
    required String description,
    required String emoji,
    DateTime? endsAt,
    bool? pauseNotifications,
  }) => _profileWrites.setStatus(
    siteUrl,
    description: description,
    emoji: emoji,
    endsAt: endsAt,
    pauseNotifications: pauseNotifications,
  );

  Future<String?> clearUserStatus(String siteUrl) =>
      _profileWrites.clearStatus(siteUrl);

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
    for (final composer in _composerRegistry.live) {
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
      for (final composer in _composerRegistry.live) {
        unawaited(composer.flushDraftOnBackground());
      }
    }
    _observePluginLifecycle(_pluginSession.setForeground(foreground));
    _syncTracking();
    if (!foreground) return;
    doNotDisturb.checkExpirations();

    final resyncTracking =
        backgroundedAt != null &&
        _clock().difference(backgroundedAt) >= _topicTrackingResyncAfter;
    final instance = currentInstance;
    _liveSessions.resume(resyncTracking: resyncTracking);
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
        _checklists.isWriting(siteUrl, postId),
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
  );

  late final BookmarkLinkResolver _bookmarkLinks = BookmarkLinkResolver(
    bookmarks: _bookmarks,
    store: store,
    api: api.topicContent,
    credentials: credentials,
    servingForum: (target) => mostSpecificServingForum(
      _instances,
      target,
      siteUrl: (site) => site.url,
    )?.forum,
    pluginResolvers: () =>
        _pluginSession.capabilities<PluginBookmarkLinkResolver>(),
  );

  late final ChecklistTransactions _checklists = ChecklistTransactions(
    api: api.postMutations,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    isConnected: (siteUrl) => _instanceAt(siteUrl)?.isConnected == true,
    topicData: (siteUrl, lease) => _topicData.forLease(siteUrl, lease),
    bookmarkWriting: (siteUrl, lease, postId) =>
        _bookmarks.forLease(siteUrl, lease)?.postBookmarkWriting(postId) ??
        false,
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
      _topicNavigation.armHighlightIfLoaded();
      return changed;
    },
    lastPostResolved: _settleLastTopicPost,
    prepareCategories: (siteUrl, ids) async {
      final instance = _instanceAt(siteUrl);
      if (instance != null) await _taxonomy.ensureCategoryIds(instance, ids);
    },

    loadTimeout: topicLoadTimeout,
    bookmarkReads: (siteUrl, lease) => _bookmarks.forLease(siteUrl, lease)!,
    notificationReads: (siteUrl, lease, topicId) => _topicTracking
        .capture(siteUrl, lease: lease)
        ?.reconciler
        .beginNotificationRead(topicId),
  );
  late final _notificationPreferences = NotificationPreferenceTransactions(
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    topics: api.topicMutations,
    categories: api.categoryMutations,
    site: api.site,
    currentUsers: NotificationPreferenceCurrentUsers(
      read: (siteUrl) => _instanceAt(siteUrl)?.user,
      reconcilerFor: _currentUsers.reconcilerFor,
      publish: (siteUrl, lease, user) {
        if (!lease.isCurrent || isDisposed) return;
        final instance = _instanceAt(siteUrl);
        if (instance == null) return;
        _replaceInstance(instance, instance.copyWith(user: user));
        instanceStore.save(List.of(_instances)).ignore();
      },
    ),
    taxonomy: _taxonomy,
    trackingEffects: NotificationPreferenceTracking(
      forSite: (siteUrl) => _topicTracking.capture(siteUrl)?.reconciler,
      refresh:
          ({
            required siteUrl,
            required username,
            required lease,
            required tracking,
            required ticket,
            required requestCredentials,
            refreshCategoryPreferences,
          }) {
            _liveSessions.clearRetry(siteUrl);
            return _liveSessions.loadTracking(
              siteUrl: siteUrl,
              username: username,
              lease: lease,
              tracking: tracking,
              ticket: ticket,
              requestCredentials: requestCredentials,
              refreshCategoryPreferences: refreshCategoryPreferences,
            );
          },
    ),
    topicChanged: (siteUrl) {
      if (currentInstance?.url == siteUrl) _notify();
    },
    changed: _notify,
  );
  late final _topicActions = _TopicActionTransactions(
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    topics: api.topicMutations,
    topicData: _topicData,
    instanceAt: _instanceAt,
    changed: _notify,
    topicRemoved: (siteUrl, topicId) {
      if (currentInstance?.url == siteUrl &&
          currentContent?.topicId == topicId) {
        handleBack(canReturnToSidebar: false);
      }
    },
    mutationProblem: _postMutationPolicy.problem,
    failedMutation: _postMutationPolicy.failed,
  );
  late final _messageArchives = _MessageArchiveTransactions(
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    topics: api.topicMutations,
    topicData: _topicData,
    instanceAt: _instanceAt,
    topicFeeds: topicFeeds,
  );
  late final _topicNavigation = _TopicNavigationAttempts(
    focusedContext: () => focusedTabContext,
    store: store,
    topicData: _topicData,
    lifecycle: lifecycle,
    openPost: openCurrentTopicPost,
    changed: _notify,
    loadTimeout: topicLoadTimeout,
  );
  final _topicListRevealRequests = StreamController<int>.broadcast(sync: true);

  TopicDetail? get currentTopic => focusedTabContext.currentTopic;

  bool get currentTopicSummary => focusedTabContext.currentTopicSummary;

  bool get currentTopicSummaryLoading =>
      focusedTabContext.currentTopicSummaryLoading;

  List<int> get currentTopicStreamIds =>
      focusedTabContext.currentTopicStreamIds;

  List<int> get currentPostIds => focusedTabContext.currentPostIds;

  late final _readerProjections = TopicReaderProjections(store);

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
      _topicNavigation.requestHighlight(
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
  BookmarkLinkAction? cachedTopicBookmarkLink(String url) =>
      _bookmarkLinks.cachedTopicBookmarkLink(url);

  /// Resolves the clicked link without selecting its forum, tab, or topic.
  Future<BookmarkLinkAction?> resolveBookmarkLink(
    String url, {
    Bookmark? targetBookmark,
  }) => _bookmarkLinks.resolveBookmarkLink(url, targetBookmark: targetBookmark);

  Future<bool> openInAppLink(
    String url, {
    String? title,
    PluginLinkOrigin origin = PluginLinkOrigin.inApp,
    void Function()? onNavigated,
  }) async {
    if (openCorePageUrl(url)) {
      onNavigated?.call();
      return true;
    }
    if (await openPluginUrl(url, origin: origin, onNavigated: onNavigated)) {
      return true;
    }
    final destination = _routeForLink(url, specializedTitle: title);
    if (destination == null || _isCorePageLink(destination.route)) return false;
    final handled = _openResolvedCoreLink(
      destination,
      _CoreLinkIntent.ordinary,
    );
    if (handled) onNavigated?.call();
    return handled;
  }

  bool openTopicUrl(String url) {
    final destination = _routeForLink(url);
    return destination != null &&
        destination.route.destination is TopicDestination &&
        _openResolvedCoreLink(destination, _CoreLinkIntent.ordinary);
  }

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

  ResolvedCoreLink? _routeForLink(
    String url, {
    String? title,
    String? specializedTitle,
  }) {
    final target = CoreLinkTarget.match(
      url,
      currentSiteUrl: currentInstance?.url,
      instances: _instances,
    );
    if (target == null) return null;
    final instance = target.instance;
    final decoded = target.decode(
      config: siteConfigFor(instance.url),
      homepage: target.isHomepage ? _homepageFor(instance) : null,
      title: title,
      specializedTitle: specializedTitle,
    );
    if (decoded == null) return null;
    return target.enrich(
      decoded,
      category: categoryFor(decoded.categoryId, siteUrl: instance.url),
      filterCategories: filterCategoriesFor(instance.url),
    );
  }

  bool openBadgeUrl(String url, {String? title, bool refresh = false}) {
    final destination = _routeForLink(url, title: title);
    return destination != null &&
        destination.route.destination is BadgeDestination &&
        _openResolvedCoreLink(
          destination,
          refresh ? _CoreLinkIntent.notification : _CoreLinkIntent.ordinary,
        );
  }

  bool openGroupUrl(String url) {
    final destination = _routeForLink(url);
    return destination != null &&
        destination.route.destination is GroupDestination &&
        _openResolvedCoreLink(destination, _CoreLinkIntent.ordinary);
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
      _topicNavigation.explicitTarget(tab.id);
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
      _topicNavigation.requestHighlight(
        siteUrl: siteUrl,
        topicId: topicId,
        postNumber: postNumber,
      );
    } else {
      _topicNavigation.clearHighlight(notify: false);
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

  bool isTopicPostHighlighted(String siteUrl, int topicId, int postNumber) =>
      _topicNavigation.isPostHighlighted(siteUrl, topicId, postNumber);

  int get topicNavigationRevision => focusedTabContext.topicNavigationRevision;

  /// Opens the post at progress position [index], counted from one: its place
  /// in the stream, or in a mega topic, whose stream is only the run read so
  /// far, its post number (TopicViewportSnapshot.progressTotal).
  Future<bool> jumpToCurrentTopicIndex(int index) =>
      _topicNavigation.jumpToCurrentTopicIndex(index);

  bool openCorePageUrl(String url) {
    final destination = _routeForLink(url);
    return destination != null &&
        _isCorePageLink(destination.route) &&
        _openResolvedCoreLink(destination, _CoreLinkIntent.ordinary);
  }

  bool openListUrl(String url, {String? title}) {
    final destination = _routeForLink(url, title: title);
    return destination != null &&
        destination.route.isTaxonomyList &&
        _openResolvedCoreLink(destination, _CoreLinkIntent.ordinary);
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
  }) => _loadTopic(
    topicId,
    slug,
    force: force,
    postNumber: postNumber,
    context: context ?? focusedTabContext,
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

  void _settleLastTopicPost(String siteUrl, int topicId, int postNumber) {
    final workspace = _workspace.forSite(siteUrl);
    if (workspace == null) return;
    var changed = false;
    final tabs = <ForumTab>[];
    for (final tab in workspace.tabs) {
      final route = tab.currentContent;
      if (route.topicId != topicId ||
          route.postNumber != TopicLink.lastPostNumber) {
        tabs.add(tab);
        continue;
      }
      changed = true;
      tabs.add(
        tab.copyWith(
          contentStack: [
            ...tab.contentStack.take(tab.contentStack.length - 1),
            ContentRoute(
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
            ),
          ],
          anchors: Map<String, ForumTabAnchor>.of(tab.anchors)
            ..remove(route.id),
        ),
      );
    }
    if (changed) _workspace.put(workspace.copyWith(tabs: tabs));
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
  ) => _notificationPreferences.updateTopic(siteUrl, topicId, level);

  Future<bool> updateCategoryNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
  ) => _notificationPreferences.updateCategory(siteUrl, categoryId, level);

  bool topicPinWriteInFlight(String siteUrl, int topicId) =>
      _topicActions.topicPinWriteInFlight(siteUrl, topicId);

  Future<String?> updateTopicPinPreference(
    String siteUrl,
    int topicId,
    bool pinned,
  ) => _topicActions.updateTopicPinPreference(siteUrl, topicId, pinned);

  Future<String?> updateMessageArchived(
    String siteUrl,
    int topicId,
    bool archived,
  ) => _messageArchives.update(siteUrl, topicId, archived);

  bool topicStatusWriteInFlight(String siteUrl, int topicId) =>
      _topicActions.topicStatusWriteInFlight(siteUrl, topicId);

  Future<String?> updateTopicStatus(
    String siteUrl,
    int topicId,
    TopicStatusProperty status,
    bool enabled,
  ) => _topicActions.updateTopicStatus(siteUrl, topicId, status, enabled);

  bool topicDeletionWriteInFlight(String siteUrl, int topicId) =>
      _topicActions.topicDeletionWriteInFlight(siteUrl, topicId);

  Future<String?> setTopicDeleted(String siteUrl, int topicId, bool deleted) =>
      _topicActions.setTopicDeleted(siteUrl, topicId, deleted);

  bool topicUnreadWriteInFlight(String siteUrl, int topicId) =>
      _topicReads.resetInFlight(siteUrl, topicId);

  Future<String?> markTopicUnread(String siteUrl, int topicId) async {
    if (isDisposed || instanceFor(siteUrl)?.isConnected != true) return null;
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null) return null;
    final lease = lifecycle.capture(siteUrl);
    final tab = activeTabId;
    final route = currentContent;
    String? failure;
    final tracking = _topicTracking.capture(siteUrl, lease: lease);
    await _topicReads.reset(
      siteUrl,
      topicId,
      lease: lease,
      onChanged: _notify,
      write: () async {
        final credential = await _credentialForWrite(siteUrl, lease: lease);
        if (isDisposed || !lease.isCurrent) return;
        if (credential.failure case final failure?) throw failure;
        await credential.request!.run(
          () => api.pluginTransport.pluginWriteJson(
            siteUrl: siteUrl,
            path: '/t/$topicId/timings.json?last=1',
            method: 'DELETE',
            apiKey: credential.apiKey!,
            body: const {},
          ),
        );
      },
      accepted: () async {
        if (tracking?.isCurrent != true) return;
        tracking!.markLastPostUnread(
          topicId,
          math.max(0, topic.highestPostNumber - 1),
        );
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
        if (tracking.isCurrent &&
            currentInstance?.url == siteUrl &&
            activeTabId == tab &&
            identical(currentContent, route) &&
            route?.topicId == topicId) {
          handleBack(canReturnToSidebar: false);
        }
        if (tracking.isCurrent) {
          await _topicData.forLease(siteUrl, lease)?.refresh(topicId, slug: '');
        }
      },
      onError: (error, stackTrace) {
        if (error is WriteException) {
          failure = lease.isCurrent ? error.message : null;
        } else if (lease.isCurrent && !isDisposed) {
          failure = const WriteException(WriteFailure.unreachable).message;
        }
      },
    );
    return failure;
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
    final tracking = _topicTracking.capture(siteUrl, lease: lease);
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
      tracking?.markRead(topicId, position);
      if (tracking?.isCurrent == true && currentInstance?.url == siteUrl) {
        _notifyLiveChange();
      }
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
    final pending = context._reader!.pendingAfter(
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
    final pending = context._reader!.pendingBefore(
      context._currentPostWindow(),
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

  late final _RetainedComposerRegistry _composerRegistry =
      _RetainedComposerRegistry(_composerDrafts);

  ComposerController? get composerRevealTarget =>
      _composerRegistry.revealTarget;

  /// Explicit draft selections reveal even an already selected minimized editor.
  int get composerRevealRevision => _composerRegistry.revealRevision;
  late final _composerOpeningHost = _ShellComposerOpeningHost(this);
  late final _composerOpening = ComposerOpeningOwner(
    presentation: _composerOpeningHost,
    metadata: _composerOpeningHost,
    drafts: _composerDrafts,
    credentials: credentials,
    categories: api.categories,
    queries: api.topicComposerQueries,
  );

  late final _existingTopicOpening = ExistingTopicComposerOpeningOwner(
    editors: _ShellExistingTopicOpeningEditors(this),
    store: store,
    drafts: _composerDrafts,
    credentials: credentials,
    content: api.topicContent,
  );

  late final _ComposerSubmissionOwner _composerSubmissions =
      _ComposerSubmissionOwner(this);

  // Commands target the selected forum; async continuations keep the exact
  // composer that started them even if the user changes forums or drafts.
  ComposerController? get _composer =>
      _composerRegistry.selected(currentInstance?.url);

  /// Selects a retained draft without replacing its editor or history.
  void selectComposer(ComposerController composer) {
    if (!_composerRegistry.select(composer, siteUrl: currentInstance?.url)) {
      return;
    }
    _notify();
    composer.focus.requestFocus();
  }

  /// Every open draft remains account scoped, independently of reader tabs.
  Iterable<ComposerController> get liveComposers => _composerRegistry.live;

  // Reported after every frame the reader moves; kept off the facade so a
  // resize or dock drag does not re-run every shell selector.
  final _readerContentBounds = FrameSafeValueNotifier<Rect?>(null);

  late final ComposerDraftCoordinator _composerDrafts =
      ComposerDraftCoordinator(
        localStore: drafts,
        localDraftSite: (siteUrl) {
          final instance = _instanceAt(siteUrl);
          return DraftStore.accountSiteKey(
            siteUrl,
            instance == null ? 'anonymous' : instance.localDraftAccount,
          );
        },
        persistence: api.composerPersistence,
        draftsApi: api.drafts,
        lifecycle: lifecycle,
        credentials: credentials,
        readClientId: authenticator.clientId,
        isDisposed: () => isDisposed,
        isCurrentComposer: (composer) => _composerRegistry.owns(composer),
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
          _composerRegistry.remove(composer);
          _notify();
        },
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
          !isDisposed && (target.isPlugin || _composerRegistry.owns(composer)),
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
    final heldMessage = _composerRegistry
        .forSite(siteUrl)
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
    _composerRegistry.add(composer);
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
    final origin = NewTopicOpeningOrigin(
      siteUrl: instance.url,
      lease: lifecycle.capture(instance.url),
      tabId: tabId,
      feedId: feedId,
      content: currentContent,
      route: route,
      defaultFeedId: instance.defaultDestination.id,
      revealContent: revealContent,
      hasSourceRoute: sourceRoute != null,
    );
    final plan = await _composerOpening.prepareNewTopic(
      origin,
      allocateDraftKey: () => _newDraftKey(ComposerDraft.newTopicDraftKey),
      topicTitle: () => appL10n.newTopic,
      listedDraft: listedDraft,
    );
    if (plan == null ||
        !_composerOpening.isCurrent(plan) ||
        !_replaceComposer()) {
      return;
    }
    final composer = _buildTextComposer(
      plan.target,
      persistsDraft: true,
      minimumRequiredTags: plan.category?.minimumRequiredTags ?? 0,
    );
    _composerRegistry.add(composer);
    if (revealContent) _mobilePane = MobilePane.content;
    final enrichment = _composerOpening.start(plan, composer);
    _notify();
    await enrichment;
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
    if (!await _composerOpening.prepareReplacement() || !sourceIsCurrent()) {
      return;
    }

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
    _composerRegistry.add(composer);
    _notify();
    _composerDrafts.startNewDraft(composer);
    if (!lease.isCurrent ||
        !_composerRegistry.owns(composer) ||
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
      if (!await _composerOpening.prepareReplacement()) {
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
      _composerRegistry.add(composer);
      _notify();
      _composerDrafts.startNewDraft(composer);
    }

    try {
      await _composerDrafts.restoreTaskFor(composer);
    } catch (_) {}
    if (!forumActive ||
        !lease.isCurrent ||
        !_composerRegistry.owns(composer) ||
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
    if (!lease.isCurrent || !_composerRegistry.owns(composer)) {
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
  ) => _composerOpening.changeCategory(composer, categoryId);

  ExistingTopicOpeningOrigin? _existingTopicOpeningOrigin(
    ShellTabContext? context,
  ) {
    final document = context ?? focusedTabContext;
    if (!document.isCurrent || !identical(document.shell, this)) return null;
    final siteUrl = currentInstance?.url;
    final route = document.currentContent;
    if (siteUrl == null || route?.topicId == null) return null;
    return ExistingTopicOpeningOrigin(
      siteUrl: siteUrl,
      lease: document.lease!,
      tabId: document.tabId,
      reader: _ShellExistingTopicOpeningReader(document),
      route: route!,
      topic: document.currentTopic,
      canReply: document.canReplyHere,
    );
  }

  void openReply({
    int? replyToPostNumber,
    String? replyToUsername,
    bool? replyingToWhisper,
    UserDraft? listedDraft,
    ShellTabContext? context,
  }) {
    final origin = _existingTopicOpeningOrigin(context);
    if (origin == null) return;
    final plan = _existingTopicOpening.prepareReply(
      origin,
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper: replyingToWhisper,
      listedDraft: listedDraft,
    );
    if (plan != null) _presentReplyOpening(plan);
  }

  ComposerController? _presentReplyOpening(ReplyOpeningPlan plan) {
    switch (plan) {
      case ReuseReplyOpeningPlan():
        selectComposer(plan.composer);
        _existingTopicOpening.reuseReply(plan);
        return plan.composer;
      case CreateReplyOpeningPlan():
        if (!_replaceComposer()) return null;
        final composer = _buildTextComposer(plan.target, persistsDraft: true);
        _composerRegistry.add(composer);
        _notify();
        _existingTopicOpening.startReply(plan, composer);
        return composer;
    }
  }

  Future<void> openQuote(
    Post post,
    String quote, {
    ShellTabContext? context,
  }) async {
    final origin = _existingTopicOpeningOrigin(context);
    if (origin == null) return;
    final plan = _existingTopicOpening.prepareQuote(origin, post, quote);
    if (plan == null) return;
    final composer = plan.composer ?? _presentReplyOpening(plan.reply!);
    if (composer != null) {
      await _existingTopicOpening.insertQuote(plan, composer, quote);
    }
  }

  void openEdit(Post post, {String? focusText, ShellTabContext? context}) {
    final origin = _existingTopicOpeningOrigin(context);
    if (origin == null) return;
    final plan = _existingTopicOpening.prepareEdit(
      origin,
      post,
      category: categoryFor(origin.topic?.categoryId, siteUrl: origin.siteUrl),
      focusText: focusText,
    );
    if (plan == null) return;
    unawaited(_ensureTopicComposerCapabilities(origin.siteUrl));
    if (!_replaceComposer()) return;
    // Published edits must never overwrite an unfinished reply's draft key.
    final composer = _buildTextComposer(
      plan.target,
      minimumRequiredTags: plan.minimumRequiredTags,
    );
    _composerRegistry.add(composer);
    _notify();
    unawaited(_existingTopicOpening.loadEditBody(plan, composer));
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
    } catch (error) {
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

    return _saveTopicMetadata(
      siteUrl: siteUrl,
      topicId: topicId,
      command: _TopicTitleCommand(nextTitle, originalTitle ?? detail.title),
    );
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
    return _saveTopicMetadata(
      siteUrl: siteUrl,
      topicId: topicId,
      command: _TopicCategoryCommand(detail.title, categoryId, detail.tags),
    );
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
    _composerRegistry.add(
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
    return _saveTopicMetadata(
      siteUrl: siteUrl,
      topicId: topicId,
      command: _TopicTagsCommand(tags),
    );
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
    } catch (_) {}
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

  late final _PostMutationPolicy _postMutationPolicy = _PostMutationPolicy(
    store: store,
    instanceFor: _instanceAt,
    selectedSite: () => currentInstance?.url,
    isDisposed: () => isDisposed,
  );

  late final _SelectedPostModeration _selectedPostModeration =
      _SelectedPostModeration(
        store: store,
        api: api.postMutations,
        credentials: credentials,
        lifecycle: lifecycle,
        topicData: _topicData,
        policy: _postMutationPolicy,
        changed: _notify,
      );

  bool topicPostSelectionEnabled(String siteUrl, int topicId) =>
      _selectedPostModeration.topicPostSelectionEnabled(siteUrl, topicId);

  Set<int> selectedTopicPostIds(String siteUrl, int topicId) =>
      _selectedPostModeration.selectedTopicPostIds(siteUrl, topicId);

  bool isTopicPostSelected(String siteUrl, int topicId, int postId) =>
      _selectedPostModeration.isTopicPostSelected(siteUrl, topicId, postId);

  List<Post> selectedTopicPosts(String siteUrl, int topicId) =>
      _selectedPostModeration.selectedTopicPosts(siteUrl, topicId);

  bool topicPostSelectionWriteInFlight(String siteUrl, int topicId) =>
      _selectedPostModeration.topicPostSelectionWriteInFlight(siteUrl, topicId);

  void setTopicPostSelectionEnabled(
    String siteUrl,
    int topicId,
    bool enabled,
  ) => _selectedPostModeration.setTopicPostSelectionEnabled(
    siteUrl,
    topicId,
    enabled,
  );

  void toggleTopicPostSelected(String siteUrl, int topicId, int postId) =>
      _selectedPostModeration.toggleTopicPostSelected(siteUrl, topicId, postId);

  void selectAllLoadedTopicPosts(String siteUrl, int topicId) =>
      _selectedPostModeration.selectAllLoadedTopicPosts(siteUrl, topicId);

  void clearSelectedTopicPosts(String siteUrl, int topicId) =>
      _selectedPostModeration.clearSelectedTopicPosts(siteUrl, topicId);

  Future<PostMutationOutcome> deleteSelectedTopicPosts(
    String siteUrl,
    int topicId,
  ) => _selectedPostModeration.deleteSelectedTopicPosts(siteUrl, topicId);

  Future<PostMutationOutcome> mergeSelectedTopicPosts(
    String siteUrl,
    int topicId,
  ) => _selectedPostModeration.mergeSelectedTopicPosts(siteUrl, topicId);

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

  PostMutationOutcome? _topicPostMoveBlock(
    TopicPostMoveTarget target, {
    List<int>? postIds,
    bool newTopic = false,
  }) => _postMutationPolicy.moveBlock(
    target,
    postIds: postIds,
    newTopic: newTopic,
  );

  String? _topicPostMoveRefusal(
    TopicPostMoveTarget target, {
    List<int>? postIds,
    bool newTopic = false,
  }) => switch (_topicPostMoveBlock(
    target,
    postIds: postIds,
    newTopic: newTopic,
  )) {
    null => null,
    PostMutationRetired() => _obsoleteTopicPostMove,
    _ => const WriteException(WriteFailure.forbidden).message,
  };

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
    } catch (error) {
      return (
        destinations: const <TopicMoveDestination>[],
        error:
            _topicPostMoveRefusal(target) ??
            const WriteException(WriteFailure.unreachable).message,
      );
    }
  }

  Future<PostMoveOutcome> moveSelectedTopicPostsToExisting(
    TopicPostMoveTarget target,
    int destinationTopicId, {
    bool chronologicalOrder = false,
  }) => _selectedPostModeration.moveSelectedTopicPostsToExisting(
    target,
    destinationTopicId,
    chronologicalOrder: chronologicalOrder,
  );

  Future<PostMoveOutcome> moveSelectedTopicPostsToNew(
    TopicPostMoveTarget target, {
    required String title,
    int? categoryId,
    List<int> tagIds = const [],
  }) => _selectedPostModeration.moveSelectedTopicPostsToNew(
    target,
    title: title,
    categoryId: categoryId,
    tagIds: tagIds,
  );

  bool canChangeSelectedTopicPostOwner(String siteUrl, int topicId) =>
      _selectedPostModeration.canChangeSelectedTopicPostOwner(siteUrl, topicId);

  Future<PostMutationOutcome> changeSelectedTopicPostOwner(
    TopicPostOwnerTarget target,
    String username,
  ) => _selectedPostModeration.changeSelectedTopicPostOwner(target, username);

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

  bool _ownsTopicPostOwnerTarget(TopicPostOwnerTarget target) =>
      !isDisposed && target._lease.isCurrent;

  PostMutationOutcome? _topicPostOwnerRefusal(
    TopicPostOwnerTarget target,
    List<int> postIds,
    String username,
  ) => _postMutationPolicy.ownerRefusal(target, postIds, username);

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

  late final _PostCommandOwner _postCommands = _PostCommandOwner(this);

  Future<PostMutationOutcome> changeTopicPostOwner(
    TopicPostOwnerTarget target,
    String username,
  ) => _postCommands.run(_ChangePostOwner(target, username));

  Future<PostMutationOutcome> deletePost(Post post) async {
    if (!post.canDelete) return _PostCommandOwner._invalidTarget;
    final siteUrl = currentInstance?.url;
    final lease = siteUrl == null ? null : lifecycle.capture(siteUrl);
    final editing = switch (_composer?.target) {
      PostEditingComposerTarget(:final editingPostId)
          when editingPostId == post.id =>
        _composer,
      TaxonomyEditComposerTarget(:final firstPostId)
          when firstPostId == post.id =>
        _composer,
      _ => null,
    };

    final outcome = await _postCommands.run(_DeletePost(post));

    if (outcome is PostMutationAccepted &&
        lease?.isCurrent == true &&
        _composerRegistry.owns(editing)) {
      closeComposer(composer: editing);
    }
    return lease?.isCurrent == false
        ? _postMutationPolicy.retired(outcome)
        : outcome;
  }

  bool canPermanentlyDeletePost(Post post) {
    final topic = currentTopic;
    return topic != null && _canPermanentlyDeletePost(topic, post);
  }

  bool _canPermanentlyDeletePost(TopicDetail topic, Post post) =>
      _topicActions._canPermanentlyDeletePost(topic, post);

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

  PostMutationOutcome? _permanentPostDeletionBlock(
    PostPermanentDeleteTarget target,
  ) => _topicActions._permanentPostDeletionBlock(target);

  String? _permanentPostDeletionRefusal(PostPermanentDeleteTarget target) =>
      switch (_permanentPostDeletionBlock(target)) {
        null => null,
        PostMutationRetired() => _obsoletePermanentPostDeletion,
        _ => appL10n.thisPostCannotBePermanentlyDeleted,
      };

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
    } catch (error) {
      if (!lease.isCurrent || isDisposed) {
        return _obsoletePermanentPostDeletion;
      }

      return const WriteException(WriteFailure.unreachable).message;
    }
  }

  Future<PostMutationOutcome> permanentlyDeletePost(
    PostPermanentDeleteTarget target,
  ) async {
    if (!target.deletesTopic) {
      return _postCommands.run(_PermanentlyDeleteReply(target));
    }
    return _topicActions.permanentlyDeleteTopic(target);
  }

  Future<PostMutationOutcome> recoverPost(Post post) =>
      _postCommands.run(_RecoverPost(post));

  Future<PostMutationOutcome> setPostWiki(Post post, bool wiki) =>
      _postCommands.run(_SetPostWiki(post, wiki));

  bool canLockPost(Post post) =>
      currentInstance?.user?.staff == true && post.userId != null;

  Future<PostMutationOutcome> setPostLocked(Post post, bool locked) =>
      _postCommands.run(_SetPostLocked(post, locked));

  bool canUnhidePost(Post post) =>
      currentInstance?.user?.staff == true && post.hidden;

  Future<PostMutationOutcome> unhidePost(Post post) =>
      _postCommands.run(_UnhidePost(post));

  bool canTogglePostType(Post post) =>
      currentInstance?.user?.staff == true && !post.isWhisper;

  Future<PostMutationOutcome> togglePostType(Post post) =>
      _postCommands.run(_TogglePostType(post));

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
    } catch (error) {
      if (!lease.isCurrent) return _obsoletePostNotice;

      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(releasePost);
    }
  }

  late final FlagTransactions _flags = FlagTransactions(
    store: store,
    api: api.postMutations,
    credentials: credentials,
    lifecycle: lifecycle,
    topicData: _topicData,
    siteContextFor: (siteUrl) => FlagSiteContext(
      connected: _instanceAt(siteUrl)?.isConnected == true,
      catalog: _postActionCatalogs[siteUrl] ?? const SitePostActionCatalog(),
      minimumMessageLength: siteConfigFor(siteUrl).minPersonalMessagePostLength,
    ),
    changed: _notify,
  );

  Future<String?> createPostFlag(
    String siteUrl,
    Post post,
    PostFlagType flagType, {
    String? message,
  }) => _flags.createPost(siteUrl, post, flagType, message: message);

  bool topicFlagWriteInFlight(String siteUrl, int topicId) =>
      _flags.topicWriting(siteUrl, topicId);

  Future<String?> createTopicFlag(
    String siteUrl,
    TopicDetail topic,
    PostFlagType flagType, {
    String? message,
  }) => _flags.createTopic(siteUrl, topic, flagType, message: message);

  Future<String?> togglePostChecklist({
    required String siteUrl,
    required int topicId,
    required Post post,
    required PostChecklistTarget target,
    required bool checked,
  }) => _checklists.toggle(
    siteUrl: siteUrl,
    topicId: topicId,
    post: post,
    target: target,
    checked: checked,
  );

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
    } catch (error) {
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

  @override
  BookmarkTargetHost bookmarkTarget(BookmarkTargetType targetType) =>
      _bookmarks.bookmarkTarget(targetType);

  Topic _prepareTopicForStore(
    String siteUrl,
    Topic incoming,
    TopicFeedReadStamp? versionAtDispatch,
  ) => _topicData
      .forSite(siteUrl)
      .actionRowFromRead(
        versionAtDispatch?.actions ?? _topicData.forSite(siteUrl).actionEpoch,
        _bookmarks
            .forSite(siteUrl)
            .prepareRow(
              _topicTracking
                      .existing(siteUrl)
                      ?.project(_topicReads.project(siteUrl, incoming)) ??
                  _topicReads.project(siteUrl, incoming),
              versionAtDispatch?.bookmarks,
            ),
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

  Future<void> loadLikers(int postId, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;
    await _previews.loadLikers(instance, postId);
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
    } catch (error) {
      rethrow;
    }
  }

  bool _replaceComposer() =>
      _composerRegistry.replaceSelected(currentInstance?.url);

  void closeComposer({ComposerController? composer}) {
    if (!_composerRegistry.close(composer ?? _composer)) return;
    _notify();
  }

  bool hideComposerForClose(ComposerController composer) {
    if (!_composerRegistry.owns(composer) || !composer.beginClose()) {
      return false;
    }
    _notify();
    return true;
  }

  void restoreComposerAfterFailedClose(ComposerController composer) {
    if (!_composerRegistry.owns(composer) || composer.isDisposed) return;
    composer.cancelClose();
    _notify();
  }

  Future<bool> finishComposerDraftRestore(ComposerController composer) =>
      _composerDrafts.finishRestore(composer);

  /// Preserves a draft before closing its composer. False leaves
  /// the session open for retry or an explicit discard choice by the UI.
  Future<bool> prepareComposerForClose(ComposerController composer) async {
    if (!_composerRegistry.owns(composer)) return true;
    if (_composerHasPendingOperation(composer)) return false;
    if (!composer.canSaveDraft) {
      return !composer.hasChanges && !composer.metadataChanged;
    }
    if (!await finishComposerDraftRestore(composer)) return false;
    if (!_composerRegistry.owns(composer)) return true;
    if (_composerHasPendingOperation(composer)) return false;
    if (composer.hasUnappliedDraft && !composer.hasChanges) return true;

    if (composer.hasChanges || composer.localDraftFailed) {
      await composer.flushDraft();
    }
    await composer.finishDraftSaves();
    return !_composerRegistry.owns(composer) ||
        (!_composerHasPendingOperation(composer) &&
            !composer.localDraftFailed &&
            !composer.draftPersistencePending);
  }

  bool _composerHasPendingOperation(ComposerController composer) =>
      ComposerOpeningOwner.hasPendingOperation(composer);

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
  }) async {
    final result = await _composerSubmissions.submit(
      composer ?? _composer,
      onPreparationNotice,
    );
    _presentComposerSubmission(result);
  }

  Future<void> recheckComposer({ComposerController? composer}) async {
    final result = await _composerSubmissions.recheck(composer ?? _composer);
    _presentComposerSubmission(result);
  }

  void _presentComposerSubmission(_SubmissionResult result) {
    if (result is! _CompletedSubmission) return;
    final attempt = result.attempt;
    final target = attempt.target;
    final lease = attempt.lease;
    if (isDisposed || !lease.isCurrent) return;
    if (result.metadata case final metadata?) {
      if (target case ExistingTopicComposerTarget(:final topicId)) {
        _updateTopicRouteMetadata(
          target.siteUrl,
          topicId,
          metadata.title,
          metadata.categoryId,
        );
      }
    }
    if (isDisposed || !lease.isCurrent) return;
    if (result is! _SubmissionAccepted) return;
    final composer = attempt.editor;
    final retained =
        _composerRegistry.owns(composer) && composer.ownsSubmission(attempt);
    if (result.acceptance is! _SubmissionEnqueued && retained) {
      _composerRegistry.closeSubmitted(composer);
    }
    _notify();
    if (isDisposed || !lease.isCurrent) return;
    switch (result.acceptance) {
      case _SubmissionTopic(:final topicId, :final slug, :final title):
        if (target is! TopicCreationComposerTarget) return;
        if (target.isPrivateMessage) {
          _messageArchives.refreshFolders(
            target.siteUrl,
            lease: lease,
            personal: const [MessageListMode.sent],
            group: const [MessageListMode.inbox],
            groupNames: {
              for (final name in (target.targetRecipients ?? '').split(','))
                if (name.trim().isNotEmpty) name.trim(),
            },
          );
        }
        if (!retained || isDisposed || !lease.isCurrent) return;
        final workspace = _workspace.forSite(target.siteUrl);
        final tabId =
            workspace?.tabById(attempt.sourceTabId ?? '')?.id ??
            workspace?.activeTabId;
        if (currentInstance?.url == target.siteUrl && activeTabId == tabId) {
          _openTopic(topicId, slug, title);
          if (!lease.isCurrent || isDisposed) return;
          if (target.originFeedId case final origin? when target.isNewTopic) {
            unawaited(loadFeed(origin, force: true));
          }
        } else if (tabId != null) {
          final tab = workspace?.tabById(tabId);
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
      case _SubmissionReply(:final refresh):
        if (refresh && target is ReplyComposerTarget) {
          unawaited(
            _topicData
                .forLease(target.siteUrl, lease)
                ?.refresh(target.topicId, slug: target.slug),
          );
        }
      case _SubmissionEnqueued() || _SubmissionEdited():
        break;
    }
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

  @override
  DiscourseInstance? _instanceAt(String url) {
    for (final instance in _instances) {
      if (instance.url == url) return instance;
    }
    return null;
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

  Future<void> loadUserCard(
    String username, {
    bool force = false,
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;
    await _previews.loadUserCard(instance, username, force: force);
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

  final Map<String, _ComposerIdentityResolution> _composerIdentities = {};

  _ComposerIdentityResolution _composerIdentityFor(String siteUrl) {
    final existing = _composerIdentities[siteUrl];
    if (existing != null && existing.isCurrent) return existing;
    existing?.retire();
    final owner = _ComposerIdentityResolution(
      session: AccountRequestSession(siteUrl, lifecycle.capture(siteUrl)),
      credentials: credentials,
      authenticated: _instanceAt(siteUrl)?.isConnected == true,
      search: api.search,
      lookups: api.lookups,
      pluginHashtagTypes: plugins.registry.pluginHashtagWireTypes,
      onChanged: (artwork) {
        cooking.contextChanged(siteUrl);
        if (artwork) {
          for (final composer in _composerRegistry.forSite(siteUrl)) {
            composer.text.artworkArrived();
          }
        }
      },
    );
    if (isDisposed) owner.retire();
    return _composerIdentities[siteUrl] = owner;
  }

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
  }) => _composerIdentityFor(siteUrl).searchHashtags(term);

  ComposerPills _composerPills(ComposerTarget target) =>
      _composerIdentityFor(target.siteUrl).pills(target.mentionTopicId);

  ComposerRecipientSearch messageRecipientSearch(String siteUrl) {
    final lease = lifecycle.capture(siteUrl);
    return ComposerRecipientSearch(
      siteUrl: siteUrl,
      sourceIdentity: this,
      lease: lease,
      isSourceCurrent: () => !accountSessionDisposed,
      search: (term) async {
        try {
          final session = AccountRequestSession(siteUrl, lease);
          final credential = _instanceAt(siteUrl)?.isConnected == true
              ? await session.credentials(credentials)
              : session.anonymousCredentials();
          if (!lease.isCurrent) return const FoundUsersAndGroups();
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
        } catch (error) {
          return const FoundUsersAndGroups();
        }
      },
    );
  }

  Future<FoundUsersAndGroups> _searchMentions({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) => _composerIdentityFor(siteUrl).searchMentions(term, topicId);

  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) => _composerIdentityFor(siteUrl).searchUsers(term, topicId);

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
      _currentUsers.freshUserFor(siteUrl);

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
      search.selectSite(
        siteUrl,
        username: currentInstance?.user?.username,
        authenticated: currentInstance?.isConnected == true,
        logSearchQueries: config.logSearchQueries,
      );
    }
    for (final composer in _composerRegistry.forSite(siteUrl)) {
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
      switch (result) {
        case AccountConnected(instance: final connected):
          _connectErrors.remove(instance.url);
          unawaited(_refreshOne(connected));
          unawaited(_customSidebar.ensure(instance.url));
        case AccountConnectionCancelled():
          _connectErrors.remove(instance.url);
        case AccountConnectionFailed(
          :final message,
          :final refreshSignedOutPresentation,
        ):
          _connectErrors[instance.url] = message;
          if (refreshSignedOutPresentation &&
              currentInstance?.url == instance.url) {
            unawaited(
              RequestIntent.background().run(
                () => _presentation.ensureAppearance(instance.url),
              ),
            );
          }
        case AccountConnectionStale() || AccountConnectionMissing():
          break;
      }
    } finally {
      if (_connectingSiteUrl == instance.url) _connectingSiteUrl = null;
      final held = _instanceAt(instance.url);
      if (held?.isConnected == true && !_currentUsers.isFresh(instance.url)) {
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
    return switch (result) {
      AccountDisconnected() => true,
      AccountDisconnectionFailed() ||
      AccountDisconnectionStale() ||
      AccountDisconnectionMissing() => false,
    };
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
      final lease = lifecycle.capture(replacement.url);
      final user = _acceptDoNotDisturbSnapshot(
        replacement.url,
        replacement.user!,
        isCurrent: true,
      );
      applied = replacement.copyWith(user: user);
      _seedGroupedUnreadNotifications(replacement.url, user);
      _currentUsers.markConnectedUserFresh(replacement.url, lease);
      _profileWrites.currentUserAccepted(replacement.url, user);
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
    _newTopicDismissals.forget(siteUrl);
    _bookmarks.forget(siteUrl);
    _checklists.forget(siteUrl);
    _topicData.forget(siteUrl);
    siteImages.forget(siteUrl);
    videoThumbnails.forget(siteUrl);
    pdfThumbnails.forget(siteUrl);
    _workspace.remove(siteUrl);
    _rotatedWorkspaces.remove(siteUrl);
    search.forget(siteUrl);
    _composerRegistry.forgetSite(siteUrl);

    accountActivity.forget(siteUrl);
    draftList.forget(siteUrl);
    userSummary.forget(siteUrl);
    groups.forget(siteUrl);
    userDirectory.forget(siteUrl);
    badges.forget(siteUrl);
    preferences.forget(siteUrl);
    store.forget(siteUrl);
    _cookingContextOwner?.rebindStoreReferences(siteUrl);

    _selectedPostModeration.forget(siteUrl);
    _flags.forget(siteUrl);
    _notificationPreferences.forget(siteUrl);
    _currentUsers.forget(siteUrl);
    _topicActions.forget(siteUrl);
    _messageArchives.forget(siteUrl);
    _topicNavigation.forgetSite(siteUrl);
    _topicReads.forget(siteUrl);

    _taxonomy.forget(siteUrl);
    _topicTracking.forget(siteUrl);
    _liveSessions.clearRetry(siteUrl);
    _topicComposerCapabilities.remove(siteUrl);
    _postActionCatalogs.remove(siteUrl);
    _customSidebar.forget(siteUrl);
    _notificationFeeds.forget(siteUrl);
    _sitePresentation?.forget(siteUrl);
    _pluginSiteConfigListenables.remove(siteUrl)?.dispose();
    _composerIdentities.remove(siteUrl)?.retire();
    _connectErrors.remove(siteUrl);
    _unavailableForums.remove(siteUrl);
    _retryingUnavailableForums.remove(siteUrl);
    _basicInfoRefreshes.remove(siteUrl);

    _backgroundRetention.releaseSite(siteUrl);
    final forgetPlugins = _pluginSession
        .forget(siteUrl)
        .whenComplete(() => _backgroundRetention.releaseSite(siteUrl));
    _observePluginLifecycle(forgetPlugins);
    topicFeeds.forget(siteUrl);
    doNotDisturb.forget(siteUrl);
    userStatuses.forget(siteUrl);
    _profileWrites.forget(siteUrl);
    _liveSessions.forget(siteUrl);
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
      username: instance.user?.username,
      authenticated: instance.isConnected,
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
      );
    }
    _syncTracking();
    _syncTopicChannels();
    _liveSessions.retryTracking(instance.url);
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

  @override
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);

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

  void replaceOpeningGroupName({
    required String siteUrl,
    required String? tabId,
    required String previousName,
    required Group group,
  }) {
    if (previousName == group.name) return;
    final workspace = _workspace.forSite(siteUrl);
    final tab = workspace?.tabById(tabId ?? '');
    if (workspace == null || tab == null) return;
    final username = _instances
        .where((site) => site.url == siteUrl)
        .firstOrNull
        ?.user
        ?.username;
    final updated = tab.rewriteRoutes((content) {
      final route = content.groupRoute;
      if (route?.groupName?.toLowerCase() != previousName.toLowerCase()) {
        return content;
      }
      final renamed = route!.isPlugin
          ? GroupRoute.plugin(
              groupName: group.name,
              owner: route.pluginOwner!,
              section: route.section!,
              subsection: route.subsection,
            )
          : GroupRoute.detail(
              group.name,
              section: route.section!,
              subsection: route.subsection,
            );
      return ContentRoute.group(
        renamed,
        title: group.label,
        feedPath: renamed.topicFeedPath(username) ?? content.feedPath,
      ).withDisplay(
        icon: content.icon,
        subtitle: content.subtitle,
        color: content.color,
      );
    });
    if (identical(updated, tab)) return;
    _workspace.put(
      workspace.copyWith(
        tabs: [
          for (final item in workspace.tabs) item.id == tab.id ? updated : item,
        ],
      ),
    );
    _notify();
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
    unawaited(
      focusedTabContext._transitionTopicList(
        const BrowseTopicListCategory(null),
      ),
    );
  }

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
  }) => unawaited(
    focusedTabContext._transitionTopicList(
      BrowseTopicListCategory(category, keepTopicOpen: keepTopicOpen),
    ),
  );

  List<String> _topicListFilterTagNames(String siteUrl, ContentRoute? route) =>
      TopicListTransitions.tagNames(
        route,
        listedTopics:
            (topicFeeds.feedFor(siteUrl, route?.id ?? '')?.topicIds ??
                    const <int>[])
                .map((id) => store.read<Topic>(siteUrl, id))
                .whereType<Topic>(),
        knownTags: _taxonomy.knownTagsFor(siteUrl),
      );

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

    final retained = _composerRegistry
        .forSite(siteUrl)
        .where((composer) => composer.target.draftKey == draft.key)
        .firstOrNull;
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
    _composerOpening.dispose();
    _existingTopicOpening.dispose();
    _instanceRail.retire();
    _bookmarks.dispose();
    _checklists.dispose();
    _topicData.dispose();
    _readerProjections.dispose();
    // Queue the final local draft before lifecycle invalidation without
    // entering the normal remote-sync callback.
    for (final composer in _composerRegistry.live) {
      _composerDrafts.preservePendingLocally(composer);
    }
    _discoverSites?.dispose();
    _cookingContextOwner?.dispose();
    for (final owner in _composerIdentities.values) {
      owner.retire();
    }
    _composerIdentities.clear();
    unawaited(cooking.dispose());

    // A window can close in the frame immediately after a selection or a
    // scroll. Keep the latest local choice and anchor durable, but never start
    // hydration while tearing the controller down.
    _workspace.dispose();
    _topicNavigation.dispose();
    _topicPropertyRequests.dispose();
    unawaited(_topicListRevealRequests.close());
    _notificationPreferences.dispose();
    _currentUsers.dispose();
    _topicActions.dispose();
    _messageArchives.dispose();
    _newTopicDismissals.dispose();
    _profileWrites.dispose();
    _notificationFeeds.dispose();
    _selectedPostModeration.dispose();
    _flags.dispose();
    _topicReads.dispose();
    _customSidebar.dispose();
    for (final instance in _instances) {
      lifecycle.invalidate(instance.url);
    }
    _taxonomy.dispose();
    _topicTracking.dispose();
    _liveSessions.dispose();
    updates.dispose();
    accountActivity.dispose();
    doNotDisturb.dispose();
    userStatuses.dispose();
    _previews.dispose();
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
    _observePluginLifecycle(closePluginSession);
    if (_ownsPlugins) {
      final closeOwnedPlugins = closePluginSession
          .onError((_, _) {})
          .then((_) => plugins.close());
      _pluginTeardownFuture = closeOwnedPlugins;
      _observePluginLifecycle(closeOwnedPlugins);
    } else {
      _pluginTeardownFuture = closePluginSession;
    }
    globalSearch.dispose();
    search.dispose();
    _searchHistory.dispose();

    for (final listenable in _pluginSiteConfigListenables.values) {
      listenable.dispose();
    }
    _pluginSiteConfigListenables.clear();
    final presentation = _sitePresentation;
    if (presentation != null) {
      presentation.removeListener(_notify);
      presentation.dispose();
    }
    _composerRegistry.dispose();
    _readerContentBounds.dispose();
    if (ownsApi) api.close();
    super.dispose();
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

final class _ShellProfileCurrentUser implements ProfileCurrentUser {
  _ShellProfileCurrentUser(this._shell);

  final ShellController _shell;

  @override
  ProfileUserSnapshot? snapshotFor(String siteUrl) {
    final instance = _shell._instanceAt(siteUrl);
    return instance == null
        ? null
        : ProfileUserSnapshot(
            user: instance.user,
            statusEnabled: instance.config.userStatusEnabled,
          );
  }

  @override
  CurrentUserReconciler reconcilerFor(String siteUrl) =>
      _shell._currentUsers.reconcilerFor(siteUrl);

  @override
  Future<void> refresh(String siteUrl, String apiKey, SiteLease lease) async {
    await _shell._currentUsers.refresh(
      siteUrl,
      apiKey,
      lease: lease,
      force: true,
    );
  }

  @override
  void confirmPresence(String siteUrl, bool hidden) {
    final instance = _shell._instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null) return;
    _shell._replaceInstance(
      instance,
      instance.copyWith(user: user.withHidePresence(hidden)),
    );
  }

  @override
  void confirmStatus(String siteUrl, int userId, UserStatus? status) =>
      _shell._applyOwnUserStatus(siteUrl, userId, status);

  @override
  void persist() =>
      _shell.instanceStore.save(List.of(_shell._instances)).ignore();
}

final class _ShellComposerOpeningHost
    implements ComposerOpeningPresentation, ComposerOpeningMetadata {
  _ShellComposerOpeningHost(this._shell);

  final ShellController _shell;

  @override
  ComposerController? get selectedComposer => _shell._composer;

  @override
  bool get canCreateTopicHere => _shell.canCreateTopicHere;

  @override
  bool owns(ComposerController composer) =>
      _shell._composerRegistry.owns(composer);

  @override
  bool isCurrentOrigin(NewTopicOpeningOrigin origin) =>
      _shell.currentInstance?.url == origin.siteUrl &&
      _shell.activeTabId == origin.tabId &&
      _shell.currentFeedId == origin.feedId &&
      _shell.currentContent == origin.content;

  @override
  Future<void>? confirmReplacement(ComposerController composer) =>
      _shell.confirmComposerReplacement?.call(composer);

  @override
  void publishOpening() => _shell._notify();

  @override
  TopicCategory? categoryFor(String siteUrl, int? categoryId) =>
      _shell.categoryFor(categoryId, siteUrl: siteUrl);

  @override
  List<TopicCategory> categoriesFor(String siteUrl) =>
      _shell.topicComposerCategories(siteUrl);

  @override
  void mergeCategories(String siteUrl, List<TopicCategory> categories) =>
      _shell._taxonomy.mergeCategories(siteUrl, categories);

  @override
  Future<void> ensureForOpening(String siteUrl) async {
    await Future.wait<void>([
      if (!_shell._topicComposerCapabilities.containsKey(siteUrl))
        _shell._ensureTopicComposerCapabilities(siteUrl),
      if (_shell._taxonomy.needsCategoryLoad(siteUrl))
        _shell.loadCategories(siteUrl),
    ]);
  }

  @override
  TopicComposerCapabilities capabilitiesFor(String siteUrl) =>
      _shell.topicComposerCapabilities(siteUrl);

  @override
  Future<TopicTagSearch> searchTags(ComposerController composer, String term) =>
      _shell.searchComposerTags(composer, term);
}

final class _ShellExistingTopicOpeningReader
    implements ExistingTopicOpeningReader {
  _ShellExistingTopicOpeningReader(this._document);

  final ShellTabContext _document;

  @override
  bool isCurrentRoute(ContentRoute route) =>
      _document.isCurrent && identical(_document.currentContent, route);
}

final class _ShellExistingTopicOpeningEditors
    implements ExistingTopicOpeningEditors {
  _ShellExistingTopicOpeningEditors(this._shell);

  final ShellController _shell;

  @override
  ComposerController? get selectedComposer => _shell._composer;

  @override
  Iterable<ComposerController> forSite(String siteUrl) =>
      _shell._composerRegistry.forSite(siteUrl);

  @override
  bool owns(ComposerController composer) =>
      _shell._composerRegistry.owns(composer);
}
