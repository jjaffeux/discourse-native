/// Plugin compatibility boundary; plugins must not import the package's `src`.
library;

export 'package:discourse_cooking/discourse_cooking.dart';

export 'src/app_shortcuts.dart' show primaryShortcutForPlatform;
export 'src/data/app_release.dart';
export 'src/data/discourse_api_contracts.dart'
    hide
        CategoryLoadResult,
        CategoryQueriesApi,
        ComposerPersistenceApi,
        DiscourseApiConfiguration,
        DiscourseApiLifecycle,
        DiscourseApiModels,
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
export 'src/data/origin_cooldown.dart' show OriginCooldown;
export 'src/data/plugin_transport.dart';
export 'src/data/serial_operation_queue.dart';
export 'src/data/site_preference_keys.dart'
    show SitePreferenceKey, SitePreferenceTail;
export 'src/data/store.dart' show Ref, Store, StorePolicy, Storable;
export 'src/data/store_diagnostics.dart' show reportStorageFailure;
export 'src/diagnostics/diagnostic_event.dart';
export 'src/diagnostics/diagnostics_controller.dart';
export 'src/diagnostics/diagnostics_persistence.dart';
export 'src/diagnostics/diagnostics_redactor.dart' show redactHomeDirectories;
export 'src/diagnostics/diagnostics_scope.dart' show DiagnosticsScope;
export 'src/diagnostics/topic_scroll_capture.dart';
export 'src/foundation/calendar_day.dart';
export 'src/foundation/clock_time.dart';
export 'src/foundation/count_label.dart';
export 'src/foundation/diagnostic_errors.dart' show reportImageError;
export 'src/foundation/frame_safe_notifier.dart'
    show FrameSafeNotifier, FrameSafeValueNotifier;
export 'src/foundation/loopback_host.dart';
export 'src/foundation/private_file_document.dart'
    show PrivateFileDocument, PrivateFileResult;
export 'src/foundation/private_file_permissions.dart';
export 'src/foundation/private_file_staging.dart';
export 'src/foundation/timezone_environment.dart' show TimezoneEnvironment;
export 'src/foundation/uri_path.dart' show tryUriPathSegments;
export 'src/models/bookmark.dart' show Bookmark, BookmarkTargetType;
export 'src/models/composer_upload.dart'
    show ComposerUploadResult, ComposerUploadType;
export 'src/models/content_route.dart';
export 'src/models/discourse_instance.dart' show DiscourseInstance;
export 'src/models/discourse_user.dart' show DiscourseUser;
export 'src/models/forum_workspace.dart' show ForumPanel, ForumTab;
export 'src/models/group_route.dart' show GroupRoute;
export 'src/models/json.dart';
export 'src/models/live_refresh_id.dart' show liveRefreshId;
export 'src/models/notification.dart'
    show DiscourseNotification, NotificationWireType;
export 'src/models/notification_totals.dart' show NotificationTotals;
export 'src/models/post.dart' show Post, TopicDetail;
export 'src/models/post_flag.dart' show PostFlagType;
export 'src/models/search_results.dart' show SearchExcerpt;
export 'src/models/sidebar.dart';
export 'src/models/site_config.dart';
export 'src/models/site_emoji.dart' show SiteEmojiCatalog;
export 'src/models/topic.dart' show Topic, TopicList;
export 'src/models/topic_feed.dart' show TopicFeed;
export 'src/models/user_card.dart' show UserCard;
export 'src/models/user_draft.dart' show UserDraft;
export 'src/models/user_flair.dart' show UserFlair;
export 'src/models/user_preferences.dart';
export 'src/models/user_status.dart'
    show UserStatus, UserStatusReference, userStatusesByUsername;
export 'src/plugin_api/background_retention.dart';
export 'src/plugin_api/bookmark_host.dart';
export 'src/plugin_api/composer_component.dart';
export 'src/plugin_api/composer_syntax.dart';
export 'src/plugin_api/cooking_plugin.dart';
export 'src/plugin_api/core_plugin_host.dart';
export 'src/plugin_api/discourse_model_codec.dart';
export 'src/plugin_api/emoji_usage.dart';
export 'src/plugin_api/global_search.dart';
export 'src/plugin_api/hashtag_kind.dart';
export 'src/plugin_api/live_channels.dart';
export 'src/plugin_api/notification_counters.dart';
export 'src/plugin_api/notification_feed_host.dart';
export 'src/plugin_api/notification_types.dart';
export 'src/plugin_api/plugin_data.dart';
export 'src/plugin_api/plugin_icon_catalog.dart';
export 'src/plugin_api/plugin_manifest.dart';
export 'src/plugin_api/plugin_runtime.dart';
export 'src/plugin_api/plugin_scope.dart';
export 'src/plugin_api/preserved_json.dart';
export 'src/plugin_api/reaction_presentation.dart';
export 'src/plugin_api/shell_extensions.dart';
export 'src/plugin_api/site_plugin_api.dart';
export 'src/plugin_api/timezone_host.dart';
export 'src/shell/adaptive_dialog_action.dart';
export 'src/shell/adaptive_shell.dart' show ShellLayout;
export 'src/shell/anchored_layout.dart' show AnchoredLayout;
export 'src/shell/avatar_image.dart';
export 'src/shell/bookmark_ui.dart' show showPluginBookmarkMenu;
export 'src/shell/choice_menu.dart' show ChoiceMenuAnchor, ChoiceMenuOption;
export 'src/shell/code_block.dart' show CodeBlock, CodeBlockData, CodeLine;
export 'src/shell/composer_autocomplete.dart' show ComposerSuggestionAction;
export 'src/shell/composer_block_selection.dart' show ComposerBlockSelection;
export 'src/shell/composer_controller.dart'
    show
        ComposerController,
        ComposerTargetKind,
        ComposerTargetPolicy,
        ComposerTargetRequest,
        ComposerUploadDisposition;
export 'src/shell/composer_drop.dart'
    show NativeDropTarget, composerUploadFilesFromDrop, dropContainsDirectory;
export 'src/shell/composer_embedded_editor.dart' show ComposerEmbeddedEditor;
export 'src/shell/composer_images.dart' show escapeImageAlt, flattenImageAlt;
export 'src/shell/composer_link.dart' show showComposerLinkDialog;
export 'src/shell/composer_marks.dart' show ComposerMark;
export 'src/shell/composer_panel.dart' show ComposerEditor, ComposerUploadQueue;
export 'src/shell/composer_slash_menu.dart' show ComposerSlashAction;
export 'src/shell/composer_upload_picker.dart'
    show
        ComposerFilePicker,
        ComposerImagePicker,
        pickComposerFiles,
        pickComposerImages;
export 'src/shell/content_reading_lane.dart'
    show
        ContentReadingLane,
        ContentReadingLaneBox,
        ContentReadingLaneBuilder,
        ContentReadingLaneGeometry;
export 'src/shell/cooked_dom.dart'
    show childWhere, childrenWhere, descendantWhere, descendantsWhere;
export 'src/shell/cooked_html.dart';
export 'src/shell/diagnostics_text.dart';
export 'src/shell/emoji.dart' show EmojiImage;
export 'src/shell/emoji_composer.dart' show openEmojiPickerForComposer;
export 'src/shell/emoji_picker.dart' show EmojiPickerAnchor, showEmojiPicker;
export 'src/shell/external_link.dart' show openExternalLink;
export 'src/shell/forum_search.dart' show ForumSearch;
export 'src/shell/global_search_models.dart'
    show GlobalSearchCondition, GlobalSearchContext;
export 'src/shell/group_flair.dart' show GroupFlairBadge;
export 'src/shell/header_notification_button.dart'
    show headerNotificationButton;
export 'src/shell/hover_action_toolbar.dart' show HoverActionButton;
export 'src/shell/hover_panel.dart' show HoverPanel, HoverPanelState;
export 'src/shell/image_decode.dart' show imageForCover, imagePhysicalPixels;
export 'src/shell/inline_action.dart' show InlineAction;
export 'src/shell/inline_code.dart' show InlineCode;
export 'src/shell/inline_video.dart' show InlineVideo, InlineVideoData;
export 'src/shell/lightbox.dart'
    show LightboxGallery, LightboxImage, UnavailableImage;
export 'src/shell/list_boundary_shortcuts.dart' show ListBoundaryShortcuts;
export 'src/shell/markdown_editing_controller.dart'
    show MarkdownEditingController;
export 'src/shell/markdown_highlight.dart'
    show
        CodeRanges,
        MarkdownRun,
        Md,
        markdownBlocks,
        markdownCodeRanges,
        markdownPairs,
        scanMarkdown,
        sharedMarkdownScan;
export 'src/shell/mobile_footer_action.dart'
    show
        MobileFooterAction,
        MobileFooterActionController,
        MobileFooterActionScope;
export 'src/shell/notification_list.dart' show PluginNotificationsSection;
export 'src/shell/oneboxes/embedded.dart' show embeddedOneboxWidgetBuilder;
export 'src/shell/oneboxes/markup.dart' show digitsIn, oneLineText;
export 'src/shell/oneboxes/onebox.dart' show OneboxCard, OneboxData;
export 'src/shell/open_link.dart' show LinkTarget, openLink;
export 'src/shell/pill.dart' show Pill;
export 'src/shell/platform.dart'
    show TouchPlatform, forumTabsEnabledForCurrentPlatform;
export 'src/shell/post_action.dart' show PostAction, PostActionPlacement;
export 'src/shell/post_flag_editor.dart' show PostFlagEditor;
export 'src/shell/quote_panel.dart' show QuotePanel;
export 'src/shell/reaction_presentation.dart'
    show ReactionPill, ReactionPills, ReactionUsersList, ReactionUsersPanel;
export 'src/shell/relative_time.dart'
    show RelativeTimeBuilder, RelativeTimeText, relativeTime;
export 'src/shell/route_aware_selection_area.dart' show RouteAwareSelectionArea;
export 'src/shell/shell_metrics.dart' show shellHeaderHeight;
export 'src/shell/shell_sheet.dart' show showShellSheet;
export 'src/shell/site_emoji_image.dart' show SiteEmojiImage;
export 'src/shell/site_emoji_text.dart' show SiteEmojiText;
export 'src/shell/site_image.dart' show SiteImage;
export 'src/shell/site_url.dart';
export 'src/shell/skeleton_fill.dart' show SkeletonSurface, skeletonFill;
export 'src/shell/stream_day_separator.dart' show StreamDaySeparator;
export 'src/shell/syntax.dart' show highlightLines;
export 'src/shell/time_gap.dart' show TimeGapNotice, timeGapDaysBetween;
export 'src/shell/title_bar.dart' show ShellTitleBar;
export 'src/shell/topic_list_footer.dart' show TopicSourceFooter;
export 'src/shell/topic_list_view.dart' show TopicListRow, TopicListSeparator;
export 'src/shell/user_card.dart' show UserCardTarget;
export 'src/shell/user_menu.dart' show UserPresenceMenu;
export 'src/shell/user_menu_button.dart' show UserMenuButton;
export 'src/shell/user_status.dart' show UserStatusMessage;
export 'src/shell/youtube_video.dart'
    show YoutubeVideo, YoutubeVideoData, parseYoutubeTime, sanitizeYoutubeId;
export 'src/theme/app_theme.dart';
export 'src/theme/d_icon.dart';
export 'src/theme/d_icons.dart';
export 'src/theme/d_native_icons.dart' show DNativeIcons;
export 'src/theme/discourse_typography.dart' show DiscourseTypography;
export 'src/ui/components/d_select.dart';
export 'src/ui/foundation/code_typography.dart' show monospaceTextStyle;
export 'src/utils/pagination.dart' show paginationPrefetchDistance;
