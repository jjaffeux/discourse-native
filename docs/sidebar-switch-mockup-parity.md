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
The shared material renderer supplies platform-specific glass rendering.

Focused checks: `d_expanding_tabs_test.dart` (geometry, measured badges, transition
width, gaps, reduced motion, RTL keyboard, scrolling, hover and press),
`sidebar_panel_tabs_test.dart` (production panels/badges/routing), and
`styleguide/tabs_examples_test.dart` (narrow 200% RTL and interactions).
`d_tabs_test.dart` also ran: its two existing failures (38px versus an old 44px
navigation target assertion; initial automatic selection included in callbacks)
reproduced on unchanged main before this change.
