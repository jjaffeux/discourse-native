# Tooltip migration audit

Audited `lib`, every bundled module in `lib/src/plugins`, compatibility packages,
and the full profile. The table records every changed app tooltip file; counts
are migrated constructor sites, not the number of rendered controls. Reusable
toolbar/row adapters can serve many controls. All original callbacks, keys,
permissions, focus nodes, asynchronous state and native menu owners remain.

Native IconButton/PopupMenuButton entries now use an outer `DTooltip` with
`labelTrigger: true` and an empty tooltip on the native control. The outer
semantics merges the accessible name with that control's action/state; it does
not create another button or menu. A redundant lightbox icon name was removed
to avoid announcing its label twice.

| App file | Direct Material / Raw tooltip sites | Native tooltip properties |
| --- | ---: | ---: |
| `lib/src/plugins/assign/assign_plugin.dart` | 1 | — |
| `lib/src/plugins/assign/assigned_group_view.dart` | — | 1 |
| `lib/src/plugins/chat/chat_channel_actions.dart` | — | 1 |
| `lib/src/plugins/chat/chat_channel_search.dart` | — | 3 |
| `lib/src/plugins/chat/chat_channel_view.dart` | 1 | 4 |
| `lib/src/plugins/chat/chat_pinned_bar.dart` | — | 1 |
| `lib/src/plugins/chat/chat_search_view.dart` | — | 1 |
| `lib/src/plugins/chat/chat_user_avatar.dart` | 1 | — |
| `lib/src/plugins/discourse_ai/ai_proofreading_plugin.dart` | 1 | — |
| `lib/src/plugins/discourse_events/event_calendar.dart` | 1 | 2 |
| `lib/src/plugins/discourse_events/event_card.dart` | 1 | 2 |
| `lib/src/plugins/discourse_events/event_composer.dart` | — | 1 |
| `lib/src/plugins/discourse_events/event_directory.dart` | — | 2 |
| `lib/src/plugins/discourse_events/event_participants.dart` | — | 1 |
| `lib/src/plugins/discourse_events/topic_calendar.dart` | 1 | 3 |
| `lib/src/plugins/gifs/gif_picker.dart` | 2 | 2 |
| `lib/src/plugins/local_dates/local_date_composer_sheet.dart` | — | 4 |
| `lib/src/plugins/poll/poll_composer_sheet.dart` | — | 4 |
| `lib/src/plugins/prometheus_alert_receiver/alert_tables.dart` | 1 | 1 |
| `lib/src/plugins/reactions/reaction_picker.dart` | — | 1 |
| `lib/src/plugins/voice/voice_call_widget.dart` | 1 | 2 |
| `lib/src/plugins/voice/voice_diagnostics_view.dart` | — | 3 |
| `lib/src/plugins/voice/voice_room_view.dart` | 1 | 7 |
| `lib/src/shell/add_instance_sheet.dart` | 2 | 1 |
| `lib/src/shell/bookmark_list.dart` | 1 | — |
| `lib/src/shell/bookmark_ui.dart` | — | 1 |
| `lib/src/shell/choice_menu.dart` | — | 1 |
| `lib/src/shell/composer_header.dart` | 1 | 4 |
| `lib/src/shell/composer_panel.dart` | 3 | 19 |
| `lib/src/shell/composer_quotes.dart` | 1 | — |
| `lib/src/shell/composer_reply_context.dart` | 1 | — |
| `lib/src/shell/diagnostics_panel.dart` | — | 7 |
| `lib/src/shell/draft_list.dart` | 1 | — |
| `lib/src/shell/emoji_picker.dart` | 2 | 4 |
| `lib/src/shell/forum_search.dart` | — | 3 |
| `lib/src/shell/forum_tabs_bar.dart` | — | 2 |
| `lib/src/shell/group/group_members_view.dart` | 2 | — |
| `lib/src/shell/groups_page.dart` | — | 1 |
| `lib/src/shell/image_grid.dart` | 1 | 1 |
| `lib/src/shell/inline_video.dart` | 1 | 4 |
| `lib/src/shell/instance_rail.dart` | 6 | — |
| `lib/src/shell/instance_sidebar.dart` | 1 | 1 |
| `lib/src/shell/lightbox.dart` | — | 1 |
| `lib/src/shell/main_content.dart` | 1 | — |
| `lib/src/shell/post_revision_history.dart` | 1 | — |
| `lib/src/shell/reaction_presentation.dart` | 1 | — |
| `lib/src/shell/shell_sheet.dart` | — | 2 |
| `lib/src/shell/stream_day_separator.dart` | 1 | — |
| `lib/src/shell/topic_filter_input.dart` | 2 | 2 |
| `lib/src/shell/topic_header_tags.dart` | 1 | — |
| `lib/src/shell/topic_inbox_header.dart` | 4 | — |
| `lib/src/shell/topic_inbox_row.dart` | 2 | — |
| `lib/src/shell/topic_list_indicators.dart` | 2 | — |
| `lib/src/shell/topic_progress.dart` | 1 | — |
| `lib/src/shell/topic_taxonomy_fields.dart` | 7 | — |
| `lib/src/shell/topic_title.dart` | 1 | — |
| `lib/src/shell/topic_view.dart` | 5 | — |
| `lib/src/shell/user_menu.dart` | 2 | — |
| `lib/src/shell/user_menu_button.dart` | 1 | 2 |
| `lib/src/shell/user_status.dart` | 1 | — |
| `lib/src/shell/user_status_editor.dart` | 1 | — |
| `lib/src/shell/users_page.dart` | — | 1 |
| `lib/src/shell/youtube_video.dart` | 1 | — |
| `lib/src/styleguide/styleguide_page.dart` | — | 2 |
| `lib/src/theme/app_theme.dart` | — | — |
| `lib/src/theme/d_button.dart` | — | — |

The 105 native properties are enumerated below with their original message
expressions. Line numbers describe the pre-migration snapshot, not final source.

```text
lib/src/shell/groups_page.dart:322: IconButton — 'Clear search'
lib/src/shell/choice_menu.dart:481: IconButton — 'Clear filter'
lib/src/shell/image_grid.dart:566: IconButton — label
lib/src/shell/lightbox.dart:972: IconButton.filled — tooltip
lib/src/shell/user_menu_button.dart:246: IconButton.filled — 'Sign up'
lib/src/shell/user_menu_button.dart:254: IconButton.filled — connecting ? 'Signing in…' : 'Sign in'
lib/src/shell/topic_filter_input.dart:380: IconButton — 'Clear filter'
lib/src/shell/topic_filter_input.dart:511: IconButton — 'Clear all filters'
lib/src/shell/composer_panel.dart:2713: IconButton — label
lib/src/shell/composer_panel.dart:2788: IconButton — 'Decrease image size'
lib/src/shell/composer_panel.dart:2801: IconButton — 'Increase image size'
lib/src/shell/composer_panel.dart:2814: IconButton — 'Move image outside gallery'
lib/src/shell/composer_panel.dart:2825: IconButton — 'Delete image'
lib/src/shell/composer_panel.dart:2851: IconButton — 'Save alt text'
lib/src/shell/composer_panel.dart:2923: IconButton — 'Grid gallery mode'
lib/src/shell/composer_panel.dart:2938: IconButton — 'Carousel gallery mode'
lib/src/shell/composer_panel.dart:2953: PopupMenuButton<_GalleryAddChoice> — 'Add images to gallery'
lib/src/shell/composer_panel.dart:3006: IconButton — 'Remove gallery, keep images'
lib/src/shell/composer_panel.dart:3136: IconButton — 'Add emoji'
lib/src/shell/composer_panel.dart:3192: IconButton — 'Formatting'
lib/src/shell/composer_panel.dart:3219: IconButton — 'Insert'
lib/src/shell/composer_panel.dart:3369: IconButton — forward
            ? 'Show more composer tools'
            : 'Show previous composer tools'
lib/src/shell/composer_panel.dart:3445: IconButton — 'Upload images'
lib/src/shell/composer_panel.dart:3548: IconButton — 'Retry upload'
lib/src/shell/composer_panel.dart:3556: IconButton — 'Remove upload'
lib/src/shell/composer_panel.dart:3563: IconButton — 'Remove upload'
lib/src/shell/composer_panel.dart:3578: IconButton — 'Cancel upload'
lib/src/shell/inline_video.dart:236: IconButton.filled — downloading ? 'Downloading video…' : 'Download video'
lib/src/shell/inline_video.dart:912: IconButton — isPlaying ? 'Pause' : 'Play'
lib/src/shell/inline_video.dart:925: IconButton — 'Exit full screen'
lib/src/shell/inline_video.dart:933: IconButton — 'Enter full screen'
lib/src/shell/composer_header.dart:194: IconButton — 'Composer options'
lib/src/shell/composer_header.dart:202: IconButton — 'Restore composer'
lib/src/shell/composer_header.dart:209: IconButton — 'Minimize composer'
lib/src/shell/composer_header.dart:215: IconButton — closeTooltip
lib/src/shell/forum_tabs_bar.dart:579: IconButton — 'Browse tabs'
lib/src/shell/forum_tabs_bar.dart:857: IconButton — label
lib/src/shell/emoji_picker.dart:249: IconButton — 'Close'
lib/src/shell/emoji_picker.dart:813: IconButton — 'Clear search'
lib/src/shell/emoji_picker.dart:849: PopupMenuButton<EmojiSkinTone> — 'Choose skin tone'
lib/src/shell/emoji_picker.dart:1021: IconButton — 'Clear frequently used emoji'
lib/src/shell/bookmark_ui.dart:1104: PopupMenuButton<_TopicBookmarksActionKind> — 'Post bookmark actions'
lib/src/shell/instance_sidebar.dart:1563: IconButton — 'Open ${destination.label}'
lib/src/shell/shell_sheet.dart:116: IconButton — 'Back'
lib/src/shell/shell_sheet.dart:129: IconButton — 'Close'
lib/src/shell/forum_search.dart:389: IconButton — 'Clear search'
lib/src/shell/forum_search.dart:408: IconButton — 'Advanced search'
lib/src/shell/forum_search.dart:564: IconButton — 'Clear recent searches'
lib/src/shell/users_page.dart:926: IconButton — 'Clear search'
lib/src/shell/add_instance_sheet.dart:55: IconButton — 'Close'
lib/src/shell/diagnostics_panel.dart:251: IconButton — 'Clear search'
lib/src/shell/diagnostics_panel.dart:424: IconButton — 'Back to diagnostics'
lib/src/shell/diagnostics_panel.dart:441: IconButton — frozen ? 'Resume live updates' : 'Freeze visible events'
lib/src/shell/diagnostics_panel.dart:448: IconButton — 'Copy filtered report'
lib/src/shell/diagnostics_panel.dart:454: IconButton — 'Clear history'
lib/src/shell/diagnostics_panel.dart:461: IconButton — 'Close diagnostics'
lib/src/shell/diagnostics_panel.dart:739: PopupMenuButton<String> — 'Filter by ${label.toLowerCase()}'
lib/src/styleguide/styleguide_page.dart:83: IconButton — 'Close styleguide'
lib/src/styleguide/styleguide_page.dart:178: IconButton — 'Clear search'
lib/src/plugins/prometheus_alert_receiver/alert_tables.dart:378: IconButton — label
lib/src/plugins/chat/chat_channel_actions.dart:213: IconButton — 'Open ${channel.title} menu'
lib/src/plugins/chat/chat_channel_search.dart:184: IconButton — 'Clear search'
lib/src/plugins/chat/chat_channel_search.dart:205: IconButton — 'Previous result'
lib/src/plugins/chat/chat_channel_search.dart:216: IconButton — 'Next result'
lib/src/plugins/chat/chat_pinned_bar.dart:232: IconButton — 'Pinned messages'
lib/src/plugins/chat/chat_search_view.dart:260: IconButton — 'Clear search'
lib/src/plugins/chat/chat_channel_view.dart:1751: IconButton — 'Quote selected messages'
lib/src/plugins/chat/chat_channel_view.dart:1779: IconButton — 'Move selected messages to another channel'
lib/src/plugins/chat/chat_channel_view.dart:1794: IconButton — count > ChatController.maximumBulkDeleteMessages
                    ? 'Select no more than '
                          '${ChatController.maximumBulkDeleteMessages} messages'
                    : 'Delete selected messages'
lib/src/plugins/chat/chat_channel_view.dart:1810: IconButton — 'Cancel selection'
lib/src/plugins/reactions/reaction_picker.dart:483: IconButton — 'More emojis'
lib/src/plugins/gifs/gif_picker.dart:107: IconButton — 'Close'
lib/src/plugins/gifs/gif_picker.dart:214: IconButton — 'Clear search'
lib/src/plugins/local_dates/local_date_composer_sheet.dart:70: IconButton — 'Close'
lib/src/plugins/local_dates/local_date_composer_sheet.dart:345: IconButton.filledTonal — 'Add timezone'
lib/src/plugins/local_dates/local_date_composer_sheet.dart:400: IconButton — 'Choose $label date'
lib/src/plugins/local_dates/local_date_composer_sheet.dart:428: IconButton — 'Choose $label time'
lib/src/plugins/voice/voice_call_widget.dart:86: IconButton — call.muted ? 'Unmute' : 'Mute'
lib/src/plugins/voice/voice_call_widget.dart:97: IconButton — 'Leave room'
lib/src/plugins/voice/voice_diagnostics_view.dart:158: IconButton — 'Clear search'
lib/src/plugins/voice/voice_diagnostics_view.dart:485: IconButton.outlined — state.enabled
                        ? 'Turn recording off before clearing'
                        : 'Clear capture'
lib/src/plugins/voice/voice_diagnostics_view.dart:652: IconButton — 'Back to capture'
lib/src/plugins/voice/voice_room_view.dart:707: PopupMenuButton<String> — 'Participant actions'
lib/src/plugins/voice/voice_room_view.dart:971: IconButton.filledTonal — label
lib/src/plugins/voice/voice_room_view.dart:1820: IconButton — 'Close'
lib/src/plugins/voice/voice_room_view.dart:1886: IconButton.filled — 'Send message'
lib/src/plugins/voice/voice_room_view.dart:2034: PopupMenuButton<VoiceRole> — 'Change role'
lib/src/plugins/voice/voice_room_view.dart:2049: IconButton — 'Remove member'
lib/src/plugins/voice/voice_room_view.dart:2080: IconButton.filledTonal — 'Add member'
lib/src/plugins/assign/assigned_group_view.dart:711: IconButton — query.ascending ? 'Descending' : 'Ascending'
lib/src/plugins/discourse_events/event_calendar.dart:223: IconButton — 'Previous ${_view.name}'
lib/src/plugins/discourse_events/event_calendar.dart:230: IconButton — 'Next ${_view.name}'
lib/src/plugins/discourse_events/event_composer.dart:371: IconButton — 'Choose date and time'
lib/src/plugins/discourse_events/event_participants.dart:113: IconButton — 'Search'
lib/src/plugins/discourse_events/event_directory.dart:407: PopupMenuButton<VoidCallback> — 'Calendar actions'
lib/src/plugins/discourse_events/event_directory.dart:465: IconButton — 'Search events'
lib/src/plugins/discourse_events/event_card.dart:176: PopupMenuButton<VoidCallback> — 'Event actions'
lib/src/plugins/discourse_events/event_card.dart:350: PopupMenuButton<VoidCallback> — 'Choose recurring attendance'
lib/src/plugins/discourse_events/topic_calendar.dart:379: IconButton — 'Previous ${_view == _CalendarView.agenda ? 'month' : _view.label.toLowerCase()}'
lib/src/plugins/discourse_events/topic_calendar.dart:386: IconButton — 'Next ${_view == _CalendarView.agenda ? 'month' : _view.label.toLowerCase()}'
lib/src/plugins/discourse_events/topic_calendar.dart:405: PopupMenuButton<_CalendarView> — 'Calendar view'
lib/src/plugins/poll/poll_composer_sheet.dart:83: IconButton — 'Close'
lib/src/plugins/poll/poll_composer_sheet.dart:337: IconButton — 'Move option up'
lib/src/plugins/poll/poll_composer_sheet.dart:342: IconButton — 'Move option down'
lib/src/plugins/poll/poll_composer_sheet.dart:349: IconButton — 'Remove option'
```

The old `theme/d_tooltip.dart` renderer was removed. Existing public DTooltip
and DButton consumers now resolve through `discourse_ui.dart` to the new shared
owner. The rail's remaining private `_RailTooltip` only supplies app avatar,
title, shortcut, logical side and existing timing; its custom RawTooltip,
transition, shape, hard-coded swatches and shadow were removed.

The styleguide uses the new public owner in eleven runnable examples and in
its migrated palette controls. It continues to identify Button as a separate
baseline component.

Retained alternatives:

- The fallback `AppTheme.tooltipTheme` styles framework-owned internal hints
  with the same palette and basic metrics. Native controls that expose their
  tooltip property have all been migrated. Framework-private text selection
  and picker internals remain with their native owners.
- Existing DButton/tool/action adapter `tooltip` properties already compose
  the shared DTooltip, so their caller-facing API and action dispatch remain.
- Vendored video-player and WebRTC example apps keep their native tooltips.
  They are third-party package examples, not application or bundled-plugin UI.
- Networking avatar data, user status strings and permissions stay in app
  adapters. Essential instructions remain inline; tooltips are supplementary.

Final read-only audit: zero direct `Tooltip(...)` or `RawTooltip(...)`
constructors in `lib`; zero nonempty native IconButton/PopupMenuButton tooltip
properties. All bundled plugin renderers are under that same `lib` audit.
