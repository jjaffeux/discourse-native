# Mobile notification menu

Reference: `NotificationsMenu` in
`/Users/joffreyjaffeux/Code/discourse-native-mockups/src/App.tsx`, inspected
September 23, 2026, and the user's accompanying mobile screenshot.

The bell opens the Native Popover directly on touch platforms. Below a 600px
window width it requests a 320px panel, clamped to the safe viewport by Popover.
Panels narrower than 440px put navigation above the independently scrolling
feed. Wider panels retain the vertical category rail. Category selection is
preserved when the panel changes layout.

The user explicitly approved `DTabListVariant.outlinePill` for this design.
It uses the shared button palette, capsule outlines, an accent-filled selected
tab and 6px gaps. Small controls keep the shared typography and mobile control
height, with at least 48px touch targets. Tabs owns horizontal scrolling,
keyboard reveal, RTL navigation and selection semantics. The compact strip
shows labels; accessible labels include unread counts. The Tabs styleguide
contains an interactive **Outlined pills** example.

The menu follows the selected account, as the desktop popover does. Switching
accounts refreshes the selected feed and its actions. Messages opens the
existing inbox; plugin tabs preserve their active-link behavior.

## Verification

- Root `dart analyze`: clean.
- 48 focused tests pass across the mobile menu, outlined pills, layout,
  account identity, plugin sections and modal lifecycle suites.
- Mobile tests cover iOS/Android themes, horizontal swipes, fixed navigation
  while the feed scrolls, category switching, outside/Escape dismissal,
  320px width, 200% text, RTL, keyboard reveal and plugin selection on resize.
- The broader existing tabs, header-accessibility and notification-list suites
  have 13 pre-existing failures. An isolated checkout of `e809c83e3` reproduced
  the same four tab geometry/focus failures, three header size assertions and
  six notification scroll/background-tab failures.
- `flutter build macos --debug --no-pub -t tool/mobile_notifications_review_main.dart`
  succeeds. The fixture uses local account data and production menu widgets,
  with width, palette, text-scale, direction and styleguide controls.
- Native macOS fixture inspection covered the real popup in Dracula and light
  palettes, 390px and 320px viewports, 200% text, Replies selection, outside
  dismissal, the 900px category rail and the RTL styleguide example. Native
  accessibility exposed category names and complete notification labels.
  Touch swipes and keyboard reveal were verified in widget tests, not on a
  physical phone. CUA horizontal wheel input did not move the native fixture's
  strip; the iOS/Android touch-drag tests verified its scroll extent and access
  to the last category.
