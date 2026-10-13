# Desktop panel and title-bar parity

Reference: final native-mockups snapshot `54ba01c`, with the desktop layout,
menu composition and split-control deltas from `6ba308a`, `05fe535`, `012ecab`,
`41d4082` and `03d7a28`. This updates the earlier desktop implementation through
`8d94d09`; other groups retain ownership of sidebar content, scrolling headers,
search, composer placement and material tokens.

- Docked navigation runs from the window top. macOS traffic lights sit 20pt
  from the leading edge and center on the 49pt chrome row. Navigation clears
  them, and the title bar starts above the document panels. The sidebar has no
  restored border. Collapsed navigation leaves the title bar its window width.
- Every visible desktop panel ends its strip with an inline Native split toggle.
  Activating it hides that panel; the remaining strip restores the hidden one.
  Both hide fully, including their seam and rail. Tabs, reader widgets, focus,
  saved split width, edge resizing, reduced motion and RTL remain supported.
- The approved Native `DLayoutGlyph` shows panel identities and editor docking.
  `DToggle.interactiveIcon` previews the resulting layout on hover, press or
  focus, within the existing 32pt control and 18pt artwork bounds.
- The focused panel supplies the title-bar action. New topic and New message
  share an icon capsule with the real account's draft menu, including its empty
  state. Reply uses the same icon-only action size. Existing permissions,
  message recipients, composer visibility and draft resumption remain intact.
- Chat and notification title-bar dropdowns use the same Native header, action,
  horizontal filter strip and rows. Chat reads the live account directory,
  orders unread conversations first and opens channels through its service.
  Notifications retain core/plugin filters, exact-post navigation, background
  middle-click and account ownership. Mark all read covers server-defined types
  through the existing guarded bulk-write reconciliation. Old-account gestures
  and writes cannot adopt a replacement account.
- Chat input stays inside its conversation; topic progress stays at the lower
  trailing corner. Existing topic/chat back-link clearance already uses the
  16pt inset below tabs, so those implementations are retained.

Header sizing was rechecked against native-mockups `7c86328` and its live CSS
layout on 2026-10-13. The row is 49pt; its 36pt search, creation capsule and
profile are at 8.5pt from the top, with 4.5pt below. The profile has a 2pt border
and 32pt image. Creation uses 28pt inner controls, 4pt capsule insets, 2pt gaps,
and a 32pt drafts trigger. Separate groups have 10pt gaps and a 14pt trailing
inset; chat and notifications retain the loose group's 6pt inner gap and 1pt
side border clearance. The existing Native avatar and chrome presets own these
bounds. At larger text sizes the row grows to fit the profile, and account
controls wrap at narrow widths without expanding their hit targets.

Validation: focused widget/unit files and targeted analysis; macOS debug build;
native hide/restore inspection; real-font shell and menu renders at 1000/1440pt,
light/dark, including 200% text. Header size and gap assertions, profile pixels
and hit bounds, keyboard/menu interactions, and large-count layouts at 320/390pt
pass in their focused test files. A macOS Metal render confirms the production
header composition. The host's minimum desktop width is 380pt. No production
fixture data is used.
