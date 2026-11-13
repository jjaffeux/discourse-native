/// Plugin compatibility boundary; plugins must not import the package's `src`.
library;

export 'discourse_plugin_composer.dart';
export 'discourse_plugin_contracts.dart';
export 'discourse_plugin_preferences.dart';
export 'discourse_plugin_reader.dart';
export 'discourse_ui.dart'
    show
        DSelectSize,
        DSelectChangeReason,
        DSelectValueChanged,
        DMultiSelectValueChanged,
        DSelectValueBuilder,
        DMultiSelectValueBuilder,
        DSelectTriggerBuilder,
        DSelectTriggerState,
        DSelectEntry,
        DSelectItem,
        DSelectOption,
        DSelectGroup,
        DSelectSeparator,
        DSelect,
        DSelectField,
        DMultiSelect;
export 'discourse_ui.dart' show monospaceTextStyle;
export 'src/foundation/read_dwell.dart';
export 'src/plugin_api/composer_sheet_header.dart';
export 'src/plugin_api/composer_sheet_layout.dart';
export 'src/plugin_api/plugin_runtime.dart';
export 'src/plugin_api/plugin_scope.dart';
export 'src/shell/adaptive_dialog_action.dart';
export 'src/shell/anchored_layout.dart' show AnchoredLayout;
export 'src/shell/animated_emoji.dart' show DAnimatedEmoji;
export 'src/shell/avatar_image.dart';
export 'src/shell/bookmark_ui.dart' show showPluginBookmarkMenu;
export 'src/shell/broken_image.dart' show BrokenImage;
export 'src/shell/category_icon.dart' show CategoryIcon;
export 'src/shell/code_block.dart' show CodeBlock, CodeBlockData, CodeLine;
export 'src/shell/composer/block_selection.dart' show ComposerBlockSelection;
export 'src/shell/composer/components/emoji.dart'
    show openEmojiPickerForComposer;
export 'src/shell/composer/components/link_dialog.dart'
    show showComposerLinkDialog;
export 'src/shell/composer/controller.dart' show ComposerController;
export 'src/shell/composer/drop.dart'
    show NativeDropTarget, composerUploadFilesFromDrop, dropContainsDirectory;
export 'src/shell/composer/embedded_editor.dart' show ComposerEmbeddedEditor;
export 'src/shell/composer/panel.dart' show ComposerEditor, ComposerUploadQueue;
export 'src/shell/composer/plugin_composer_host.dart';
export 'src/shell/composer/slash_menu.dart' show ComposerSlashAction;
export 'src/shell/content_reading_lane.dart'
    show
        ContentReadingLane,
        ContentReadingLaneBox,
        ContentReadingLaneBuilder,
        ContentReadingLaneGeometry;
export 'src/shell/cooked_html.dart';
export 'src/shell/desktop_header_menu.dart';
export 'src/shell/destination_bookmark_menu_item.dart'
    show DestinationBookmarkMenuItem;
export 'src/shell/dsa_notice_form.dart' show showIllegalContentReport;
export 'src/shell/emoji.dart' show EmojiImage;
export 'src/shell/emoji_picker.dart' show EmojiPickerAnchor, showEmojiPicker;
export 'src/shell/forum_search.dart' show ForumSearch;
export 'src/shell/forum_theme_surfaces.dart' show ForumWindowBackground;
export 'src/shell/group_flair.dart' show GroupFlairBadge;
export 'src/shell/header_notification_button.dart'
    show headerNotificationButton;
export 'src/shell/hover_action_toolbar.dart' show HoverActionButton;
export 'src/shell/hover_panel.dart' show HoverPanel, HoverPanelState;
export 'src/shell/inline_code.dart' show InlineCode;
export 'src/shell/inline_video.dart' show InlineVideo, InlineVideoData;
export 'src/shell/lightbox.dart'
    show
        LightboxGallery,
        LightboxImage,
        RemoteLightboxImage,
        showLightboxGallery;
export 'src/shell/list_boundary_shortcuts.dart'
    show ListBoundaryFocusExempt, ListBoundaryShortcuts;
export 'src/shell/mobile_footer_action.dart'
    show
        MobileFooterAction,
        MobileFooterActionController,
        MobileFooterActionScope;
export 'src/shell/notification_list.dart' show PluginNotificationsSection;
export 'src/shell/oneboxes/embedded.dart' show embeddedOneboxWidgetBuilder;
export 'src/shell/oneboxes/markup.dart' show digitsIn, oneLineText;
export 'src/shell/oneboxes/onebox_card.dart' show OneboxCard, OneboxData;
export 'src/shell/open_link.dart' show LinkTarget, openLink;
export 'src/shell/plugin_topic_reader.dart'
    show PluginTopicPost, PluginTopicHeader;
export 'src/shell/post_action_leading.dart' show PostActionLeading;
export 'src/shell/post_flag_editor.dart' show PostFlagEditor, showFlagEditor;
export 'src/shell/quote_panel.dart' show QuotePanel;
export 'src/shell/reaction_presentation.dart'
    show ReactionPill, ReactionPills, ReactionUsersList, ReactionUsersPanel;
export 'src/shell/relative_time.dart'
    show RelativeTimeBuilder, RelativeTimeText, relativeTime;
export 'src/shell/route_aware_selection_area.dart' show RouteAwareSelectionArea;
export 'src/shell/search_words.dart'
    show SearchWords, SearchText, searchSnippet;
export 'src/shell/shell_metrics.dart' show ShellLayout, shellHeaderHeight;
export 'src/shell/shell_sheet.dart'
    show ShellSheetActions, ShellSheetForm, showShellSheet;
export 'src/shell/site_emoji_image.dart' show SiteEmojiImage;
export 'src/shell/site_emoji_text.dart' show SiteEmojiText;
export 'src/shell/site_image.dart' show SiteImage;
export 'src/shell/skeleton_fill.dart' show SkeletonSurface, skeletonFill;
export 'src/shell/stream_day_separator.dart'
    show StreamChip, StreamDaySeparator;
export 'src/shell/time_gap.dart' show TimeGapNotice, timeGapDaysBetween;
export 'src/shell/title_bar.dart' show ShellTitleBar;
export 'src/shell/topic_corner_controls.dart' show TopicCornerControls;
export 'src/shell/topic_list_footer.dart' show TopicSourceFooter;
export 'src/shell/topic_list_view.dart'
    show TopicListLoadingSkeleton, TopicListRow, TopicListSeparator;
export 'src/shell/user_card_target.dart' show UserCardTarget;
export 'src/shell/user_menu.dart' show UserPresenceMenu;
export 'src/shell/user_menu_button.dart' show UserMenuButton;
export 'src/shell/user_status.dart' show UserStatusMessage;
export 'src/shell/youtube_video.dart'
    show YoutubeVideo, YoutubeVideoData, parseYoutubeTime, sanitizeYoutubeId;
export 'src/theme/d_icon.dart' hide DIconSetScope;
