# Topic header motion studies

Open `index.html` directly, or serve this directory with a local HTTP server.
There are no build steps, network requests, packages or account dependencies.

## Adopted Flutter implementation

Direction 02 is implemented in `lib/src/shell/topic_inbox_header.dart` and
`lib/src/shell/topic_view.dart`. Following the 2026-09-13 review, a single 18px
topic title stays in the toolbar from the top, replacing the category breadcrumb
and duplicate opening title. Long titles wrap to at most three lines without
changing size on scroll. The original category/tag controls pin beneath it.
Assignment and topic
actions remain available throughout. The post viewport does not resize on
scroll or reopen after a small upward gesture.

The title editor composes Native `DTextarea` and `DButton` controls. Clicking
the compact title returns to the opening editor. Save and Cancel are explicit;
there is no keyboard-hint text. Enter and Escape remain supported, and failed
saves retain the draft. No Native component API was added or changed.

The post stream retains its virtualized list controller, measured heights and
post identities. Pinned controls are accounted for in reading progress,
indexed jumps and floating dates. The offline native fixture is
`tool/topic_header_handoff_review_main.dart`.

Validation on 2026-09-12: clean `dart analyze`, successful debug macOS build,
and 165 passing focused header, title, viewport, lifecycle, date and
control-adoption tests. The existing macOS test `footer actions stay joined at wide and compact
widths and remain usable` fails with an unrelated 8px spacing difference; the
same failure was reproduced with the unchanged source from `c84a7d1a`.

The native fixture was reviewed in dark and light palettes, at desktop and
390px pane widths, with 200% text and reduced motion. Scrolling, a small reverse
gesture, title Save/Cancel, and the tag overflow were exercised in the real
macOS window.

The 2026-09-13 single-title follow-up passed the same 165 focused tests, static
analysis and debug macOS build. Native review covered scrolling, opening and
cancelling the editor, desktop and 390px widths, both palettes and 200% text.
The updated browser mockup retained an 80px wrapped toolbar at both 0px and
560px scroll, restored title focus after Cancel, and fit the 390px preset.

## Direction 02: full-content follow-up

Open `natural-handoff.html` for the focused continuation requested by the user.
It includes the current header's editable title; category and subcategory
controls with their separate browse actions and category privacy icon; tag
links, overflow and editor; participant avatars, reply count and last activity;
assignment; Collapse topic; and the actual wrench/share actions. Notifications
and profile are in the macOS window bar, with an optional non-macOS placement
in the topic toolbar. The state selector demonstrates closed, assigned, event,
many-tag and private-message variants.

One toolbar stays fixed and shows the 18px topic title at every scroll position.
Its height accommodates the wrapped title and remains constant while scrolling.
The original 46px category/tag row pins beneath the toolbar using
CSS sticky positioning. Assignment is deliberately anchored in the toolbar
throughout. The activity summary scrolls with the opening, as it is omitted
from the current app's compact layout too. Header transitions never resize the
scroll viewport or recreate the taxonomy controls.

The title was reduced from 24px to 18px after the user's review. A subsequent
review moved it into the top bar at all scroll positions. Clicking the title
opens the full-width editor below the toolbar, with Save and Cancel.

The values are illustrative; the inventory comes from
`topic_inbox_header.dart`, `topic_header_tags.dart`, `topic_actions.dart`,
`user_menu_button.dart`, `title_bar.dart`, `assign_plugin.dart` and
`discourse_events_plugin.dart`. This is a local HTML/CSS mockup, not a live
account connection. Its pickers and editor change only its sample state.

The original full-content follow-up was checked in the browser in both palettes, in a
390px pane and a 390px browser viewport. Verified title saving, category changes
and browsing, tag edits and overflow, assignment, closed-state changes, event
and share content, focus restoration, reduced motion and the alternate account
control placement. At 168px scroll the toolbar remains 52px, the taxonomy row
pins at 52px, and the 536px desktop scroll viewport does not resize. At the
390px browser size, the account actions stay within the pane and do not overlap
the compact title. The tag picker uses one scrolling list and fits above the
topic footer. JavaScript syntax and whitespace checks passed.

Four HTML/CSS proposals explore the header in `lib/src/shell/topic_inbox_header.dart`:

| Direction | Scroll behavior | Main trade-off |
| --- | --- | --- |
| 01 Pinned title | Fixed 52px title/actions; 98px of details scroll in the document | Smaller opening title; details leave view |
| 02 Natural handoff | Large wrapping title scrolls out; a staged 28px handoff reveals the fixed toolbar title | One change of title location |
| 03 Continuous collapse | Header retracts 166→52px over the first 114px of scroll; one title transforms | Long titles stay on one line and truncate |
| 04 Always compact | Fixed 88px title and taxonomy rows | More permanent chrome; activity opens in details |

Explore each at the same scroll position, or use **Compare all** for linked
scrolling. **Play scroll** includes a small reverse gesture while reading,
followed by a return to the top. Manual scrolling interrupts playback. Also try
390px width, long titles, dark/light appearance, keyboard scrolling and reduced
motion. The reduced-motion mode replaces direction 03's scale with a fixed
toolbar and replaces playback with explicit state jumps.

Topic details, bookmark toggles, sample assignment cycling and jumps to the
first/latest post work locally. The rest of the application shell provides
static context. The popover exposes the full title and all tags at every width.
Select a direction to get a shareable local `?design=a`, `b`, `c` or `d` URL.

## Relationship to the Native kit

The HTML/CSS studies are design references for the Flutter implementation
described above. The product colors follow the local
`ShellColors` palettes. Control sizes, radius, badge and avatar treatments are
approximations informed by the component conventions, catalogue and styleguide.

| Mockup surface | Existing Native component |
| --- | --- |
| Header buttons | `DButton`, ghost/outline, small/extraSmall |
| Category and tags | Existing category adapters and `DBadge` |
| Participant stack | `DAvatar` compositions |
| Topic details | `DPopover` |
| Sidebar | `DSidebar` compositions |
| Scroll area | Existing topic viewport / `DScrollArea` |

The previous app implementation used a boolean compact state, `AnimatedSize` and
`AnimatedSwitcher` with 380ms transitions. Any upward scroll cleared compact
mode. Direction 03 uses a direct position-based transform instead; A, B and D
keep the toolbar's geometry fixed. None of the studies resizes the scrolling
viewport while the header changes.

The HTML studies demonstrate design behavior. Native implementation and
verification are recorded above.

## Verification · 2026-09-12

Reviewed in the Codex browser at desktop and 390px browser widths, plus the
390px pane preset, in light and dark themes. Checked regular/long titles,
linked scroll offsets, a partial collapse at 52px, a one-pixel reverse gesture
at 156px, keyboard Page Down, complete demo playback, reduced motion, bookmark
state, latest-post navigation, and popover visibility/focus restoration.
The narrow comparison popover scrolls to keep all details reachable.

At scroll offsets 156px and 155px, header heights remain 52/52/52/88px for
A/B/C/D; each comparison scroll viewport stays 314px high. At 52px, C is 114px
high. Browser diagnostics reported no warnings/errors and the document has no
duplicate IDs. `node --check mockups.js` and `git diff --check` passed.
