/// The part of the plugin SDK that compiles without the UI kit, the shell
/// controller, or a shell widget: wire models, parsers, plugin contracts, and
/// theme tokens. A plugin library that needs nothing else imports this rather
/// than `discourse_plugin_sdk.dart`, which re-exports all of it.
library;

export 'package:discourse_cooking/discourse_cooking.dart';

export 'src/app_shortcuts.dart' show primaryShortcutForPlatform;
export 'src/data/app_release.dart';
export 'src/data/cooking_plugin.dart';
export 'src/data/dashboard_report_source.dart';
export 'src/data/discourse_api_contracts.dart'
    hide
        CategoryLoadResult,
        CategoryQueriesApi,
        ComposerPersistenceApi,
        DiscourseApiConfiguration,
        DiscourseApiLifecycle,
        DiscourseApiModels,
        DsaNoticeConnection,
        DsaNoticesApi,
        DsaVerificationRequired,
        HttpBasicAuthenticationRequired,
        PostMutationsApi,
        ShellApiCapabilities,
        ShellLookupApi,
        ShellSearchApi,
        ShellSiteApi,
        SiteLookupApi,
        TagQueriesApi,
        TopicComposerQueriesApi,
        TopicContentApi,
        TopicMutationsApi,
        defaultDiscourseHashtagOrder,
        maximumDiscourseHashtagsPerRequest,
        maximumDiscourseSearchTermLength;
export 'src/data/live_channels.dart';
export 'src/data/origin_cooldown.dart' show OriginCooldown;
export 'src/data/plugin_transport.dart';
export 'src/data/preference_storage_scope.dart' show PreferenceStorage;
export 'src/data/serial_operation_queue.dart';
export 'src/data/site_preference_keys.dart'
    show
        ForgottenSites,
        SitePreferenceKey,
        SitePreferenceTail,
        SitePreferenceRetirement,
        OwnedSitePreferences,
        SitePreferenceIdentity,
        SitePreferenceScope,
        SitePreferenceValue;
export 'src/data/store.dart' show Ref, Store, StorePolicy;
export 'src/foundation/calendar_day.dart';
export 'src/foundation/clock_time.dart';
export 'src/foundation/count_label.dart';
export 'src/foundation/d_calendar_date.dart';
export 'src/foundation/elapsed_time.dart';
export 'src/foundation/frame_safe_notifier.dart'
    show FrameSafeNotifier, FrameSafeValueNotifier;
export 'src/foundation/icons/d_icon_data.dart';
export 'src/foundation/icons/d_icons.dart';
export 'src/foundation/icons/d_native_icons.dart' show DNativeIcons;
export 'src/foundation/loopback_host.dart';
export 'src/foundation/private_file_document.dart'
    show PrivateFileDocument, PrivateFileResult;
export 'src/foundation/private_file_permissions.dart';
export 'src/foundation/private_file_staging.dart';
export 'src/foundation/timezone_environment.dart' show TimezoneEnvironment;
export 'src/foundation/uri_path.dart' show tryUriPathSegments;
export 'src/models/bookmark.dart' show Bookmark, BookmarkTargetType;
export 'src/models/composer_metadata.dart';
export 'src/models/composer_upload.dart'
    show ComposerUploadResult, ComposerUploadType;
export 'src/models/content_route.dart';
export 'src/models/discourse_instance.dart'
    show DiscourseInstance, mostSpecificServingForum;
export 'src/models/discourse_model_codec.dart';
export 'src/models/discourse_user.dart' show DiscourseUser;
export 'src/models/emoji_usage.dart';
export 'src/models/forum_workspace.dart' show ForumPanel, ForumTab;
export 'src/models/group_route.dart' show GroupRoute;
export 'src/models/homepage_option.dart';
export 'src/models/json.dart';
export 'src/models/live_refresh_id.dart' show liveRefreshId;
export 'src/models/notification.dart'
    show DiscourseNotification, NotificationWireType;
export 'src/models/notification_counters.dart';
export 'src/models/notification_totals.dart' show NotificationTotals;
export 'src/models/plugin_data.dart';
export 'src/models/plugin_icon_catalog.dart';
export 'src/models/post.dart' show Post, TopicDetail;
export 'src/models/post_flag.dart' show PostFlagType;
export 'src/models/preserved_json.dart';
export 'src/models/search_results.dart' show SearchExcerpt;
export 'src/models/sidebar.dart';
export 'src/models/site_config.dart';
export 'src/models/site_emoji.dart' show SiteEmojiCatalog;
export 'src/models/storable.dart' show Storable;
export 'src/models/topic.dart'
    show Topic, TopicList, TopicRecommendations, TopicRecommendationSource;
export 'src/models/topic_feed.dart' show TopicFeed;
export 'src/models/topic_link.dart' show TopicLink;
export 'src/models/user_card.dart' show UserCard;
export 'src/models/user_draft.dart' show UserDraft;
export 'src/models/user_flair.dart' show UserFlair;
export 'src/models/user_preferences.dart';
export 'src/models/user_status.dart'
    show UserStatus, UserStatusReference, userStatusesByUsername;
export 'src/plugin_api/background_retention.dart';
export 'src/plugin_api/bookmark_host.dart';
export 'src/plugin_api/category_settings.dart';
export 'src/plugin_api/composer_component.dart';
export 'src/plugin_api/composer_syntax.dart';
export 'src/plugin_api/composer_target.dart'
    show
        ComposerTargetKind,
        ComposerTargetPolicy,
        ComposerTargetRequest,
        ComposerUploadDisposition;
export 'src/plugin_api/core_link_projection.dart';
export 'src/plugin_api/core_plugin_host.dart';
export 'src/plugin_api/global_search.dart';
export 'src/plugin_api/global_search_models.dart'
    show GlobalSearchCondition, GlobalSearchContext;
export 'src/plugin_api/hashtag_kind.dart';
export 'src/plugin_api/notification_feed_host.dart';
export 'src/plugin_api/notification_types.dart';
export 'src/plugin_api/plugin_manifest.dart';
export 'src/plugin_api/plugin_ui_scope.dart'
    show PluginOwnedServices, PluginServiceSelector, PluginUiScope;
export 'src/plugin_api/post_action.dart'
    show PostAction, PostActionGroup, PostActionPlacement, PostActionRole;
export 'src/plugin_api/reaction_presentation.dart';
export 'src/plugin_api/shell_extensions.dart';
export 'src/plugin_api/site_plugin_api.dart';
export 'src/plugin_api/timezone_host.dart';
export 'src/plugin_api/topic_reader.dart';
export 'src/shell/anchored_layout.dart' show AnchoredLayout;
export 'src/shell/composer/autocomplete.dart' show ComposerSuggestionAction;
export 'src/shell/composer/components/image_source.dart'
    show escapeImageAlt, flattenImageAlt;
export 'src/shell/composer/components/list_source.dart'
    show ComposerListItem, ComposerListBody, composerListItems;
export 'src/shell/composer/markdown_highlight.dart'
    show
        CodeRanges,
        MarkdownRun,
        Md,
        markdownBlocks,
        markdownCodeRanges,
        markdownPairs,
        scanMarkdown,
        sharedMarkdownScan;
export 'src/shell/composer/marks.dart' show ComposerMark;
export 'src/shell/composer/upload_picker.dart'
    show
        ComposerFilePicker,
        ComposerImagePicker,
        pickComposerFiles,
        pickComposerImages,
        pickComposerMedia;
export 'src/shell/cooked_dom.dart'
    show childWhere, childrenWhere, descendantWhere, descendantsWhere;
export 'src/shell/external_link.dart' show openExternalLink;
export 'src/shell/image_decode.dart' show imageForCover, imagePhysicalPixels;
export 'src/shell/oneboxes/markup.dart' show digitsIn, oneLineText;
export 'src/shell/platform.dart'
    show TouchPlatform, forumTabsEnabledForCurrentPlatform;
export 'src/shell/site_url.dart';
export 'src/shell/syntax.dart' show highlightLines;
export 'src/theme/app_theme.dart';
export 'src/theme/code_colors.dart';
export 'src/theme/discourse_colors.dart';
export 'src/theme/discourse_typography.dart' show DiscourseTypography;
export 'src/utils/pagination.dart'
    show
        ScrollPageTrigger,
        ScrollPagingGate,
        UserScrollGestures,
        paginationPrefetchDistance;
