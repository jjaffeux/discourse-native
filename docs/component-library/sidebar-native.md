# Sidebar native review — 2026-09-09

Final implementation: `47aabf60e65dff047cdf80dd6e29203a93fb8012`.
The coordinator granted the exclusive inspection slot. Only the independently
built sample-data styleguide was launched; no real account application was
opened, closed or modified. The coordinator owns the subsequent documentation
shell adoption and its native inspection.

## Build provenance

`flutter build macos --debug --no-pub -t lib/styleguide_main.dart` succeeded.
The temporary runner identity was Sidebar Review 0cca /
`org.discourse.sidebarreview0cca` / `discourse-sidebar-review-0cca`.
Runner source files were restored after each build. The built Info.plist was
verified directly; the Xcode warning about its debug build-setting identity
was not used as identity evidence.

The final bundle passes `codesign --verify --deep --strict` after local ad-hoc
signing. Bundled App.framework kernel bytes equal the build App.framework
payload. SHA256:
`b400402635cd61ec213815b387448a848a08bca5fe36f6081f43ee86191488a7`.
No global ensureSemantics, SDK changes or system preference changes were used.

## Reference comparison

Opened the official base-nova Sidebar documentation in one task-owned Chrome
tab. Inspected dark and light expanded examples and light icon collapse,
alongside the documentation site's compact selected navigation pill. The
registry snapshot and exact metrics are in sidebar.md and reference/sidebar.json.

Native screenshots were1144×768; reference captures1388×952. Native previews
used Fit and360px,100% and200% text, plus RTL/reduced motion. This is an
intrinsic-metric and visual comparison, not a pixel-diff claim. The native
styleguide uses the configured app fonts/palettes and local sample labels and
caller icons. The generic trigger uses the exact PanelLeft SVG. Main menu
rows have no inter-row gap, submenus4px, and the native documentation example
uses the documented30px minimum override and neutral selected pill.

All screenshots and native AX observations are inline in the Sidebar task.
The native AX tree exposed the search field and selection menus but was sparse
inside the preview; visible coordinates and real keyboard actions were used.

## Findings and corrections

- Floating icon mode showed an actual2px RenderFlex overflow. A layout border
  was consuming the inner icon width. The final implementation paints the
  border independently; the added regression verifies32px inner menu width.
  The final native collapse showed the complete icon column without stripes.
- Escape originally required Tab to enter the mobile subtree. A new autofocus
  target below the modal shortcut scope establishes immediate keyboard entry.
  On the final native build, opening and immediately pressing Escape dismissed
  the panel and restored the trigger focus ring.
- Coordinator review fixes are included: pointer activation takes focus,
  mobile breakpoint dismissal clears openMobile, and iOS/Android controls
  provide48px minimum targets around the compact visuals. Those two platforms
  were checked by widget tests, not physical device runs.

## Actual interactions

- Application: selected Inbox, observed the neutral selected treatment and
  local feedback; clicked the trigger to collapse offcanvas while retaining
  selection. Independent content scrolling preserved the header; footer
  visibility was also inspected by scrolling the enclosing preview.
- Floating: inspected expanded inset spacing and final collapsed icons. The
  corrected ring preserved compact artwork and left no layout overflow.
- Documentation: inspected same-background light navigation at100%, then200%
  RTL, then360px Forest with reduced motion. Labels grew; the input hint
  truncated without obstructing editing. This is the independent documentation
  composition, not the coordinator's new styleguide shell.
- Right-side mobile: inspected360px RTL200% Forest, switched the still-open
  panel live to Plum, selected Inbox and observed dismissal/trigger focus.
  Return on the restored trigger reopened the panel. Final immediate Escape
  behavior was checked in the corrected floating/mobile example.
- Controlled inset: observed Expanded → Collapsed on pointer activation,
  followed by Return → Expanded; the parent status followed the controlled
  value and the inset content remained visible.
- Loading/recovery: inspected the Skeleton composition, simulated failure,
  clicked Retry and obtained navigation. Scrolled to project submenus,
  selected Design, then collapsed Projects; selection feedback remained.

## Verification and limits

Final focused command passed21 tests with seed9092026:

```
flutter test --no-pub test/d_sidebar_test.dart \
  test/styleguide/sidebar_examples_test.dart \
  test/styleguide/styleguide_page_test.dart \
  --test-randomize-ordering-seed=9092026
```

Root and full-profile analysis passed after the corrections. Root/full locked
pub get passed; lockfiles and Flutter pin were not changed. Formatting and
`git diff --check` passed.

Cmd/Ctrl+B did not produce a visible toggle through the native CUA attempts;
those exact bindings pass widget tests. Return,Tab and Escape were visibly
verified. This native shortcut observation remains a review limitation, not a
claim of successful native shortcut execution. No spoken VoiceOver or iOS/Linux
device inspection was performed. Sheet/Input/Collapsible/Dropdown Menu remain
pending catalogue owners as documented in sidebar.md. Live forum/Chat adapters
remain intentionally retained; only the coordinator's documentation shell is
the first app adoption.

Cleanup: restored the official page's original dark theme, closed the created
reference tab, and quit only Sidebar Review 0cca using its menu. A final global
CUA inventory returned no app with its bundle ID and no reference tab with
ID1360425131. The slot was released to the coordinator before final metadata.
