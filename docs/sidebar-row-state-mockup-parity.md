# Sidebar hover and active rows

Reference: `discourse-native-mockups` snapshot `7c86328`, `src/app.css`
and `SidebarNav` in `src/App.tsx`.

- Category, tag, conversation, and voice-room rows use a flat 8% foreground
  hover tint. Menu selection uses a 13% foreground tint.
- Top-level Forum and Chat destinations use the navigation variant: the
  resting and hovered row remain flat, and standard selection uses the
  reference 12% foreground/background mix. Active labels use 600 weight;
  ordinary labels and icons use the reference text and secondary text colors.
- Liquid-glass selection uses the raised surface at 50% opacity in light mode
  and 42% in dark mode, the elliptical white sheen, a 1px rim and upper catch,
  and the reference outer shadow at 2px offset with 8px blur. Hover stays flat.
  These rows have no backdrop filter, matching the sidebar-specific CSS rule.
- The UI kit owns the painting through `DSidebarMenuButton` and the shared
  `DItemSelectionStyle.sidebar` treatment. Compact inbox rows use 8px corners.
  Selection semantics, keyboard focus, text scaling, and visible hit bounds
  retain their existing owners. The focused document controls selection.
- High contrast and Reduce Transparency use the standard row fills.

`sidebar_row_states_test.dart` checks rendered pixels, including the glass
sheen, hover exit, selection changes, and selection semantics in 18 cases.
`chat_sidebar_parity_test.dart` checks General selection through directory
navigation and tab focus in both panels; `sidebar_active_destination_test.dart`
pins the top-level navigation variant and the focused Forum destination.

For optional widget captures, set `SIDEBAR_STATES_REVIEW_DIR` while running
the state test by file path. For actual macOS rendering, run:

```sh
flutter run -d macos -t lib/sidebar_row_review_main.dart \
  --dart-define=SIDEBAR_ROW_REVIEW_CAPTURE=true
```

The fixture prints its native capture paths. It shows selected navigation,
menu, and conversation rows plus an inactive conversation under the pointer,
in light/dark standard and glass modes. This is a Native component fixture,
without an authenticated server session.

Four unrelated assertions in the existing Item/Sidebar component suites fail
identically on unchanged main: invalid sidebar dimensions, Item linear-size
media alignment, narrow RTL form state, and neutral Item selection styling.
The new state checks, focused-panel navigation, Chat sidebar/inbox, and
destination semantics checks pass.
