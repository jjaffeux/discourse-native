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

`MobileHistoryGestures` observes touch gestures from the first/last 24 logical
pixels of the viewport: right goes Back and left goes Forward in LTR, mirrored
in RTL. It requires horizontal intent, ignores multi-touch and vertical drags,
and leaves body gestures to feature content. Modal routes block gestures behind
them. Android system Back closes a modal first, then traverses content history;
at the root it can leave the app. These are history gestures, without an
interactive iOS page-transition animation.

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

The final change record should distinguish widget/build verification from
interactive inspection on a physical mobile device. No physical-device pass is
implied by the platform variants or the simulator build.
