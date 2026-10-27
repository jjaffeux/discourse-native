> Historical design and capture notes. The app now uses the [solid appearance](material-mockup-parity.md), with [depth from the current mockup](surface-depth-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

# Sidebar mode switch parity

Reference: `discourse-native-mockups` snapshot `7c86328`, `App.tsx` SideNav
and `app.css` `.side-switch`, `.side-switch__name`, `.glass-well`.
Scope: the sidebar Forum / plugin panels (including Chat) / Shortcuts switch.

The existing `DTabList.expandSelected` mode now owns the reference's capsule
track, 3px inset and gaps, 38px minimum inactive width, 12.5px glyphs and labels,
5px vertical label padding, selected semibold text and muted inactive glyphs.
Actual label and badge widths determine each choice's base width. Spare width
is distributed by animated flex weight, rather than reserving a fixed allowance
for every badge. A narrow strip scrolls when its content cannot fit.

Selection expands its label and flex weight over 300ms with CSS ease
(`cubic-bezier(.25,.1,.25,1)`). Label opacity, foreground and fill change over
200ms. Mouse hover paints the bare control; press scales selected controls to
95% and inactive controls to 92% over 80ms, then returns with the reference's
400ms spring curve. Hit testing follows the transformed artwork. Reduced
motion applies these changes immediately.

The existing Native material renderer paints the recessed track and raised
selection for Standard and Liquid glass, including light and dark themes.
The track uses the reference's inner shadow and bottom rim. Liquid glass uses
the raised palette tint at 42% in dark mode and 50% in light mode, with 5px
backdrop blur, 185% saturation, an elliptical upper sheen and inset white rim.
Inactive hover uses a 28% tint, its own centered sheen and upper edge catch,
without a backdrop filter or outer shadow. Selected hover brightens the sheen.
Idle inactive controls remain transparent. Tint changes retain the 200ms fade;
high contrast and Reduce Transparency keep the opaque Standard treatment.
Desktop Chat urgent counts are plain green, bold, 12px tabular text with their
existing accessible description; ordinary unread activity keeps its dot.
Routing, plugin visibility, manual keyboard activation, RTL, tooltips and
independent badge updates retain their existing contracts.

`Sidebar modes` in the Tabs styleguide demonstrates the production composition.
`lib/sidebar_switch_review_main.dart` is an account-free native capture fixture:

```sh
flutter run -d macos -t lib/sidebar_switch_review_main.dart \
  --dart-define=SIDEBAR_REVIEW_CAPTURE=true
```

It logs the platform temporary paths for Forum, Chat, Shortcuts and a transition
frame. Each image covers light/dark, Standard/Liquid glass, counts/dots and 200%
text. These are macOS rendered captures; no physical mobile device was checked.
It also captures inactive Chat hover and a Dracula palette over a purple ground,
matching the supplied reference's material, with separate reference images.
The shared material renderer supplies platform-specific glass rendering.

Focused checks: `d_expanding_tabs_test.dart` (geometry, measured badges, transition
width, gaps, reduced motion, RTL keyboard, scrolling, hover and press),
`sidebar_panel_tabs_test.dart` (production panels/badges/routing), and
`styleguide/tabs_examples_test.dart` (narrow 200% RTL and interactions).
`d_tabs_test.dart` also ran: its two existing failures (38px versus an old 44px
navigation target assertion; initial automatic selection included in callbacks)
reproduced on unchanged main before this change.

The material correction is additionally covered by `d_sidebar_tab_material_test.dart`
(rendered tint against two backdrops, bare hover, pointer exit and high contrast)
and `d_document_tab_material_test.dart` (the shared glass painter's document tabs).

## Mobile navigation

The phone navigation page now uses the same mode switch as desktop, including
Chat's plugin visibility, glyphs, badges and selected-label animation. Choosing
a mode changes the sidebar without navigating the retained page. Dock-owned
mobile panel roots continue to use their own mobile builder.

The phone reference in `App.tsx` uses a 53px rail and a sidebar inset of 6px on
all four sides, with the device bottom safe area added to the panel's bottom
margin. The rail consumes its own safe area independently. When the keyboard
replaces that inset, the panel retains its 6px margin. Its switch has 10px top,
12px horizontal and 8px bottom spacing.
The production mobile composition now uses those dimensions. The hamburger's
layout column shares the rail's width so the menu glyph and
forum icons have the same horizontal center. The button retains its Native
visible hit bounds. Voice rooms and Chat's compact inbox/filter controls belong
to the Chat sidebar mode. Mobile
omits the desktop directory rows above the filters, matching `showTopItems` in
the reference. Forum contains its categories/tags and Shortcuts its custom links.

`test/support/mobile_sidebar_review_main.dart` runs the production app shell
with in-memory forum, Chat and Voice fixtures and saves six native captures:

```sh
flutter run -d <simulator-id> -t test/support/mobile_sidebar_review_main.dart
```

The October 14 verification includes light/dark Forum, Chat and Shortcuts on
the iPhone 18 Pro simulator with Impeller. This is simulator evidence, not a
physical-device capture. Widget checks cover iOS/Android, both material settings
(Apple platforms resolve to Liquid glass), switch geometry, unchanged page
routing, Chat capability visibility, conversation opening, Voice revocation,
320/430/600px widths with 200% text and rail bounds throughout swipe gestures.
The owning desktop panel/badge checks also remain covered by
`sidebar_panel_tabs_test.dart`.

The two existing `mobile_shell_test.dart` minimized-composer checks still fail
on unchanged main: they attempt to tap the retired `Minimize` text. They are
outside the sidebar change.
