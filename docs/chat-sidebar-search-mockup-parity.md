# Chat sidebar search and directory pills

Design reference: `discourse-native-mockups` commit
`7f43e9ddf474dd58225b6e30921c798ac641f202`, Group 2. The exact commit diff and
surrounding source were inspected. Source line numbers below refer to that
commit, not a moving branch. Start/Dashboard and global folded filters belong
to the other groups.

The user approved a quiet variant of the existing `DInputGroup`, keeping the
recessed variant used by global search. They also approved moving implicit
`DSidebarContent` pinned-header padding to its callers, and the secondary-controls
slot in `DPageSurface.headed` for exact second-row spacing. Application controls
remain Native components imported through `discourse_ui.dart`.

## Itemized parity checklist

| State | Mockup evidence | Native implementation | Verification |
| --- | --- | --- | --- |
| Done | `App.tsx` 29474–29518: editable Search chat, no search-navigation callback | `ChatSearchEntry` uses `DInputGroupInput`; it updates only per-forum sidebar query state. No global search request, scope change or drawer dismissal. | Actual iOS/Android drawer tests at 320 and 390 logical pixels; desktop route identity check. |
| Done | 24818–24826 and 40216–40223: case-insensitive all-word matching across name, messages and authors | `ChatController.sidebarConversations` intersects the ordinary inbox projection with names, directory previews/authors and retained message raw/cooked text and author username/display name. Loaded thread replies and local sends participate. | Unit cases combine name, message and author across different messages, mixed case and repeated whitespace; DM/group and thread fixtures. |
| Done | 29462–29469: matching follows the existing list scope | Sidebar query is separate from `ChatInboxFilter`; scope/unread projection and ordinary ordering run first. Starred rows retain their own section; Newest uses All chats. The full Chats page does not inherit the sidebar query. | Scope and unread unit checks; desktop starred/channel/DM/group rows; clear retains DM scope and Newest sort; page inbox suite. |
| Done | 29463, 29504–29508: raw input remains editable, trimming determines activity | `ChatInboxFilters` keeps the raw string per forum; section behavior and no-match state use `trim()`. Clearing removes only the string. | Leading/trailing/internal whitespace and raw-value assertions; whitespace-only input shows clear without No chats match. |
| Done | 41668–41674: rooms, including newly created rooms, match by name | `ChatInboxRooms.sidebarRooms` uses the same all-word matcher after existing scope/unread rules. Voice consumes it and observes provider changes. No mock room corpus enters production. | Room-only multiword matching, 11 matches beyond the cap, dynamically supplied local room, and empty-result checks. |
| Done | 42230–42237, 42401–42411, 42426–42432 and 42511–42527: every match, no more/less links | Active filtering treats conversation and room slices as expanded and suppresses their more/less actions. Ordinary cap/expansion returns when cleared. | Scroll to the seventh matching channel and eleventh room; no ChatInboxMore during filtering. |
| Done | 42399–42402 and 42426: section collapse still applies during filtering | Conversation collapse state is controlled above the filtered sections, so removing and restoring a section does not reset it. Voice keeps its ordinary section-store collapse state. Room expansion is stored per forum so removing the section does not reset more/less state. | Collapse Channels, filter it away, clear and verify it remains collapsed. Expand rooms, filter all rooms away, clear and verify View less returns. Existing sidebar collapse/pinning checks. |
| Done | 42416–42418: No chats match only when query is active and both result sets are empty | Inbox layout considers filtered conversations and filtered rooms together. Matching rooms suppress the message. An empty raw/whitespace-only query retains the ordinary empty/error states. | Desktop no-match and room-only checks; six actual phone drawer variants. |
| Done | 29506 and 29508–29516: Escape and Clear search | Raw nonempty input shows the Native clear action, including whitespace. Both clear paths restore editor focus and preserve current route, filter/sort choices and ordinary disclosure state. | Desktop clear/Escape; iOS/Android clear/Escape with open drawer and focus assertions. |
| Done | 29484–29497: field widths, margins, text and icon geometry | Caller padding is desktop `4,4,4,6`, phone `10,10,10,0`. Quiet group artwork is 30 desktop/36 phone, text 12.5/16, magnifier 12/14, 8px addon gap. Text scaling grows the artwork; placeholder is muted and entered text strong. | Production sidebar width assertions; phone widths and scaled heights; kit geometry tests on macOS/iOS/Android; rendered captures. |
| Done | `app.css` 5528–5568: clear 22px circle, 11px cross, trailing -4px; empty message 12px by 10px, 13/15px text | Quiet input-group button uses its existing search-clear density with 22px extent and 11px icon, pill radius and a 7px trailing inset relative to the normal 11px inset. Empty-state margin accounts for the desktop sidebar's existing 8px body inset. Native owns hover, focus and touch behavior. | Kit asserts 22×22 and 7px trailing inset on three platforms; desktop empty text starts 10px from sidebar edge; phone/desktop captures. |
| Done | Global search is not part of this sidebar interaction | Existing recessed `DInputGroupVariant.search` remains used by `ForumSearch`; explicit contextual global-search tests now invoke its actual global-search action. | Input/input-group suites; existing contextual search tests retained. Their pre-existing geometry failures are recorded below. |
| Done | 31757–31762: ordinary page/list pills and wrap gap 8 | Browse channels and Threads use `DButtonVariant.quiet`, `DControlSize.filter` and `Wrap(spacing: 8, runSpacing: 8)`. Native phone/list sizing and text scaling remain kit-owned. | Desktop 30px/12.5px and phone 44px/16px, including combined app/system scaling; 16px page inset assertions. |
| Done | 31762–31766: 8px below switches, navigation padding top 0/bottom 2 | The approved `DPageSurface.headed.secondaryControls` slot supplies the 8px gap, 16px side inset and 2px bottom inset; Chat migrates its navigation row to that slot. No negative-margin or application control geometry is needed. Both rows use Native persistent-control behavior. | Page-surface tests assert 8px/16px/2px on macOS, iOS and Android; production Chat layout checks and readable phone/desktop captures. |

## Verification and evidence

Focused runs cover the added matching and sidebar tests, the actual phone
drawer, ordinary chat inbox/phone pages, sidebar pinned controls/collapse,
Native Input/Input Group/borderless behavior, and the runnable Input Group
styleguide. No full Flutter test suite was run.

Readable captures use bundled fonts and the existing Native evidence helper's
system-font loading. The fixtures contain no real account data and are confined
to tests. The captured layouts are rendered widget evidence, not live-server or
physical-device validation.

Executed focused checks:

- `flutter test --no-pub test/chat_sidebar_search_test.dart test/chat_inbox_navigation_scale_test.dart test/d_sidebar_pinned_controls_test.dart test/d_sidebar_cards_test.dart test/d_input_group_test.dart test/d_input_group_borderless_test.dart test/d_input_test.dart test/styleguide/input_group_examples_test.dart test/chat_mobile_sidebar_test.dart test/chat_sidebar_parity_test.dart test/chat_inbox_test.dart`: **92 passed**.
- `flutter test --no-pub test/chat_search_entry_test.dart --plain-name 'phone drawer filters in place'`: **6 passed**, also rerun with readable-font captures.
- After the approved heading extension: `flutter test --no-pub test/d_page_surface_test.dart test/chat_inbox_navigation_scale_test.dart test/chat_mobile_sidebar_test.dart`: **33 passed**. This includes the new slot, its styleguide examples, production Chat spacing and narrow/keyboard layouts. The earlier tests were not blindly repeated.
- Targeted `dart analyze` on all changed source and test files: **no issues**.
- `git diff --check`: **passed**.

The first renders used Flutter's placeholder font. Those were replaced with
readable captures using the bundled and system-font helpers before visual
inspection. The final examples below were inspected after the heading change.

| Capture | Evidence |
| --- | --- |
| [Desktop matching rows](chat-sidebar-search-mockup-parity/desktop-matches.png) | Quiet editable pill, ordinary sections, matching rows past their cap. |
| [Desktop no matches](chat-sidebar-search-mockup-parity/desktop-empty.png) | Strong raw input, compact clear button, 10px empty-message inset. |
| [Phone search](chat-sidebar-search-mockup-parity/phone-search.png) | 390px iOS drawer with 10px field margins and a retained drawer. |
| [Narrow phone, 200% text](chat-sidebar-search-mockup-parity/phone-search-2x.png) | 320px Android editor, scaled controls and readable wrapped no-match message. |
| [Desktop navigation](chat-sidebar-search-mockup-parity/desktop-navigation.png) | Ordinary page pills, 8px second-row gap, final 2px bottom spacing. |
| [Phone navigation](chat-sidebar-search-mockup-parity/phone-navigation.png) | The same second-row geometry with Native phone pill sizing. |

## Independently reproduced baseline failures

The unchanged `ffb4cc4c9` checkout reproduced **14** failures in
`test/chat_search_entry_test.dart` and `test/mobile_drawer_structure_test.dart`:
12 contextual global-search cases expect an 8px inset while the current
recessed field starts at 12px; the 320px/200% global-search case additionally
has existing overflow/zero-width behavior; one separate narrow global-search
case fails similarly; and the scrolled drawer fixture cannot hit its fourth
channel before scrolling. These are outside the new local sidebar interaction.

The exact test names and baseline revision are in
[baseline-failures.tsv](chat-sidebar-search-mockup-parity/baseline-failures.tsv).
The tests remain present. The new drawer interaction assertions pass.

## Limits

The mockup can search its complete in-memory fixture corpus. The Native app
filters the conversations/rooms already available to the account and the
messages retained by this client, including directory previews, loaded thread
replies and local sends. It does not fetch every channel's history or call the
server's global chat-search endpoint. Unloaded/evicted history cannot produce
a match. The sidebar field works independently of the server's global-search
capability; server permissions and existing directory availability still apply.

Real backend room creation, a live server's complete history, physical keyboards
and software keyboards on devices were not exercised. Phone keyboard/layout
coverage uses the production shell in widget tests, including existing inset
and large-text tests. The Native UI kit continues to own page-control sizes,
phone touch targets and field sizing.
