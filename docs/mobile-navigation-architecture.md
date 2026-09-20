# Shared features, separate desktop and mobile navigation

Status: implemented in the Flutter application. The HTML prototype remains in
[`mockups/mobile-navigation`](mockups/mobile-navigation/README.md).

## Ownership

The application shares its routes, accounts, API, caches, feature controllers,
permissions, drafts, live updates, and content widgets. The shell chooses the
navigation and presentation policy for the platform. iOS and Android use mobile
navigation, including at tablet widths; desktop keeps its workspace and tabs.
A narrow desktop window does not become a mobile session.

| Responsibility | Shared implementation | Mobile presentation |
| --- | --- | --- |
| Routes and feature operations | `ContentRoute`, `ShellController`, plugin capabilities | One content journey above the selected sidebar |
| Topics and posts | Existing `TopicListView` and `TopicView` | Same desktop topic cards; full-width list and reader |
| Chat | Existing channel controller, list rows, stream and actions | Channels / DMs sidebar; full-page conversations |
| Users and events | Existing directory and Events plugin | Full-page destinations; Upcoming events opens the calendar |
| Sidebar modes | `SidebarPanelContribution` and availability checks | Home first, available plugin modes, Settings action |
| Forum actions | `ForumIdentityHeader` | Same logo menu as desktop |
| Notifications and account | `UserMenuButton` | Bell and profile in the root header |
| Search | Existing controller, editor, result list and link dispatch | Icon opens a Native sheet |
| Forum appearance | Existing settings and preferences | Native bottom sheet |

Application controls come from `discourse_ui.dart`. The approved
`DTabListVariant.navigation` extends Native tabs with equally sized slots,
a rounded bar, and a short top selection marker. Settings remains an independent
button, so opening it does not change the selected mode. Existing tab variants
and keyboard behavior remain shared.

## Root and content composition

`DiscourseApp` sets the controller's navigation policy from the platform, and
`AdaptiveShell` selects `_MobileShell` from that policy. `MobileForumRoot`
owns the header, the sidebar container, and the bottom bar. Home includes the
instance rail and the default sidebar. The logo opens the desktop forum actions:
Open forum in browser, Settings, and Remove forum. Instance switching belongs
to the rail.

Opening a content destination removes the root from painting, hit testing,
focus and semantics. The page fills the safe area, with its own Back control;
there is no global header, rail, desktop tab strip, or bottom mode bar. The root
stays mounted offstage to preserve sidebar position and Chat's selected subtab
when returning. Settings and search are transient sheets outside visit history.

The plugin API has one optional presentation hook:
`SidebarPanelContribution.mobileBuilder`. Chat uses it for a Native Channels / DMs
tab strip above the shared channel list. Other plugins reuse their existing
sidebar sections. The host supplies the existing `PluginUiScope`, so plugin
services stay behind the same dependency boundary. Capability changes remove
unavailable modes and return a selected unavailable mode to Home.

Chat keeps its existing Browse, list options, and New message actions. When
the subtabs and actions cannot fit at the current text scale, actions move to
a second row. The shared Start chatting picker opens a conversation in the
mobile journey and Back restores the DMs subtab.

## Mobile history and the existing content renderer

`MobileNavigation` owns a bounded visit history with Home at index zero. Entries
contain `ForumTabLocation` route metadata, plus an aggregate destination marker;
they never own widgets or duplicate feature data. The selected root mode is
separate from the content history.

`ShellController` remains the navigation entry point for existing screens and
plugins. In a mobile session it records route transitions in `MobileNavigation`
and delegates Back and Forward to it. Only the selected location is projected
into the existing active workspace snapshot used by `MainContent`. Desktop
Back/Forward continues to use the existing per-tab history. Mobile disables
desktop plugin pane switching and tab creation.

This is a compatibility boundary, not a second retained screen stack. Existing
feature widgets still read some active route state from `ShellScope`; mounting
several retained copies would make hidden pages observe the current route and
could affect read tracking. The mobile shell therefore mounts only one shared
content renderer. Feature caches, drafts and reading anchors keep their existing
owners. A later move to retained Navigator pages should first make each feature
reader accept an explicit entry context; it does not require rewriting APIs,
controllers or plugins.

History rules:

- Back from the first page returns to the originating sidebar. Forward reopens
  it. A conversation → linked topic → Back returns to the conversation, then
  to the selected Channels / DMs sidebar.
- A new destination after Back discards the forward branch. Changing root modes
  starts a fresh journey; reopening the same root mode retains its history.
- List filters and explicit replacement commands replace the current visit.
  Hydrating a title updates metadata without creating an extra Back step.
- History is bounded to 50 content visits plus the root. Site/account changes
  discard the previous owner's history. Manual rail selection returns to Home.
- Ordinary mobile launch starts at Home. Existing URL parsing, authentication,
  and link-opening commands continue to resolve shared destinations.

`MobileHistoryGestures` adapts the visit identities and callbacks to the Native
`DHistoryTransition` component. Touch gestures from the first/last 24 logical
pixels move the page with the finger: right goes Back and left goes Forward in
LTR, mirrored in RTL. The adjacent page slides beneath/above it with parallax.
The page underneath has a 20% scrim that fades as Back reveals it; Forward
gradually dims the outgoing page instead. A soft shadow follows the front
page's leading edge, mirrored in RTL. These effects stay outside the snapshot
boundary, so captured pages retain their original colors.
Release past one quarter of the viewport, or flick inward, to finish; a short
drag or outward flick returns to the current page. History changes only after
the completion animation, so cancelled gestures never navigate or hydrate a
different destination. Reduced motion preserves gestures without page movement.

Previews are snapshots of previously painted pages, not retained feature widgets.
Opaque visit identities survive title hydration and Back/Forward; replacement
gets a fresh identity, and owner/sidebar-mode resets start a new history identity.
The component captures the outgoing page before its single live subtree rebuilds.
It retains at most eight images, each capped at one million pixels (about 32 MB
in total). Images never enter persistent storage or accessibility semantics.
History, theme, viewport and app lifecycle changes, plus memory pressure, clear
them. Missing/evicted previews use the themed background; embedded platform
views may not appear in snapshots. The destination becomes live on commit.

Horizontal gestures participate in Flutter's gesture arena; vertical scrolling
and body gestures remain with feature content. Multi-touch, pointer cancellation,
covered modal routes and concurrent navigation cancel the transition. Android
system Back closes a modal first, then traverses content history; at the root it
can leave the app. Buttons and system Back retain their existing behavior.

## Verification and local review fixture

`tool/mobile_navigation_review_main.dart` runs the production mobile shell with
in-memory sample forums, topics, messages and voice rooms. It overrides the
target platform to iOS for an isolated macOS review build and also builds for
the iOS simulator. It does not use the user's accounts or persist fixture data.

```sh
flutter run -d macos -t tool/mobile_navigation_review_main.dart
flutter build ios --simulator --debug --no-pub -t tool/mobile_navigation_review_main.dart
```

Focused verification covers:

- iOS and Android widget variants: Home, bell and logo actions, search sheet,
  topic cards, full-page Users, conversation / linked-topic Back, Channels / DMs
  restoration, tablet layout, edge gestures, system Back, list replacement,
  and 320-pixel layouts with 200% text and a visible keyboard.
- Pure mobile history: branching, ownership changes, bounded history,
  title hydration, replacement, and aggregate Back/Forward.
- Native tabs: keyboard navigation, semantics, independent settings action,
  equal slots, narrow RTL and large text, and the styleguide example.
- Affected desktop sidebar, topic list, Users, Chat rows, search, settings,
  plugin dependency boundaries, and component adoption checks.

The integration candidate starts at main `f26391674`, preserving sidebar link
reordering and the Native Start chatting picker. Formatting, locked dependency
resolution, root/Voice/full-profile analysis, and the production iOS simulator
build pass. The final overlap check passes 46 tests covering mobile journeys,
the picker, sidebar ordering, Chat rows, and channel-list preferences. A further
27 tests pass after adopting existing typography tokens in the picker, including
all 18 iOS/Android mobile cases and the typography adoption check.

The randomized full-suite run uses seed `2313302827` and completes with 12,143
passing tests, seven skipped, and 11 failures. One failure is fixed by the
typography token follow-up below; the remaining ten were independently
reproduced on pre-mobile base `b1321009f`:

- Five Chat composer cases: edit/draft restoration, GIF failure, reply action
  selection, uncertain network failure, and definitive send refusal.
- Two styleguide cases: Typography rich-action color and Kbd tooltip color.
- Two topic footer geometry cases in `topic_inbox_test.dart` and
  `topic_view_lifecycle_test.dart`.
- `shell_rebuild_isolation_test.dart` expects the sidebar theme wrapper to
  rebuild instead of its selector.

The full run also caught three font-size literals in main's Start chatting
picker; these now use the equivalent `DiscourseTypography.xs` token, and the
adoption check passes on the final source. The full suite is not recorded as
green; the ten independently reproduced failures remain outside this change.

Interactive native inspection could not run because the approved UI tool
reported the Mac was locked. The fixture is available for follow-up review;
widget platform variants and a successful simulator build do not constitute
an interactive simulator or physical-device pass.

### Interactive history transitions — 2026-09-20

The Native component is available in the styleguide under **History transition**
with Back/Forward and RTL examples. It adds no package dependency.

Verification: formatting and static analysis pass. The focused run passes all
45 tests in `d_history_transition_test.dart`, `mobile_navigation_test.dart`,
`mobile_shell_test.dart`, `control_style_adoption_test.dart`,
`d_button_adoption_test.dart` and `discourse_typography_adoption_test.dart`.
Gesture tests inspect intermediate positions before release as well as final
state, including cancellation, flick velocity, RTL, reduced motion, modals,
multi-touch, concurrent navigation, resizing, memory pressure and disposal.
The real mobile shell is exercised with both iOS and Android widget variants.

Rendered test frames were inspected for the production Users-to-Home swipe in
both directions at 390px, plus styleguide transitions in light, dark, forest
and plum palettes. The production mobile fixture builds for the iOS simulator.
Interactive simulator inspection was unavailable because the UI tool could not
open Simulator; no physical-device gesture check was performed.

The depth follow-up passes 33 component/mobile-shell tests and static analysis.
Light/dark and LTR/RTL frames at 20%, 60% and 90% Back progress, plus Forward,
were inspected with real shadow blurring enabled in the rendering fixture.
