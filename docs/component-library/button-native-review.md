# Button native review — 2026-09-09

Owner task `01a083ac-5fd5-78b1-9263-7e3218a878b6`, branch `codex/ui-button`.
The coordinator granted exclusive native/browser CUA access. Both slots were
explicitly released after final V8 accessibility confirmation. No main app,
production service, real account, browser tab or release configuration was changed.

## Evidence and provenance

`evidence/button/native-v6-*.jpg` are actual macOS CUA screenshots, not widget
exports. V6 contains the final visual renderer, Users layout correction and the
real styleguide/Poll/Users fixtures. V7 adds populated real UserSummary categories;
V8 additionally corrects icon names and duplicate category-count semantics.
Those changes do not alter the compared Button surfaces. Final V8 screenshots
and AX text are `native-v8-summary*` and `native-v8-columns*`.

Final inspected app: `/private/tmp/DiscourseButtonReview-3a88-v8.app`, bundle ID
`org.discourse.native.button-review.3a88.v8`. Kernel SHA256:
`f1d36a8fc4850705bb5fcc310bef9d27677695a3c96499f5a45fd05e95843f8c`.
Pre-build source manifest is preserved as `evidence/button/native-v8-source.json`,
SHA256 `7c91e347ee640e38f70241bc461809724f7ed115e5f4d014357a908dfd5f3eff`.
All listed source bytes were checked again before copying/signing the bundle.
Deep strict ad-hoc signature verification passed. Review-only entitlements omit
restricted APS/team/application identifiers; project provisioning is unchanged.

## Actual observations

- Six variants render in native light/dark palettes; all four text/icon sizes,
  exact SVG compositions, rounded shapes, rich wrapping and invalid/expanded
  trigger specimens were inspected against the completed browser comparison.
- Forest and Plum token changes apply live. At 360 logical pixels and 200% text,
  variants wrap without overflow; the Arabic example wraps its spinner onto a
  second line and mirrors its directional icon. Full preview RTL reverses the
  variant order. Corresponding screenshots preserve these states.
- Generate shows its spinner and disabled surface while pending. Two immediate
  clicks complete one operation. Tab/Return then completes operation two.
  Unavailable remains inactive. Focus/keyboard handling has additional focused
  widget-test coverage; no spoken VoiceOver claim is made.
- Login opens the local preview route and Back to examples returns. The styleguide
  action controls successfully select examples, themes, 360 px, 200% and RTL.
- Real PollCard starts with Cast votes disabled. Selecting Alpha enables it;
  submission disables selection/action and exposes Saving vote, then reports
  Saved a. Connect account and the semantic Vote on web link invoke their local
  callbacks. No network navigation is involved.
- Real Users toolbar aligns search and period control targets. The column editor
  preserves 40px pointer targets and reserves 48px in both axes for an iOS theme.
  Clicking near the bottom edge reorders on both profiles; Save reports column
  order 2, 1, 3. These are macOS-hosted iOS-theme checks, not an iOS device claim.
- Native inspection found that CheckboxListTile secondary merged arrows into its
  checkbox semantics and constrained their height. Arrows now sit beside the
  checkbox, each with an independent full target. Explicit inset surfaces retain
  the authored compact desktop target.
- Native inspection also found unnamed icon-only buttons and duplicate nested
  category-count buttons. Icon-only tooltip text now supplies the default semantic
  label, with explicit labels taking precedence. UserSummary passes its descriptive
  name directly to DButton. V8 AX confirms named independent reorder actions and
  exactly one named button for each category count. The real count was activated;
  its search destination is verified by the existing controller integration test,
  since this isolated fixture does not mount the full shell search destination.

## Checks and integration boundary

Final 40 Button/reference/example/adoption/UserSummary tests pass. UsersPage has
48 passing tests, including iOS/macOS target size, semantic name/bounds and outer
edge activation. Its only two failures are the previously identified Avatar
assertions on this older base; coordinator main already reconciles those. Preserve
main's Avatar assertions during merge. Root and full-profile analysis pass without
diagnostics. Logs: `/private/tmp/button-final-focused.log`,
`/private/tmp/button-users-final.log`, `/private/tmp/button-final-analysis.log`,
`/private/tmp/button-final-full-analysis.log`.

The baseline styleguide root exposes only its search field to native AX on this
branch. Menus and production fixtures expose controls normally. The coordinator
owns the root semantics correction and its combined native recheck. This was
reported and not patched here. Button owner work is review-ready; the catalogue's
baseline status is intentionally left for coordinator promotion after that merged
root accessibility check. No iOS/Linux native run, spoken VoiceOver session or
cross-renderer pixel-diff is claimed. Browser/native font and interpolation
adaptations remain documented in `button-rendered-comparison.md`.
