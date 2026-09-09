# Sidebar final-owner composition review

Review task: `01a086cd-3f9c-75b0-bda3-7d495758a941`.
The original component remains accepted at local merge
`93bfcf65f64868c92340f9aec8236d77585c3cd8`; this is its separate final-composition
follow-up. No second reviewer or original implementation remerge is needed.

## Source and reference

The frozen Sidebar documentation URL is
https://ui.shadcn.com/docs/components/base/sidebar, catalogue Markdown SHA256
`a48b885e4d6f0d8d1cb143ef436b80b90ebcf5e548347d455f6b201dcb637971`.
The committed base-nova registry and decoded source hashes remain recorded in
[sidebar.md](sidebar.md). Its mobile branch uses Sheet with an 18rem width,
zero panel padding and hidden close button; header/account examples compose
Dropdown Menu and Avatar, and project disclosure composes Collapsible.

Accepted owner pins on local main: Sheet `b67f0068104b922ec0e80170643eddced6e27c37`,
Input `7df72ef294826616e8ba24c31c6129d8e9041fec`, Collapsible
`985b4efdf4dd5e4502c98d4c2c0332df8e344982`, Dropdown Menu
`5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`, and Avatar
`5c78eb9d5c9db5f37ac7eaf8deab2233944dcbd0`.

## Changes and review findings

- Mobile Sidebar now composes controlled DSheet. Sheet owns route lifecycle,
  modal semantics, dismissal and focus restoration. Sidebar retains its width,
  side, provider shortcut and bounded independent scrolling contract.
- The Sheet owner's requested API boundary is retained: nullable exact width
  belongs to DSheetContent and showDSheet, clamped by both the configured cap
  and viewport. Existing 75% width and desktop-cap defaults remain unchanged.
  A nullable whole-sheet-scroll override allows Sidebar's bounded scroll area
  to remain the owner at 200% text with its fixed header/footer.
- The styleguide's mobile search shortcut requests initial focus through
  Sidebar/Sheet, so opening the route cannot replace the requested editor focus.
- Six existing examples now use the final Input, Collapsible, workspace/account
  Dropdown Menu and Avatar owners, with local actions and controlled disclosure.
- Reviewing icon collapse reproduced a 16px account-avatar overflow. Matching
  the registry's large-button zero-padding icon state fixes it. Hiding the
  complete group-label slot also removes an invisible disclosure focus target.
- Narrow RTL/200% interaction exposed squeezed outward dropdowns. Mobile
  workspace/account menus now open vertically, allowing the accepted popup
  owner to use the viewport width. Selecting a workspace leaves the Sheet
  open; Escape closes the account popup first and restores its trigger focus,
  and a second Escape closes the Sheet.
- The styleguide is the actual application adoption. Forum and Chat retain
  their documented domain-specific navigation adapters; their routing,
  memberships, permissions and persistence were not part of this follow-up.

## Verification in progress

The initial composition source is `e8b1543640f11cc18cbb1132060755610c224815`.
Focused Sidebar, Sheet and example tests passed 30 checks with seed 9092026.
The added icon-collapse regression first failed with a 16px overflow, then
passed after the correction, including account-menu Enter/Escape and restored
focus. The real styleguide mobile search and 320px/200% text regressions passed.
Final candidate checks and the rebuilt native bundle will be recorded below.

The required current browser/native composition inspection is pending the
canonical FIFO desktop lease. Earlier Sidebar native evidence remains in
[sidebar-native.md](sidebar-native.md); it does not establish acceptance of
the changed mobile and final-owner compositions. No new native result is
claimed yet.
