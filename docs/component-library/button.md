# Button implementation and reference mapping

Current sizing: [24/28/32px Native scale](compact-control-sizing.md), with
12px normal labels and no extra-small controls. The frozen reference metrics
below describe the original upstream implementation.

Current shared control styling and application adoption: [2026-09-11 follow-up](control-consistency.md).

Task: `01a083ac-5fd5-78b1-9263-7e3218a878b6`, branch `codex/ui-button`,
base `2e894b5e`. Button owner implementation and native review are complete;
coordinator integration review remains. See [native evidence](button-native-review.md).

## Sources

Retrieved 2026-09-09 with read-only HTTPS requests:

- [Frozen documentation](https://ui.shadcn.com/docs/components/base/button.md),
  preserved at `reference/button.md`, SHA256
  `966cf16702128d2b385b62616ee24bb3b1b3b2ed7eebfc13ce411c90421f8910`.
  This exactly matches the frozen catalogue hash.
- [Official base-nova registry](https://ui.shadcn.com/r/styles/base-nova/button.json),
  preserved at `reference/button.json`, SHA256
  `9ba7e870178813f0552b818a913a2792fb500c779e36395740b4973e3025d427`.
- [Rendered documentation](https://ui.shadcn.com/docs/components/base/button).
  Browser and isolated native application comparisons are complete.
  See [the rendered comparison](button-rendered-comparison.md).
- Exact Lucide and Tabler example SVG URLs and hashes are recorded in
  `reference/button-icons.json`. Reusable Button accepts caller-supplied artwork;
  the documentation specimens use the original SVGs. Existing app icons remain
  caller-owned. shadcn license: `reference/LICENSE.shadcn.md`; Lucide license:
  `licenses/lucide.txt`; Tabler license: `reference/LICENSE.button-tabler.md`.

## Source-to-Flutter mapping

CSS px map to logical pixels with a 16px root rem. These are registry-derived
metrics; they are not represented as completed native measurements. The
2026-09-09 [audit](audit/button.md) corrected the rows marked below against
the live stylesheet.

| Registry | Flutter |
| --- | --- |
| Default `h-8`, xs `h-6`, sm `h-7`, lg `h-9` | regular 32, extraSmall 24, small 28, large 36px minimum surfaces |
| icon / icon-xs / icon-sm / icon-lg | `DButton.iconOnly` at the same sizes |
| 14px/20px medium; xs 12px/16px; sm .8rem | Explicit 14/20, 12/16, 12.8/22.4 metrics and 500 weight, no extra tracking |
| Default/lg gap 1.5, xs/sm gap 1 | 6px / 4px directional gap |
| px-2.5 or xs px-2, transparent 1px border | 10px / 8px padding plus 1px border-box inset |
| Inline icon reduces adjacent padding | 8px default/lg, 6px xs/sm plus border inset, mirrored in RTL |
| Default 16px SVG, xs12px, sm14px; icon-sm16px | Inherited IconTheme; explicit caller artwork can override |
| Spinner keeps its own size-4 | Loading spinner stays 16px in every size (audit) |
| `border border-transparent bg-clip-padding` | The fill stops at the 1px border, leaving the frame transparent (audit) |
| rounded-lg; xs/sm min(radius-md,10/12px) | Host radius; xs/sm use radius × .8, capped at 10/12px |
| Default primary, hover primary/80 | Live primary/primaryForeground tokens and .8 alpha hover |
| Outline background/border, muted hover; dark input/30 → /50 | Background/border tokens; dark input token alpha multiplied by .3 → .5 |
| Secondary → foreground 5% mix | Muted surface and 5% foreground interpolation (Flutter sRGB adaptation; CSS uses OKLCH) |
| Ghost transparent → muted; dark muted/50 | Matching token/alpha mapping |
| Destructive .1 → .2, dark .2 → .3 | Tinted destructive surface and destructive text, rather than legacy solid danger |
| Link primary, hover underline | Primary text, transparent surface and hover underline; native underline placement follows Flutter font shaping |
| focus-visible 1px ring border + 3px ring/50 | Native focus state plus 1px border and a 3px exterior ring painted by `DButtonDecoration` outside the unclipped Material; a dark outline keeps its input border (audit) |
| destructive focus and invalid ring variants | Matching destructive opacity mappings; `invalid` also sets the semantic validation result (audit) |
| active translate-y-px except haspopup | Fill, border, ring and content translate 1px together; `hasPopup` suppresses it (audit) |
| hover behind `(hover: hover)` | Reference variants fill only on pointer hover; a touch press just translates. Compatibility variants keep their pressed fill (audit) |
| aria-expanded surfaces | `expanded`: light outline/ghost → muted, secondary keeps its surface even while hovered, dark outline unchanged; exposed to semantics with `hasPopup` (audit) |
| disabled opacity .5 | Whole-surface .5 default opacity; scoped disabledOpacity override; no activation |
| transition-all | Fill, border, ring and translation animate together over 150ms with `Curves.ease`; zero when reduced motion is requested (audit) |

The app's configured palette, font and radius remain authoritative. Native touch
platforms expand invisible interaction targets to 48px. Legacy flat/inset shell
icons retain their existing 40/48/56px desktop hit dimensions and 4px visual inset.
Touch targets are clamped to at least 48px independently of the painted surface.
Large text can grow text surfaces; explicitly wrapping rich content retains its
own `Text.softWrap`/`maxLines`. The app keeps pointer cursors as permitted by the
reference's Cursor section.

## Public ownership and compositions

`lib/src/ui/components/d_button.dart` is the sole owner, exported by
`discourse_ui.dart` (and transitively the plugin SDK). The old theme renderer is
removed. `DiscourseButtonTheme` remains as the compatibility theme extension for
existing standard/danger/success/flat/transparent variants. Reference variants
read `DTokens` on every build. `primary` is the reference default; `regular` is
the reference default size. Variant `link` styles an action; `isLink: true`
changes navigation semantics to a link without the inherited button role.
Navigation callbacks own routing/URL handling and networking stays outside UI.

Loading is controlled by the caller. It disables activation, renders the shared
Spinner and retains the original rich accessible name. `loadingLabel` changes
visible status; `loadingSemanticLabel` localizes its separate semantic value.
No widget-owned Future can finish after disposal. The example owns its Future,
guards repeated activation and checks `mounted` after completion. Focus nodes
are borrowed. Tooltip and shortcut presentation use the completed shared owners.

The nine examples account for all frozen Button sections: variants, all sizes,
Icon/With Icon, Rounded, Spinner, the documented Button Group composition
(nested `DButtonGroup`s with a `DDropdownMenu` trigger, Label As… radio
submenu and destructive Trash item, using the exact Lucide artwork),
navigation/link semantics, RTL, shortcut hints, rich content and compatibility
states.

## Adoption

All existing direct imports now use the public library. PollCard's cast-votes,
Vote-on-web and Connect-account controls use DButton; vote eligibility, deadline
and asynchronous selection/error ownership remain in PollCard. Vote-on-web
exposes link semantics. UserSummary numeric count actions now use the public link-styled action, with
existing destination callbacks and semantic names preserved. The documentation's StyleguideAction now uses DButton
with ghost/outline surfaces and expanded selection, retaining DSidebar ownership.

Reviewed retained alternatives remain enumerated in `d_button_adoption_test`:
calendar day controls, Chat selection strips, composer taxonomy/submit tools,
DND/reaction option grids, topic period/incoming notices, selection/inline topic
tools, shell account presentation. These require their
own selection/navigation/composition owners; this task does not reclassify them
as completed catalogue components. CupertinoDialogAction remains scoped to
native Cupertino alert composition until the Dialog/Alert Dialog tasks. Existing
ordinary DButton callers automatically adopt the new owner, including core
creation, composer, settings, and plugin actions.

## Verification

- Root `flutter pub get --enforce-lockfile` and full-profile locked resolution
  passed without changing lockfiles or SDK pins.
- 222 focused impact tests passed: Button, adoption guard, PollCard, all existing
  styleguide tests, Chat header/upload, topic creation, account menu and post
  action accessibility. Log: `/private/tmp/button-final-impact.log`.
- Additional focused tests verify all icon sizes and padded iOS hit regions,
  Enter/Space activation, disabled transitions, borrowed focus ownership, link
  role, directional icon placement, live light/dark styling, underline and
  pressed/popup translation. Examples are tested at 260px, 200%, RTL, reduced
  motion; async repeat/disposal and local link navigation are covered.
- Root and full-profile `flutter analyze --no-pub` passed without diagnostics.
  A further 35 focused Button, example and UserSummary tests passed after final
  loading-padding and adoption changes. The isolated fixture build passed.
- `tool/component_library/button_review.dart` mounts real PollCard voting,
  signed-out connection and web-voting states with self-contained callbacks and
  theme/RTL/text controls. It opens the unchanged public styleguide.

## Native evidence

The isolated native review is complete. See [native review](button-native-review.md)
for screenshots, interactions, corrections, source hashes and integration limits.
The checkpoints below are historical build records superseded by final V8.

### Native-ready checkpoint

Local implementation commit: `08e9fbe9dcdb06078a9818bb2fe0ed29fbf5ebe8`.
The final fixture build is copied to
`/private/tmp/DiscourseButtonReview-3a88.app`, with display name **Discourse
Button Review**, ID `org.discourse.native.button-review.3a88` and isolated
`discourse-button-review-3a88` URL scheme. Deep strict ad-hoc signature
verification passes. The bundle has not been launched.

All compiled Dart inputs were byte-compared against the pre-build manifest at
`/private/tmp/button-build-source.json`, SHA256
`db225bac4c0677750e234f06996d9f85fa3047d289e87d0fb8cabc0a2fbaed8b`.
The copied kernel SHA256 is
`4eb63551ff6daaaf3f3d15c58f2ebb2f5c0f3f4fb01e559a666cdffff4309f4e`.
Final build log: `/private/tmp/button-review-final-build.log`.

All seven examples also pass the 260px/200%/RTL/reduced-motion layout check
in Light, Dark, Forest and Plum. Async/navigation examples pass separately
(`/private/tmp/button-custom-tests.log`). Native inspection was pending at this historical checkpoint.

### Coordinator touch-target correction

The coordinator identified that small legacy inset icons used negative Material
visual density on touch platforms. A new test reproduced a 40px target where
48px was required. The target density now clamps to at least 48px on iOS and
Android independently of the fixed 32px small inset surface. Desktop keeps its
40px target. The regression covers flat, flatClose and explicit inset outline
variants on all three platform profiles, semantic bounds and activation at a
point outside the painted surface. The previous inset geometry test now names
its macOS platform explicitly.

All 27 focused Button, Chat-header and topic-creation tests pass after the fix.
Root and full-profile analysis are clean. Logs:
`/private/tmp/button-inset-final-tests.log`,
`/private/tmp/button-inset-analysis.log`, and
`/private/tmp/button-inset-full-analysis.log`.

The corrected implementation is `50442c4e`. Its unlaunched replacement bundle
is `/private/tmp/DiscourseButtonReview-3a88-v2.app`, display name **Discourse
Button Review V2**, identifier `org.discourse.native.button-review.3a88.v2`,
URL scheme `discourse-button-review-3a88-v2`. Deep strict signature verification
passes. Every Dart source matches `/private/tmp/button-build-source-v2.json`,
SHA256 `fd7a457448ac5deab7de70468358ad86f0989940cd6da835d53d733cf8c756e5`.
Kernel SHA256:
`b229b90dee48bcda90cefc31e8a9f4ee398673f7400a8da4b9f3566ede5fbc26`.
At this checkpoint V2 replaced the original bundle; both are now superseded by V8. The original bundle is
superseded. Build log: `/private/tmp/button-review-v2-build.log`.

## Final native review

See [Button native review](button-native-review.md) for actual screenshots,
source provenance, Users touch-target corrections, native accessibility fixes,
final checks and the coordinator-owned root styleguide AX integration boundary.
