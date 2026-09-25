# Chat channel sort and filter preferences

The drawer and full-page channel lists use independent public-channel,
starred-channel, and direct-message preferences. The sidebar inbox does not
read them; it orders by recent activity with its own filters. The lists'
Native menus save immediately through the existing `PUT /u/{username}.json`
user-options endpoint. Only the changed field is sent. The six fields are:

| Section | Filter | Sort |
| --- | --- | --- |
| Channels | `chat_channel_list_filter` | `chat_channel_list_sort` |
| Starred | `chat_channel_list_filter_starred` | `chat_channel_list_sort_starred` |
| DMs | `chat_channel_list_filter_dms` | `chat_channel_list_sort_dms` |

Core's database defaults are `all` for each filter, `alphabetical` for public
and starred channels, and `priority` for DMs. Advertised unknown values use
core's client fallbacks (`all` / `alphabetical`). Absent fields remain absent
through warm storage, disable their controls and cannot be written. A section
without either field keeps its previous native sidebar/drawer ordering.

## List rules

- `all` includes muted channels. `active` also includes them, but requires a
  last-message ID and timestamp at or after exactly 30 days before the clock.
  Thread activity does not advance this cutoff.
- `unread` includes unread messages, mentions, watched-thread unread counts,
  and, when threading is enabled, thread-overview entries at or after the
  membership's last-viewed time.
- `mentions` includes mentions and watched-thread unread counts. Ordinary
  unread DMs and ordinary unread threads do not satisfy it.
- Muted channels fail `unread` and `mentions`. An active channel in expanded
  Chat or full-page Chat is retained despite any filter.
- `recent_activity` sorts by last-message time, with channels without complete
  last-message identity after channels with messages. `priority` first groups
  urgent, unread, and read/muted channels, then uses that same recency order.
- Alphabetical order uses public slugs and DM titles, with channel ID as the
  final tie-break. Native retains its case-insensitive string ordering; web's
  browser-locale collation can differ for case, accents and punctuation. Starred
  alphabetical lists group public channels before DMs; other starred sorts cross
  both types.
- Drawer and full-page public/DM lists include starred channels.
  Preference-enabled DM lists show 50 rows after filtering and sorting; the
  drawer retains core's simple 50-row slice.

Show all temporarily bypasses one section's filter, preserving its stored
filter and selected sort. Reapply filter restores it without a request.
Drawer/full-page headings expose this action for any non-default filter. A filtered-out section retains its heading and options. A new filter
selection clears bypass, including reselecting the same filter. If the save
fails, the previous filter and bypass are restored. Changing sort leaves bypass
alone. Bypass ends when the account's plugin session is forgotten.

## Ownership and concurrency

`ChatChannelListPreferences` preserves wire values and per-field capability in
both the current-user plugin record and Chat's registered `ChatUserPreferences`
value. Its model and codec live under `lib/src/plugins/chat/`; core stores the
opaque value through `UserPreferencesPlugin` and does not recognize its wire
fields. `ChatChannelListController` owns optimistic overrides, request progress,
errors and bypass state per site/account. Independent field writes may overlap;
the same field is disabled while saving, as in core. Responses merge only the
field that was sent. Credential reads and completions check the account and
site lifecycle lease. A replaced account cannot inherit a previous request or
bypass state.

`PluginUserOptionsHost` delegates to the existing user-options API and commits
confirmed plugin data to the account's warm-start record. The shell replays
only preference commits newer than an in-flight session/bootstrap read over
that read's response, while accepting unrelated refreshed fields. Subsequent
fresh reads remain authoritative. The revision history retains only the latest
commit per field and is cleared at account/site retirement. Preference changes
notify Chat, not the shell facade.

The application sidebar DTO exposes a builder for additional Native header
actions. The existing Native Sidebar action slot, Dropdown Menu radio groups,
Buttons and Toasts own all interaction and geometry; the UI kit is unchanged.
Channel navigation and starring continue to use the existing route and
membership write paths.

## Upstream and verification

Reviewed against Discourse main `2ba63e29c65ea79225eb3d7c808645ee4b5b155e`
on September 16, 2026, including the Chat changes since September 14:

- [Channel list preferences, #43249](https://github.com/discourse/discourse/pull/43249),
  merged as `3dfc739016f9ee6523d91a5b6b28d0968ef028e6`.
- [Temporary filter bypass, #43503](https://github.com/discourse/discourse/pull/43503),
  merged as `721b600ce13b3ebb9ee64a2ad748617f9868b743`.
- The current `chat-channel-list-preferences` and `chat-channels-manager`
  services, sidebar initializer, channel-list filter toggle, constants,
  user-option initialization, serializers and saveable options.

Focused coverage lives in `chat_channel_list_test.dart`,
`chat_channel_list_controller_test.dart`, `chat_channel_list_widget_test.dart`,
`chat_channel_list_session_test.dart`, and the existing preference, API and
plugin-data suites. Existing Chat controller, drawer and shell suites protect
older-server ordering, membership changes and navigation. Run the repository
gates in `CLAUDE.md` after the focused checks.
