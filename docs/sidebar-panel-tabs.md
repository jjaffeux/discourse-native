# Sidebar panel tabs

The sidebar uses Native line tabs below the forum identity. Forum contains
forum navigation, Chat contains the Chat plugin's channel sections, and Voice
contains the Voice plugin's rooms. A tab changes the sidebar only; selecting a
channel or room keeps its existing navigation/join behavior. Incoming navigation
selects the corresponding panel. Switching sites or losing access reconciles the
selection immediately.

Chat uses its existing site/account/public-channel availability check. Voice
requires a supported platform, a connected account, the enabled site setting,
and a successful server directory response. An empty accessible Voice directory
still exposes room creation when permitted. A Forum-only sidebar has no tab bar.
The old separate-Chat-sidebar preference no longer changes this layout.

The Chat tab shows a compact green unread-message count across public channels
and direct messages, including watched-thread messages. Mentions are not added
again, and unread-thread totals are not treated as message counts. The badge
updates with live Chat state, disappears at zero, and displays 99+ above 99 while
keeping the full count in its accessibility label.

## Verification (2026-09-18)

- Compared the running localhost:5183 reference: its tabs change the sidebar
  without replacing the content pane.
- Inspected the real production sidebar in an isolated offline macOS fixture:
  Forum, Chat and Voice selection; light and dark palettes; 390px fixture width
  with 200% text; RTL. No overflow observed. Voice selection did not join a call.
  This is macOS verification, not an iOS device test.
- Added access, separation, keyboard, empty-directory and revocation widget tests.
  Updated Chat integration fixtures to select their sidebar panel explicitly;
  retained legacy pane-navigation coverage through the navigation service.
- Root static analysis passed. The focused Chat/Voice/tab checks passed excluding
  two existing Chat integration failures reproduced on unchanged `1795898e`:
  `disappears while chat is active on a compact shell` and
  `stacks grouped channel details on a phone`.

Chat section headers show the same unread-message badge while expanded or
collapsed. Starred channels (including starred DMs), Chat, and Direct messages
count their own unfiltered channels, so their totals do not overlap.
