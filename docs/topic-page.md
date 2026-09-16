# Desktop topic workspace

The topic header's **Topic view** popover offers **Sheet** and **Dock right**.
The last explicit choice is stored locally in
`discourse_native.topic_presentation`, shared across forums and tabs, and
restored on restart. Docking is the initial default. Mobile retains its inline
reader and does not show the chooser.

## Presentation and available space

Docking keeps a reduced, resizable source list beside the reader. The list uses
its current width between 304 and 480 logical pixels, shrinking as needed to
preserve an 825-pixel reader. Below 1129 pixels of available reader workspace,
a docked topic temporarily opens as a sheet. Available space is calculated after
navigation and the preferred composer placement; opening a sheet does not feed
its larger background viewport back into that calculation. Widening restores
docking without overwriting the saved choice.

A sheet is centered above the browsing workspace, with an inset supplied by the
Native Sheet component. Its width follows the existing reading lane and expands
to include a side composer when there is room. Narrow windows use nearly the
full workspace width. Forum tabs, the community rail and navigation remain
outside the sheet. The source list remains mounted beneath it.

## Navigation and retained state

- Switching presentation retains the reader, current post, scroll position,
  editor, text selection and draft. The list keeps its filters and position.
- The header collapse control returns to the source. Sheets also support
  Escape and backdrop dismissal. A direct topic with no source returns to
  Topics when its sheet closes.
- Previous/next buttons remain in the visible list footer. Keyboard sequences
  navigate the same source list in either presentation; **U** returns to it.
  Nested menus and dialogs keep their own keyboard handling.
- Navigating while writing preserves the draft and its original destination.
  Closing a sheet moves the composer back to the browsing workspace. Its
  return-to-topic action remains available when reading another destination.

## Composer and navigation

The composer docks inside the active presentation. Side docking requires a
480-pixel reader plus a 360-pixel editor and divider. When these cannot fit,
the editor moves below the reader, restoring its preferred side when space
returns. The draft, editor selection and reader survive these transitions.

The rail remains visible. Below 1100 logical pixels, the sidebar is accessible
through a **Navigation** popover beside the rail. It closes after navigation
and when the permanent sidebar returns. Touch layouts retain their existing
split-view and bottom-composer behavior.

## Implementation

`TopicPresentationController` separates the saved preference from the effective
presentation. `TopicWorkspace` supplies a local Navigator below the forum tabs.
`TopicReaderPresentation` retains the reader until its sheet outlet is mounted,
then moves the same keyed subtree between that outlet and the inline workspace.
A new sheet waits for a closing outlet to finish dismissing if the window
crosses the split threshold again during the transition.
The existing composer host retains the editor through the corresponding dock
handoff. Explicit reading-route settings allow navigation shortcuts inside the
workspace and sheet while other popup routes continue to block them.

Application UI uses `DPopover`, `DToggleGroup`, `DButton` and centered `DSheet`
through `package:discourse_native/discourse_ui.dart`. No generic UI-kit component
was added or extended.

## Verification

The final focused run passed 89 desktop, preference, composer and keyboard
tests. Coverage includes repeated view switching, reader and
editor identity, selection and scroll retention, restart preferences, stale
preference loads, responsive fallback and interrupted transitions, direct links, Escape and nested-dialog
behavior, source navigation, tabs, composer docking, RTL and mobile behavior.

The broader composer, keyboard, navigation, topic-inbox, plugin-chrome and
shell-panel run passed 229 tests. Its 27 forum-tab integration failures were
reproduced with identical test names and missing-sidebar assertions on unchanged
`71246b96`: that older fixture requires the permanent sidebar at narrow widths.
The new desktop tests cover tab access and retained drafts through sheets.

Root and full-profile static analysis passed. The macOS review-fixture build
passed. Native inspection of `tool/topic_page_review_main.dart` used an isolated,
ad-hoc-signed copy with local fake data and separate preferences. It verified
centered sheet and docked views, the two-option chooser, switching with a typed
draft, light/dark themes, narrow bottom docking, and closing the sheet while
keeping the draft. The review app was quit afterward. The subsequent direct-link
close fallback and interrupted-dismissal guard have widget coverage; the inspected source-list close behavior is
unchanged. No live forum data was modified. Mobile behavior has widget coverage
only; Linux and Windows were not inspected on devices.
