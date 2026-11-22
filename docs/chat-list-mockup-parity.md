# Chat list, threads, channel panel and unread rows

Design reference: `discourse-native-mockups` commit
`ab471b37a455a6f038a11d5b1da2e2ae43cfa1a8` on `test-mobile-layout`, all of
it. The commit diff and the end state of `src/App.tsx` at that commit were
read; line numbers below are that file at that commit.

The mockup lists seeded chats. The app lists the account's real memberships,
tracking counts and last messages. Where the mockup seeds a value, the row
names the server field the app reads instead.

## Kit changes

The user chose "Extend the kit as needed" for this round on 2026-11-17.

| Change | Mockup item that needed it | Callers | Test and example |
| --- | --- | --- | --- |
| `DItemVariant.unread`: an Item that rests in `DTokens.unreadFill`, the accent at 9%, and gives way to hover, press and selection as a standard Item does | `UNREAD_FILL`, 56426: one fill for an unread chat, thread and notification | `ChatInboxRowSurface` for chats, threads and the way to the threads; `DMenuFeedRow` for notifications. No existing variant changed, so no other caller is redrawn | `test/d_item_unread_variant_test.dart`; styleguide Item, "Unread" |
| `DMenuFeedRow` passes that variant when `unread` | 53312–53318 | The header menu's notification and message rows | Same test; the existing "Header menu feed row" example is an unread row |
| `DTokens.unreadFill` | 56426 | The variant above | Same test |
| `DIcons.tableList`, Discourse's vendored `table-list` symbol | 56401: the By type mark | `ChatInboxFilterBar` | `test/chat_list_mockup_parity_test.dart` |

The channel panel, the picker and the side took no kit change. They are
composed from `showShellSheet(search: true)`, `SheetSearch`,
`SheetSearchHold`, `DSheetScrollBody`, `DItem`, `DToggle` and `DToggleGroup`
as they were.

One shell change came with the panel, which is the first sheet to open on its
field. `showShellSheet(search: true)` left no room for the grabber, which is
drawn over the sheet's top, so the field was drawn behind it. An untitled
sheet now starts 23 below its top, the grabber's own height.
`test/shell_sheet_test.dart` pins the field under the grabber.

## Itemized parity checklist

### Order and grouping

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 1 | Done | 55775–55785: in every group, what is unread first, then the rest, each part the most recent first | `chatInboxNewFirst` in `chat_inbox_order.dart` partitions the activity-ordered inbox projection, so each part keeps its recency. A chat is new when it is not muted and `tracking.unread_count` or `mention_count` is above zero | `chat_inbox_test.dart` "every group leads with what is new"; `chat_list_mockup_parity_test.dart` rendered order |
| 2 | Done | 55776–55785: what is muted goes last in its group, its news and all | The same partition closes with `membership.muted` chats | Same tests, channel 2 and "noisy" |
| 3 | Done | 55807–55822: as one list, unread and starred, unread, read and starred, read, muted | `chatInboxSections` passes `starredFirst` for Newest | `chat_inbox_test.dart`; parity test "marks what is private, muted and starred"; `mobile_shell_test.dart` "chat filters the mixed recent list" |
| 4 | Not applicable | 14941–14950: your own last message leaves nothing unread | The server owns unread counts; sending advances the reader's own read cursor there. The app adds no rule of its own | — |
| 5 | Done | 3462–3464, 55946–55958: a group shows its unread up to 10, never fewer than 4 rows, folds only when more than one row is over, keeps the open chat, never folds alone | `ChatInboxSectionSlice` with `isNew`, `few` 4 and `mostUnread` 10 | `chat_inbox_test.dart` "a group shows its unread up to ten before it folds" and the retained-row test |
| 6 | Done | 3493, 56019–56035: "View N unread & M read chats" or "View M read chats"; rooms keep "View N more" | `ChatInboxMore.hiddenUnread`, strings `chatViewUnreadAndRead`, `chatViewRead` | `chat_browse_parity_test.dart` folded page and sidebar; `chat_sidebar_search_test.dart` |
| 7 | Done | Diff 24461, 25911, 33121: the Recent / Unread switch is gone | `ChatInboxFilter.unreadOnly`, its switch, its projection branch and its empty message are removed | Parity test "the controls are the field, then the order as two marks" |

### The row

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 8 | Done | 56426, 56485–56503: an unread row boxed in the accent at 9%, radius 10, 2 by 4 outside and 12 inside, no rule under it; the open row keeps its tint and leading edge | `ChatInboxRowSurface`: the kit's unread Item at radius 10 inside a 2 by 4 inset with 12 inside; read and open rows are flush Items with the leading-accent selection | Parity test "an unread row is boxed"; capture `page-by-type.png` |
| 9 | Done | 56552–56580: name 14.5, unread 700 in strong ink, read 400 in the read-title ink, muted in muted ink | `ChatInboxRow` name styles; `DTokens.titleRead` | Parity test "a row says how much is new" |
| 10 | Done | 56583–56621: a star where no Starred heading says so, a lock on a private channel, a struck bell on a muted one | 10px marks after the name: `membership.starred` outside the Starred group, `chatable.read_restricted`, `membership.muted`. A person's status emoji keeps its place there | Parity test "marks what is private, muted and starred" |
| 11 | Done | 56623–56643: the count as a chip at the top right; a muted chat with unread shows a grey dot | `DBadge.unreadChip`; `DNotificationDot` in muted ink. The kit's dot is 8px where the mockup draws 7 | Same test |
| 12 | Done | 56464–56474, 56644–56661: the second line is always what was said last, 12.5 muted at 400 | `last_message` excerpt; the "N messages", "N unread threads" and "N new mentions" lines are removed | Parity tests; `chat_browse_parity_test.dart` "a row keeps what was last said" |
| 13 | Done, within the data | 56407–56421, 56461–56471: the face of whoever spoke, 16px; nothing before your own turn nor before the one person a conversation is with | `ChatSaidBy`. The channel index's `last_message` carries no author (`Chat::LastMessageSerializer`), so the face shows once the author is known: from a live message, a retained copy of the last message, or the conversation's members | Parity test "whoever spoke is a face before the line" |
| 14 | Done | 56424, 56662–56671: the time at the bottom right, 12 muted, in a tail column at least 56 wide | `ChatInboxRowWords`: both right-hand cells at least 56 wide and at most 45% of the row, so a long date in large text gives way first | Parity test; `shell_rebuild_isolation_test.dart` at a 208px sidebar |
| 15 | Done | 43787, 56511–56537: the side's row is the page's row | One `ChatInboxRow` with a `ChatInboxRowFrame`: 16 on the page, 8 inside a sidebar's own 8 | Parity test "the side draws the page's list"; capture `side-by-type.png` |
| 16 | Done | 43796–43846: the side's row keeps its menu under the pointer and on a held press | `ChatChannelMenu` around every row; its button as the Item's corner action on the side with a pointer | `chat_browse_parity_test.dart` star action from the sidebar |

### One list, its controls and what it leads to

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 17 | Done | 55709, 43787, 32874: the Chats page and chat's side draw one list component | `ChatListing` in `chat_listing.dart` lays out the rows; the page puts them in its lazy list and the sidebar in a sliver. It keeps the rebuild isolation both places had | Parity tests on both places; `chat_mobile_sidebar_test.dart` and `shell_rebuild_isolation_test.dart` rebuild pins |
| 18 | Done | 56387–56404, 4590–4625: the field "Find a chat" on a line of its own, then the order switch as two icons | `ChatListingControls`: `ChatFindField` over `ChatInboxFilterBar`, whose items are `DToggleGroupItem.iconOnly` named by tooltip and semantics | Parity test "the controls are the field" |
| 19 | Done | 30906–30924: on the side the controls stand 4, 4, 10 in on a wide window and 10, 10, 6 on a phone | `ChatSidebarInboxHeader` padding | `chat_search_entry_test.dart`, `mobile_drawer_structure_test.dart`, `chat_sidebar_search_test.dart` |
| 20 | Done | 25945–25947: the page and the side each keep their own words | `ChatInboxFilters.queryFor(ChatInboxPlace, site)` | Parity test "the side draws the page's list" |
| 21 | Done | Diff 4592, 33003: the Browse channels and Threads pills leave the head | `ChatInboxNavigation` and the page's secondary controls row are removed | `chat_browse_parity_test.dart` "inbox filters and navigation cards fit" |
| 22 | Done | 3422–3429, 55840–55856: each group under its icon and name; the first 12 under the controls, the rest 18 | `ChatInboxSectionHeading`, also over the voice rooms and the Results; the side no longer collapses groups | Captures; `chat_browse_parity_test.dart` alignment |
| 23 | Done, counting threads | 55857–55962, 55992–56006: a Threads row heads the channels with its count of new replies, boxed when something is new | `ChatInboxWayRow`. The channel index reports which threads have unread replies (`unread_thread_overview`), not how many replies, so the chip counts threads and the line reads "New replies in N threads" | Parity test "the way to the threads heads the channels" |
| 24 | Done | 55979–55991: in the one list the Threads row stands after what is unread and starred, or after all that is unread when no thread is new | `threadsAt` in `ChatListing` | Capture `page-newest.png` |
| 25 | Done | 56042–56051: a Browse channels row closes the channels | `ChatInboxWayRow`, which opens the channel panel over the page or the side it is on. The group is listed even with no channel in it, so an account in no channel can still reach them; the mockup's seeds always hold one | Parity test; `chat_sidebar_parity_test.dart` "the side is the one list" |
| 26 | Not applicable | 25553–25562: only the chats you are in are listed and counted | The inbox has always listed the account's memberships | — |
| 27 | Done, but for a reader with rooms and no chat | 43783–43857, 55789, 55826–55829, 56013–56017, 56041: chat's side is its controls over the one list, and the voice rooms close that list with the way to make one | `ChatSidebarInbox` lists the rooms as the page does, drawn as chats are. The desktop side's directory section (Chats, Channels, Threads) is removed, so Threads shows once, as the list's own row. Voice keeps a section of its own only where chat has no list to carry the rooms, see "The side" below | `sidebar_panel_tabs_test.dart` "the voice rooms close chat's one list" and "revoking text Chat access keeps voice rooms inside Chat"; `chat_navigation_test.dart` "the desktop side is the one list under its controls"; `mobile_drawer_structure_test.dart` |

### Finding

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 28 | Done | 55790–55802, 55967: found by name first, then by what was said or by whom, in one Results group shown whole | `ChatController.findConversations`: every word in the name, or every word in one message and its author. It replaces `sidebarConversations`, which matched words spread across a chat | `chat_inbox_test.dart` "chats are found by name first" |
| 29 | Done | 56449–56458, 56472: a found row shows the line that has the words, marked | `ChatInboxFoundLine`: the latest matching retained message or the directory excerpt, drawn with the shared `SearchText` | Same test; parity test and capture `page-found.png` |
| 30 | Done | 55789: rooms are found by name | `ChatInboxRooms.roomsFor` | Parity test; `chat_sidebar_search_test.dart` |
| 31 | Done | 56058–56069: "None of your chats match “words”" | `chatNoneMatch` | Parity test; sidebar search tests |
| 32 | Done | 56070–56078, 32895–32898: while finding, a Browse all channels row follows, carrying the words | The row opens the channel panel holding the words in its field | Parity test "chats are found by name first": the panel's field reads the words; `chat_channel_panel_test.dart` "the panel opens holding the words it was asked with" |

What is said is read from the messages this client retains, as before. A chat
whose matching message was never loaded is not found by it.

### Threads

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 33 | Done | 32744–32832: a thread's row laid out as a channel's | `ChatBrowseThreadRow` on `ChatInboxRowSurface`: the channel's mark, its name over the title, the last reply by its writer's face, the time at the bottom right | `chat_browse_parity_test.dart` threads alignment; `chat_my_threads_view_test.dart` |
| 34 | Done | 32697–32726: a thread with new replies boxed, reaching 12 past the others' edge, no rule between two boxed rows | The same surface with `ChatInboxRowFrame.plain`; a rule only between two read rows | Same tests |
| 35 | Done | 32630–32643: new replies first, then the most recent | The Threads page combines results from per-channel requests and orders the displayed rows together, unread first and newest activity first within each group. | `chat_my_threads_view_test.dart` "threads with new replies lead, newest first across channels" |
| 36 | Done | Diff 32938–33106, 60146: the posters' faces and the total reply count leave the row | The total reply count stays in the row's accessible label. The unread badge uses the server's unread-reply count, with a mention count when that is all the server reports. | `chat_navigation_test.dart`, `chat_browse_parity_test.dart`, `chat_my_threads_view_test.dart` |
| 37 | Done | 32629, 36017–36021: only threads in joined channels, and only those channels to pick from | The Threads page and its picker use the account’s joined channels with threading enabled, supplemented by paged channel discovery for memberships outside the sidebar list. Leaving a channel hides its threads and clears the filter if that channel was selected. Joining a channel makes it available without reopening the page. | `chat_browse_parity_test.dart` “Threads excludes unjoined channels and loads them after joining” and `chat_my_threads_view_test.dart` “the channel pill opens the panel to pick from” |
| 38 | Done | 32661–32690, 36040–36046: the channel pill opens the channel panel to pick from, and the one pressed is the choice | `ChatThreadChannelFilter` is the pill alone. It opens `showChatChannelPicker` and applies the answer unless the account changed while it was open. The searchable popover and its server search are removed | `chat_my_threads_view_test.dart` on iOS and macOS; captures `channel-panel-pick-phone.png`, `channel-panel-pick-desktop.png` |

### The channel panel

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 39 | Done | 3517 (diff: `chat-browse` leaves `PAGE_TABS`), 27597 (it leaves the phone's places), 33818 (its page leaves the pages), 25958–25962, 36014–36048: channels are browsed in a panel over wherever it was asked for | `chat_channel_panel.dart`. `showChatChannelBrowser` opens it from the list's rows and the joined channels list. The Browse channels page, its route content, its place in the phone's bar and its sidebar row are removed. `ChatShellService.openBrowseChannels` has no page to show a sheet over, so it opens the Chats page and leaves a request that `ChatChannelPanelRequests` takes once. A tab kept with the `chat-browse` id shows the Chats page with the panel over it, once | `chat_channel_panel_test.dart`; `chat_shell_integration_test.dart` "browses, finds and joins public channels in the panel", "a tab kept from when channels had a page", "the panel asked for from elsewhere"; `chat_shell_service_test.dart`; `mobile_shell_test.dart`; `chat_availability_navigation_test.dart` |
| 40 | Done | 56270–56353, 42976 (`channelMembers`), 15040 (`channelStatus`): each channel one row: its mark, its name and how many are in it on one line with the count giving way first, a Join or Leave chip, then what it is about in full | `_ChatChannelBrowseRow`: a menu-shaped `DItem`, the name and `memberships_count` in one line of text so the count is what is cut, the status after it unless open, `description` under it with no line limit. The chip is the sheet's own chip, a `DToggle` chosen while it offers Join. Real fields: `memberships_count`, `status`, `description`, `current_user_membership.following` and `meta.can_join_chat_channel` from `Chat::ChannelSerializer` | "channels are browsed in a panel that opens on Not joined and Open" on iOS and macOS; captures `channel-panel-browse-phone.png`, `channel-panel-browse-desktop.png` |
| 40a | Done | 36028–36029: the chip joins or leaves | `ChatController.updateChannelFollowing`. The chip waits while its write is unanswered, and the directory admits one follow write per channel, so a leave cannot be sent ahead of the join it would undo. A join the server refuses says why in a toast. A channel that is closed or cannot be joined has a disabled chip | "a channel is joined and left from its row", "a refused join says why"; `chat_channel_follow_ordering_test.dart` |
| 41 | Done | 36030–36034: pressing a channel opens it and puts the panel away | `_open`: the channel is resolved, the sheet closed, the channel opened. One that cannot be resolved says so and keeps the panel | "pressing a channel opens it and puts the panel away", "a channel that cannot be opened"; `mobile_chat_sheet_test.dart` "a channel opened from the channel panel" |
| 42 | Done | 56360–56380, 25963–25966: chips at the foot, All, Joined, Not joined, then Open, Closed, Archived, opening on Not joined and Open; pressing the status chosen lets every status back in | `_ChatChannelPanelChips`: two `DToggleGroup`s at the kit's chip preset in the `DSheetScrollBody` footer, which steps out of the way as the list is read. The strip fades at each edge with more chips beyond it. Membership narrows what is listed here; status is asked of the server. What they are set to is kept for the forum between openings, as the mockup keeps it while it runs | "the chips narrow by membership here and by status there", "what was chosen at the foot is kept for the next opening"; `chat_browse_session_test.dart` |
| 43 | Done | 56216–56223, 56355–56359: the field "Find a channel"; "No channels match “words”" | `SheetSearch`; the server finds by name as the words are typed. The panel always opens empty or on the words carried to it. With nothing typed and nothing listed it says "No channels match these filters." | "a channel is found by name along the field" |
| 44 | Done | 56236–56268: picking, All channels first, the name alone, a check on the one picked, its row in the active fill | `_picking`: `DItem`s with the strong neutral selection, the ink at 13% as `--state-active` is, and an 11 check in the accent. Found by name among what is listed | `chat_my_threads_view_test.dart` |
| 45 | Done | 56086–56096: a channel's mark in the panel is its `#` in its colour on nothing, in the 14 slot every menu row keeps | `ChatChannelMark`, in both modes | Same tests |
| 45a | Done | 9597–9645, 56216: on a phone a sheet that opens on its field with no title; on a desktop a 380 dialog titled Channels or Channel | `showShellSheet(search: true, dialogOnDesktop: true)` at 380. The desktop field takes the focus as it opens; a phone's keyboard stays down until the field is pressed, and a press in the panel leaves it up | First test on both platforms; "the keyboard goes from the field through each row and its chip"; "a phone keeps its keyboard up" |

What the page had that the panel does not: pull to refresh and a tab
refresher, a menu on each card, and the unread count of a joined channel.
The mockup's panel has none of them. The panel asks again each time it
opens, each time its words change and each time a status chip is pressed.

Two differences in how the panel renders:

- Sizes. `IN_SHEET` (56086) gives a page's sizes in a phone's sheet, which
  draws what it holds 17/13 larger. Taken literally it also shrinks the
  desktop dialog's names to 11. The comment says the size is "as a page's
  list has it", so the desktop draws 14.5, 12 and 12.5.
- A channel's emoji is not drawn in the panel. The mockup's mark is the `#`
  alone.

### The side

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 45b | Done | 43783–43857: chat's side has no rows over its list | The `chat-directories` section is removed. With it goes opening Chats or Threads in a tab of their own, which only its rows reached. The list's Threads row opens the Threads page in the current tab | `chat_sidebar_parity_test.dart` "the side is the one list"; `sidebar_panel_tabs_test.dart` "the Chats page keeps chat's side beside it" |
| 45c | Kept, for one case | The mockup draws no reader with rooms and no chat | Chat contributes no panel and no list to a reader without chat, so nothing would list their rooms. Voice's own section, with its denser row, remains for that case alone. `ChatInboxRooms.listedInSide` tells Voice whether chat's list stands | `sidebar_panel_tabs_test.dart` "Voice without Chat access" and "revoking text Chat access keeps voice rooms inside Chat" |

### Notifications

| # | State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- | --- |
| 46 | Done | 53312–53318: an unread notification's row stands in the unread fill | `DMenuFeedRow` uses the kit's unread Item | `d_item_unread_variant_test.dart` |
| 47 | Done | 52715–52765, 53080: no rule under a sheet's head line of chips; a dropdown keeps its rule (53066) | `DesktopHeaderMenu` draws its separator only outside a sheet | `test/desktop_header_menu_rule_test.dart`: the dropdown's rule stands between its chips and its first row; the sheet has none. Each case fails with the condition forced the other way |

## Captures

Rendered by `test/chat_list_mockup_parity_test.dart`,
`test/chat_channel_panel_test.dart` and `test/chat_my_threads_view_test.dart`
with `NATIVE_UI_EVIDENCE_DIR` set. The fixtures hold no account data.

| Capture | Shows |
| --- | --- |
| [Page, by type](chat-list-mockup-parity/page-by-type.png) | Groups, boxed unread rows, counts and times, faces, marks, the ways |
| [Page, one list](chat-list-mockup-parity/page-newest.png) | Starred leading each part, the Threads row among the unread |
| [Page, finding](chat-list-mockup-parity/page-found.png) | Results by name then by what was said, the way to every channel |
| [Side](chat-list-mockup-parity/side-by-type.png) | The same list at a sidebar's width |
| [Panel, browsing, phone](chat-list-mockup-parity/channel-panel-browse-phone.png) | The sheet opening on its field, a channel's row with what it is about in full, the chips at the foot |
| [Panel, browsing, desktop](chat-list-mockup-parity/channel-panel-browse-desktop.png) | The 380 dialog |
| [Panel, picking, phone](chat-list-mockup-parity/channel-panel-pick-phone.png) | All channels first and picked, with joined channels listed by name |
| [Panel, picking, desktop](chat-list-mockup-parity/channel-panel-pick-desktop.png) | The same over the Threads page |
