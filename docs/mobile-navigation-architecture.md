# Shared features, separate desktop and mobile navigation

Updated September 23, 2026. iOS and Android use the mobile shell at phone and
tablet widths. Desktop retains its workspace, tabs and sidebar behavior.

## Persistent mobile shell

`MobileForumRoot` owns the header, content card and transparent footer. The
header contains the hamburger, forum identity/menu, search, notifications and
profile. These controls and the footer remain outside the content transition.
The hamburger opens a full-width navigation page with the instance rail and
sidebar. It uses the existing Native `DHistoryTransition` to enter from the
leading edge and push the content aside, mirrored in RTL. The header stays
visible and the bottom tab bar collapses while navigation is open:

- **Forum** contains categories and tags.
- **Shortcuts** contains custom sidebar sections and configured custom More links.

Selecting a navigation destination closes the page. The hamburger, Escape and system
Back also close it, preserving the current content visit. The existing content
remains mounted offstage with focus and ticking disabled. Changing site or
account closes navigation and discards the previous owner's history without
animating that owner's content.

The footer uses independent Native buttons in this order: Topics, Chat,
Messages, Users, Events, More. Chat and Events use the plugin registry's existing
availability and permission checks. Messages and Users use the site's core
sidebar destinations. More offers Groups, Badges and connected-user Bookmarks.
Bookmark rows reuse the shared bookmark renderer and controller.

New topic and New message appear only in their relevant list contexts and when
the account can create them. They sit at the right of the same footer row. The
label collapses to an accessible plus button when the available width or text
scale requires it. On very narrow displays, the navigation buttons scroll
horizontally while the creation action stays visible. Native controls continue
to own their touch targets and text scaling. Category notification and dismiss
controls remain available in the footer when relevant.

The circular navigation buttons and pill creation actions are explicit design
exceptions using Native's existing `DButtonShape` API. Tab buttons use
`DButtonDensity.mobileNavigation`: 44px surfaces, full 18px glyphs and 48px
touch targets. The preset also applies to More and desktop mobile previews;
ordinary controls keep their shared size presets. Menus, sheets, tabs,
buttons and the message-recipient dialog use `discourse_ui.dart`.

## Shared content and mobile history

`ShellController` remains the navigation entry point for shared screens and
plugins. `MobileNavigation` stores bounded route metadata and opaque visit
identities, never widgets or duplicate feature state. Only the selected visit
is projected into the existing workspace snapshot read by `MainContent`.

Topics and other content tabs start at their destination without a synthetic
sidebar Back step. Opening a topic or another nested destination creates a
visit. Back/Forward traverse that journey. Filters replace the current visit;
title hydration updates its metadata without changing its identity. Selecting
a different tab starts a fresh journey, and site/account changes reset it.

Chat starts at its Channels / DMs sidebar. That sidebar remains mounted offstage
with focus, painting and ticking disabled while a conversation is open. Back
returns to the selected subtab. Only one shared content renderer is live, so
hidden content pages cannot bind themselves to another route or mark it read.
Feature caches, drafts, permission checks and reading anchors retain their
existing owners. Search and settings remain transient Native sheets.

## Native transitions

`MobileHistoryGestures` adapts history identities and callbacks to
`DHistoryTransition`. Its optional `tabIndex` and `tabOwner` provide the ordered
tab push transition: a lower index enters from the left and pushes the old page
right; a higher index enters from the right and pushes it left. RTL mirrors the
movement. Header and footer stay stationary. Reduced motion skips the slide.

The destination is the only live page; the outgoing page is a bounded image.
Rapid switches cancel the previous animation safely. Owner changes never
animate the previous account's content. Theme, width, lifecycle and memory
changes clear snapshots. The styleguide includes ordered-tab and RTL examples.

Existing edge Back/Forward gestures retain their parallax, scrim and shadow.
They participate in Flutter's gesture arena, leaving vertical scrolling and
body gestures with feature content. Cancellation never changes history.
Snapshots remain in memory, capped at eight images of at most one million
pixels each. Missing previews use the themed background. Android system Back
closes modals first, traverses content history, then may exit at a tab root.

## Verification and local review

`tool/mobile_navigation_review_main.dart` runs the production shell with local
sample forums and enabled Chat/Events capabilities, without user credentials.

```sh
flutter run -d macos -t tool/mobile_navigation_review_main.dart
flutter build ios --simulator --debug --no-pub -t tool/mobile_navigation_review_main.dart
flutter test --no-pub tool/render_mobile_navigation_test.dart
```

The rendering fixture uses local macOS fonts and writes light/Dracula frames to
`/tmp/mobile-navigation-review`, including navigation tabs, destinations,
intermediate sidebar/tab push frames and a narrow layout at 200% text. These
are offscreen Flutter renders, not interactive device screenshots.

Focused tests cover iOS/Android navigation, ordered transitions in LTR/RTL,
rapid switching, reduced motion, site/account isolation, optional plugin
availability, navigation page contents, composers, Chat subtab restoration,
history gestures, 320px/390px/600px footer layout, large text, tablet behavior and
affected desktop navigation. Component adoption checks guard Native usage.
Interactive simulator inspection was unavailable because the desktop UI tool
could not open Simulator; build and widget checks do not claim a physical-device
interaction pass.

The September 23 sidebar-page checks cover push direction in both opening and
closing transitions, hidden bottom tabs, unchanged header geometry, retained
content elements and history, system Back precedence, navigation selection,
forum changes, and full-width 320px/600px pages at 200% text. Light and Dracula
navigation pages were inspected using the offscreen rendering fixture.


Verification: the 66 mobile shell/history tests and root static analysis pass.
The additional transition, sidebar, adoption and shell regression run passed
135 tests, with five unrelated failures reproduced on baseline `59a0b43d3`:
the composer button styling inventory, macOS title-strip method calls, desktop
custom-sidebar row height, community section height, and rail-tooltip leading.

Interactive macOS review used the production mobile fixture with an iOS target
platform override, in a narrow window and at its initial desktop width. It
verified the full-page rail/sidebar, hidden tab bar, Forum/Shortcuts selection,
opening a topic from a shortcut, and Escape returning to content. This was a
local fixture with sample forums, not an iOS simulator or physical-device run.
The final Escape change also passed all 58 mobile shell tests and root analysis.
