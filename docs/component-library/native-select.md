# Native Select implementation and pending review

Frozen component: `native-select`, 2026-09-08. Public owner:
`lib/src/ui/components/d_native_select.dart`; export: `discourse_ui.dart`.
Status: in_progress; source/check/build preparation precedes awaiting_slot.

## Primary sources

- Frozen docs: https://ui.shadcn.com/docs/components/base/native-select.md
  SHA256 `46ba4666fa33e33a336645f213e74416eae3729c03e38ef64e687bffa54cd1a4`.
- Registry fetched 2026-09-09:
  https://ui.shadcn.com/r/styles/base-nova/native-select.json
  SHA256 `743d128b09f67c1921e3c302e778834639e5be92c454205cabfb61eed34b4ff1`.
  Exact bytes: `reference/native-select.json`.
- Linked reference examples:
  https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/native-select-example.tsx
  SHA256 `67366f6c3785982b683b2541bc68b7e7a4562a227850fdb798dc79ba147ea453`.
  Exact bytes: `reference/native-select-example.tsx`.
- API: https://ui.shadcn.com/docs/components/base/native-select#api-reference
  The select/option/optgroup contract uses HTML behavior, not Base UI Select.
- Flutter owner: https://api.flutter.dev/flutter/material/MenuAnchor-class.html
  and pinned Flutter 3.47.2 `packages/flutter/lib/src/material/menu_anchor.dart`.
- Radius factors: https://ui.shadcn.com/docs/theming (lg=1, md=.8).
  Existing shadcn MIT license is retained in `reference/LICENSE.shadcn.md`.

## CSS to Flutter mapping

Registry mapping verified against the rendered official page on 2026-09-09;
see `native-select-review.md` for measurements, fonts and evidence boundaries.
One CSS px maps to one Flutter logical px at 100% text scale.

| Registry | Flutter |
| --- | --- |
| h-8 / h-7 | 32 / 28 minimum visual height; grow for inherited large text |
| text-sm | unscaled DiscourseTypography.sm=14, 20px leading, weight 400, tracking 0; inherited host font |
| rounded-lg | 1× configured token radius |
| small rounded min(radius-md,10px) | min(.8× configured radius,10) |
| border-input | 1px colors.outlineVariant; distinct from tokens.border |
| bg-transparent, dark bg-input/30; dark hover /50 | transparent light; input alpha multiplied by .3/.5 in dark |
| pl-2.5 / pr-8 | text begins at 11px including border; trailing text allowance 33px = border+9px+16px artwork+7px gap |
| icon right-2.5, size-4 | 16×16 at trailing 10px, mirrored position in RTL |
| lucide ChevronDown | path (6,9)-(12,15)-(18,9) in 24px viewbox, scaled 2/3; 2px stroke scaled 2/3, round cap/join |
| focus-visible border-ring/ring-3 ring/50 | keyboard focus border and 3px exterior-only stroke ring (no tint inside a transparent field); pointer focus does not paint keyboard ring |
| aria-invalid destructive border/ring-3 | invalid semantics plus 3px destructive ring; .2 alpha light/.4 dark, .5 dark border |
| disabled opacity-50 | whole closed control at .5, callback disabled, forbidden pointer cursor |
| options bg Canvas/text CanvasText | Flutter popup surface/foreground from current host theme |
| transition-colors | immediate closed-control palette/focus changes; no decorative motion added |

The registry's `size` is the small/default styling enum, not HTML row count.
The frozen catalogue's incidental `variant: info` is the docs callout, not a
Native Select variant. This is a single-choice component, with typed text-only
options and one optgroup level. No rich menu, search, networking or app models.

## Native adaptation and lifecycle

`MenuAnchor` and `MenuItemButton` own the popup overlay, screen-edge positioning,
scroll view, keyboard traversal, activation, outside/Escape dismissal and focus
restoration. Per-row focus nodes are owned and disposed by the component; opening
focuses the current enabled choice. Disabled optgroups disable every option;
headings cannot select. The form owns selection rather than custom menu children.

This is an actual Flutter menu owner on all three supported targets. It is not
an AppKit NSPopUpButton, UIKit wheel/action sheet, browser HTML element, or the
separate custom Select implementation. The HTML reference leaves popup shape
and behavior to the user agent; here Flutter supplies native application menu
conventions. Popup rows wrap, use 44px minimum height with 12px horizontal/8px
vertical padding, scroll at 360px maximum height, and retain Flutter menu
positioning and navigation. Popup width matches the trigger when opened. No
OS-native picker or browser-popup pixel parity claim is made.

The closed control defaults to reference content width: the widest option or
placeholder, measured using the live font and text scaler, plus 44px border-box insets. Grouped options include one scaled em in intrinsic
width, matching the browser optgroup indentation allowance.
`isExpanded: true` fills a caller's bounded width; migrated app fields set this
explicitly to retain their layouts. Text ellipsizes in the closed control while the
full text remains available in popup and semantics. iOS/Android get an invisible
48px minimum activation region; large text expands visual bounds. Directional
padding mirrors artwork/text. Borrowed focus nodes survive disposal. Palette,
text scale and direction update an already open MenuAnchor without dismissing
it or losing selection. Menu transitions are disabled (animated: false default)
so inherited reduced-motion and local preview overrides introduce no animation.


## Character navigation

Printable character keys perform case-insensitive prefix navigation, independent
of accelerator labels. Closed controls accept a matching choice; open menus move
focus and Enter commits. Repeated letters cycle through matching enabled options;
headings and disabled options/groups are skipped. Prefixes expire after 700ms
using key-event timestamps, with no timer to leak; closing resets the buffer.
Focus-node ownership and disposal remain local. This is native-select choice
navigation, not a search/filter interface. Tests cover repeated b, disabled
Blackberry/Beet and the multi-character bl prefix selecting Blueberry.

## Form behavior

The public StatefulWidget holds a mount-time initial/default snapshot and a
single private Flutter FormField. Normal mode accepts edits itself. Controlled
mode displays only the parent's accepted value; proposals and reset requests
notify onChanged. Declines must leave FormFieldState.value, save and validation
at that accepted value even inside synchronous Form.onChanged/onChanged callbacks.
The field adapters protect validation from Flutter's private reset storage.
Reset clears Form errors/interaction state and requests the mount-time default;
controlled callers decide whether to accept it. Null is the placeholder; placeholderEnabled controls whether it can be selected.
`isRequired` supplies semantics; the caller's validator enforces domain rules.
Label owns visible text, focus association, and accessible naming; errors use a
live region. No pending Field/Input/Select dependency is imported.

## Adoption audit

28 plain selector owners migrated across core and bundled plugins:

| Owner | Choices and preserved domain behavior |
| --- | --- |
| UserStatusEditor | Clear after; busy guard and async custom-date acceptance/cancellation |
| PreferencesPage (6) | section navigation, likes, new topics, auto-track duration, reply level, bookmark auto-delete; capability gates, draft edits, server saves |
| Group management (3) | admission, visibility levels, interaction levels; controller permissions and change/save notifications |
| Bookmark editor (2) | auto-delete preference and relative time unit; busy guard, custom reminder calculation and save |
| InviteList | pending/expired/redeemed filter; capability-filtered options, counts, controller paging/search |
| Chat preferences | sidebar mode; can_chat/admin admission, editability, inherited site value and persisted wire value |
| Chat browse (2) | channel status and membership; existing server refresh and local filtering |
| Chat channel (2) | move destination and notification level; moderator selection, asynchronous notification write/busy guard |
| Assign (2) | configured/legacy status and group-topic order; preserving nullable Default order, async suggestions/save and topic query |
| Poll composer (2) | poll type and result visibility; published/ranked restrictions, staff visibility, unknown disabled values |
| Local Dates composer | relative-day mode; timezone/date formatting and async composer ownership untouched |
| Voice (3) | device choices (one owner mounts microphone/speaker/camera), room quality, member role; `_heldDevice` fallback, async device changes and membership writes |

All migrated selectors are controlled by their existing app state and retain
their initial value as the Form reset snapshot. Required
choices disable the placeholder with `placeholderEnabled: false`, preventing
new null choices from reaching existing non-null callbacks. Assign's real null
Default order remains a selectable placeholder. Voice role and Chat notification
fields keep bounded widths inside their existing horizontal rows. Surrounding
Input/Checkbox/Switch/Slider ownership is unchanged.

Retained after a fresh whole-tree audit:

- TopicMovePosts category dropdown carries CategoryIcon artwork, color and
  category hierarchy alongside text. It needs the separate rich Select owner;
  dropping that content would lose category information.
- Baseline DSelect/DSelectField source and barrel remain for the separately
  assigned custom Select component and its foundation/typography demonstrations,
  as requested by the coordinator. No remaining simple app caller uses them.
- Styleguide chrome selects theme/viewport configuration inside the documentation
  shell; those are not product form migrations and retain the shell's measured
  32px toolbar layout. Component examples use the actual new public widget.
- PopupMenuButton action menus (diagnostics, emoji, events, bookmarks, composer,
  Voice) execute actions rather than edit a plain selected value.
- Searchable timezone, assignee, user, category, hashtag and emoji pickers retain
  their search/async/rich-result owners. Multi-choice, date and calendar controls
  retain their distinct behavior; no other catalogue component is implemented.


## Verification boundary

Focused tests cover Form decline/deferred acceptance/reset, disabled options and
groups, keyboard selection/Escape/focus restoration, borrowed focus disposal,
32/28px geometry, narrow RTL large text, invisible iOS touch target, semantics,
and a popup remaining open and usable across theme/direction/text-scale updates. The popup regression inspects the rendered Material surface, not just the configured style. Styleguide examples are mounted under
light/dark, 240px, RTL and 200% text. These are widget tests, not device/VoiceOver
or pixel parity evidence. Existing PreferencesPage and UserStatusEditor suites
exercise the actual migrated production owners.

`tool/native_select_review.dart` is a reproducible local-data native entrypoint:
actual production Preferences, Group management, Bookmarks, Invites, Poll,
Local Dates, Event composer, Assignment editor/group topics, Chat browse/messages/
notifications/preferences, Voice and the full styleguide. The Voice subfixture
uses in-memory media/system-call/preferences adapters from established tests;
Join room and Media settings never acquire actual hardware.
Fake stores/API plus mocked in-memory SharedPreferences prevent account writes.
The status fixture uses a `.invalid` forum; any remote emoji cannot resolve and
may show its existing production fallback. Source and bundle evidence follows
in `native-select-build.md` after the isolated build completes.

Browser and font-loaded Flutter render comparison is recorded in
`native-select-review.md`. Native app/device/VoiceOver review remains pending.
No native CUA or app launch occurred. Do not mark review_ready or merge yet.
