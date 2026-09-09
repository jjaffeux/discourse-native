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

## Verification

Final behavior source is `63e2ee17ce344f1586a80b11b3ba74433fc6792c`, reconciled
onto main `892e1a97` as `6e57eda0815568c5a8176bb22dc8030209e8223f`. That
reconciliation changes progress ordering only; source, tests, runner and
lockfiles remain byte-identical.

- All 32 Sidebar/Sheet/example tests pass with seed 9092026. The icon-collapse
  test first reproduced a 16px overflow; the mobile RTL/200% test first exposed
  the squeezed menu. Both pass after their corrections.
- The combined run passed all 15 styleguide widget regressions, including
  actual mobile search focus, breakpoint changes, 320px/200% text, selection,
  search retention and reset. Its sole metadata-order failure was corrected
  by the Combobox owner on main `892e1a97`; the exact catalogue test passes on
  the reconciled candidate.
- Root and full-profile analysis pass. Formatting, `git diff --check`, and
  unchanged root/full lockfiles are verified. No full-suite claim is made.
- The actual styleguide entrypoint builds for macOS with an isolated identity.
  The runner files were restored exactly. The final bundle passes deep strict
  ad-hoc signature verification and its kernel equals the build framework.
  [Build provenance](evidence/sidebar/final-composition-build.json) records
  the source, bundle, source hashes, kernel and local-debug entitlements.

## Final rendered and native inspection

On 2026-09-09, this reviewer inspected the official base-nova embedded demo
(`/view/base-nova/sidebar-demo`) and the exact isolated bundle above under the
canonical desktop lease. Browser screenshots showed expanded dark/light
navigation, workspace/account dropdowns and the collapsed icon rail with a
round Avatar. The reference outer widths are 256px expanded and 48px collapsed
(observed inner widths 255px and 47px). Different capture sizes and application
fonts/palettes preclude a pixel-diff equality claim.

Native screenshots and interactions in this task verified:

- All six retained examples, neutral Light/Dark and the Forest site palette.
  Controlled inset toggles to its local Collapsed feedback; documentation
  retains compact rows; failure/Retry restores ready navigation with the final
  workspace/Input and Avatar footer intact.
- Workspace selection changes the trigger and local feedback. Account menus
  render beside the panel; Escape restores the trigger and Return reopens it,
  including in the collapsed floating rail. The 32px Avatar fits without the
  reproduced overflow; no collapsed Projects disclosure target remains.
- Projects collapses by pointer and expands with Space. Content scrolling
  leaves the workspace/search header and account footer fixed.
- At 360px, RTL, 200% text and reduced motion, the physical-right Sheet keeps
  the 288px panel contract. Workspace/account menus open vertically and remain
  visible. Workspace selection leaves the Sheet open. Escape closes the popup
  first, then the Sheet; Return reopens the Sheet from restored toggle focus.
  Enlarged content scrolls independently and selecting Home closes the Sheet.
- Resizing the actual styleguide window below its mobile breakpoint opens
  its real documentation navigation through Browse components. Literal typed
  search filters to Sidebar, and selecting the result closes the Sheet.

The earlier [native record](sidebar-native.md) explicitly reports the same
native synthetic-modifier limitation observed again here: Cmd/Ctrl+B and
Cmd/Ctrl+K did not produce a visible response through CUA. These bindings and
mobile search initial focus pass automated tests; they are not claimed as
native-verified. Return, Escape, Space, pointer actions and literal typing
worked. No spoken VoiceOver, iOS/Android/Linux device, authenticated account
flow, full-suite or comprehensive native accessibility claim is made.

The reference tab was closed, original browser theme restored, and the isolated
Sidebar app quit through its native menu; absence from the running-app list
was verified. The desktop lease was released. Final-owner composition review
is accepted with these explicit evidence limits; the original Sidebar merge
remains unchanged.
