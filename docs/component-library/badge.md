# Badge reference and native mapping

Frozen Badge Markdown was fetched on 2026-09-09 and still matches the catalogue's
SHA256 `e174d14915336a823d0926ac774ba56767fd315950ac843dbe58fc36aba507bf`.
The six variants are primary (the reference's `default`), secondary, destructive,
outline, ghost, and link. A visual variant does not imply an interactive role.

## Sources

Local snapshots are under `reference/`, with the existing shadcn MIT license.

| Source | SHA256 |
| --- | --- |
| [Official documentation](https://ui.shadcn.com/docs/components/base/badge.md), `badge.md` | `e174d14915336a823d0926ac774ba56767fd315950ac843dbe58fc36aba507bf` |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/badge.json), `badge.json` | `ccc20021cdcbf0fb23c0d4d28f1da4adde8e51ba59f4b11dd2722ed97a5ee3a4` |
| [Registry examples](https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/badge-example.tsx), `badge-example.tsx` | `b5ec41da831fe3034393d95bd93625d0f2331115353c96d5773a921cefdc2a97` |
| [Lucide badge-check](https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/badge-check.svg) | `a83b36e35ed35be896c5e5d39d0a63ba4368735ac22f09a26a31726259467775` |
| [Lucide bookmark](https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/bookmark.svg) | `1d5023760db81f21c3b5a63f012ef540acc01932731c733e4645012a876d39f4` |
| [Lucide arrow-up-right](https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/arrow-up-right.svg) | `50b2503b9d11881142255466b7e3461d022b919735841c321d72003ac9959fe1` |

The upstream SVG snapshots above are retained as provenance. Live browser inspection found older bundled badge-check and bookmark paths; the examples now preserve the live bundled paths recorded in evidence/badge/reference-light-metrics.json, 24-unit view boxes, 2-unit strokes,
round joins and caps. Attribution is in `licenses/lucide.txt`. Generic DBadge
accepts arbitrary child artwork; app callers retain their existing DIcon symbols.

## Measured source mapping

CSS pixels map to Flutter logical pixels at a 16px rem root and 100% text scale.

| base-nova | DBadge |
| --- | --- |
| inline-flex, w-fit, centered | Minimum-size Row with flexible label and centered cross-axis |
| h-5 | 20px minimum visual height; 16px line plus two 1px internal vertical insets and two 1px borders |
| text-xs, font-medium | DiscourseTypography.xs 12px, explicit 16px leading, weight 500, zero tracking; host font family |
| px-2, icon-side p-1.5 | 8px logical text-side inset, 6px icon-side inset; border adds 1px |
| gap-1, svg size-3 | 4px gaps, fixed 12px fitted decorative icon/spinner slots |
| rounded-4xl | 2.6× host radius (10.4px at host default 4; 26px at reference radius 10), clamped by Flutter at small dimensions; tall labels need not be perfect capsules |
| border, border-transparent | Always-present 1px border; outline uses DTokens.border |
| default | primary / primaryForeground; interactive hover at 80% background opacity |
| secondary | muted / foreground, matching the existing host secondary mapping; interactive hover at 80% opacity |
| destructive | destructive at 10% light or 20% dark background, destructive foreground; hover at 20% |
| outline | transparent / foreground; interactive hover muted / mutedForeground |
| ghost | transparent / foreground; hover muted (50% dark) / mutedForeground |
| link | transparent / primary; underline on hover, no default underline |
| focus-visible | 1px focusRing border with an outer 3px ring at 50% opacity; destructive ring at 20% light / 40% dark |
| aria-invalid | destructive border; ring color 20% light / 40% dark, with 3px width only during focus-visible; invalid semantics |
| transition-all | 150ms `cubic-bezier(.4, 0, .2, 1)` for decoration; disabled when reduced motion is enabled |
| overflow-hidden | Rounded clipping of content inside the decoration; outer focus ring remains visible |

The reference's fixed height/nowrap can cut off native large text. Labels wrap
within finite parent constraints and grow intrinsically; text scaling has one
owner (Flutter's inherited TextScaler). Host radius zero intentionally removes
rounding. Tests exercise 0/1/4/12 radii at 300%, plus RTL at 200%.
Flutter text decoration cannot exactly specify CSS underline-offset:4; native
font underline placement is retained. No stock Material Chip is used.

`DBadgeSize.compact` is an opt-in Native adaptation for dense counts, authorized
on 2026-09-13. It uses a 16px minimum height, the same 12px font with 14px leading,
4px horizontal insets and no vertical padding inside the 1px border. Regular
badges retain the reference geometry. Both sizes grow with text scaling, wrap
under finite constraints and preserve the 48px touch target for actions/links.

Verification: 52 focused badge, styleguide, menu and migration tests passed;
root static analysis was clean. The isolated macOS preview displayed the real
user menu with Assign list (1) and Other (6), alongside the compact styleguide
example. Inspected dark, light and plum palettes, 200% text, RTL, selected Assign
list and the narrow icon rail. Native accessibility retained both unread labels.

## Composition and interaction

- `DBadge(child: ...)` is static, has no focus or activation owner, and can be
  placed inside another control without adding a nested target. Its text stays
  selectable inside an enclosing SelectionArea, as the reference span has no
  `select-none`. Only ghost and link paint a hover treatment on a static badge;
  other static variants do not track the pointer and never rebuild under it.
- `DBadge.action(onPressed: ...)` has button semantics, Enter and Space activation.
  `DBadge.link(onPressed: ..., url: ...)` has link semantics and Enter activation;
  URL is optional accessibility metadata and navigation belongs to the caller.
- Nullable callbacks disable actions, remove activation/focus entry, and apply
  50% opacity. Pointer activation first transfers focus to the clicked badge;
  subsequent keyboard activation cannot target a previously focused control.
  Owned focus nodes are disposed; borrowed nodes are never disposed.
- iOS/Android/Fuchsia actions reserve a transparent minimum 48×48 target while
  keeping the reference visual centered. Desktop pointer visuals remain compact.
  Native press uses the same active treatment as hover; the reference has no
  distinct pressed style or selected/toggle contract.
- `leading` / `trailing` are decorative and cannot take focus or pointer input.
  `semanticLabel` replaces child announcements, `semanticValue` and `liveRegion`
  describe changing work. Spinner state, completion, retry, permissions and
  counts remain in callers. DSpinner owns animation and reduced-motion handling.
- Color overrides are resolved in caller build methods, so current and open
  route themes update normally. Custom-color examples use the five documented
  light/dark pairs plus the live site tertiary pair.

## Adoption audit

Migrated renderers preserve their domain adapters and existing callback owners:

- `TopicUnreadBadge`: exact unread post count, singular/plural label and tooltip.
- `user_menu.dart` `_Badge`: compact size, core notification accent/foreground colors, 99+ visual cap,
  with the full count announced as unread; selection and feed permissions unchanged.
- `user_card.dart`: staff/suspension labels retain caller colors; earned badge
  count uses outline with the existing certificate artwork. No award model changed.
- `groups_page.dart`: membership status uses secondary DBadge.
- `group/group_members_view.dart`: owner labels use secondary DBadge.
- Chat drawer numeric badges: existing domain urgent calculation and 99+ cap;
  full urgent count exposed to accessibility. Muted/dot decisions unchanged.
- Spinner styleguide: removed its private badge renderer and uses public DBadge
  with DSpinner; other Spinner compositions remain unchanged.

Retained alternatives from core/plugin audit:

- UserMenuButton, InstanceRail and ChatHeaderButton overlay counters retain their
  small anchored overlay geometry and parent-owned accessible names; changing
  them to inline 20px pills would obscure avatars/icons. Avatar group flair and
  DAvatarBadge are image adornments, not inline labels.
- TopicStateDot, Chat drawer dots and SidebarBadge dots now use DNotificationDot
  for unread state without a count. Sidebar numeric menus are owned by DSidebar.
- Mention/Hashtag/Poll/Local Dates/ComposerLink Pill widgets participate in editor
  selection, text baselines, serialization and editing. ReactionPill and post
  likes are independent pressed/toggle reaction controls, not status labels.
- Topic taxonomy/category/tag chips carry colors, editing/removal, menus and
  navigation semantics; their dedicated owners remain. ImageGrid counter is a
  media overlay; AggregateHeroBadge is decorative artwork.
- BadgeSymbol and EarnedBadge render award tier artwork; tier text remains a
  text label. The full Discourse award catalogue is unrelated to generic Badge.
- Voice RecordingBadge is a full-width room-wide privacy notice and remains a
  banner. Voice, Assign, AI, Events, GIFs, GitHub, Lazy Videos, Local Dates, Poll,
  Prometheus and Reactions contain no other justified standalone badge owner.
  GitHub line counts are diff statistics, Events notices are banners, and input
  selection/filter chips belong to their pending control owners.

## Review fixtures and verification

`tool/component_review/badge_main.dart` mounts the unchanged styleguide shell and
adds an isolated fixture example. It uses actual GroupsPage, TopicUnreadBadge,
UserCardTarget and ChatDrawerChannelsView with in-memory fake stores/API. The
profile route needs ShellScope above the Navigator, as in the real app; the
fixture entrypoint and test supply that scope. No real account data is used.
Native build identity and observed comparison are recorded separately in
`badge-native.md`. Review readiness requires that comparison; automated test
success alone does not establish native visual fidelity.

The five custom-color examples use the current Tailwind OKLCH values converted
to nearest 8-bit sRGB with channel clipping (not the older v3 hex palette).
`reference/badge-colors.json` records each source value, resulting ARGB, the
[official theme.css URL](https://raw.githubusercontent.com/tailwindlabs/tailwindcss/main/packages/tailwindcss/theme.css)
and full-source hash. Wide-gamut browser output may differ at out-of-sRGB colors.

The migration regression run found that the new counter width left a restricted
Chat channel title only 12px at the minimum drawer width and 200% text, overflowing
its lock icon by 3px. In narrow large-text rows, Chat now places the existing
count/time metadata below the preview, leaving room for the title and lock.
Normal rows retain their trailing metadata column. The existing real-shell
regression now also asserts usable title width and the count's lower position.

## Browser comparison (2026-09-09)

The coordinator granted a browser-only slot while the Mac remained locked.
Chrome captures and computed-style records are in `evidence/badge/`, alongside
actual Flutter widget-test renderer exports. The saved harness loads macOS system
fonts and uses the macOS target platform; it is not a running macOS app. Neutral
comparison fixtures use radius 10 and reference gray focus/muted-foreground
colors without modifying shared tokens. SF versus Geist glyph widths and
anti-aliasing remain intentional host differences. Matched 638×288 exports show
20px compact bounds, directional 12px artwork, and corresponding light/dark
variants, custom colors, spinner and RTL layouts. Settled hover and keyboard
focus are captured separately. The website exposes five static variants and a
default-styled link; the separate link variant is checked against source and
Flutter exports, not falsely claimed as a live page example.

The official website `apps/v4/app/globals.css` overrides the Tailwind radius
scale: sm=.6×, md=.8×, lg=1×, xl=1.4×, 2xl=1.8×, 3xl=2.2×,
4xl=2.6×. The live base radius is .625rem (10px), yielding 26px for Badge.
The registry only names rounded-4xl; base-nova style.json contains no radius
values. Tailwind's default 2rem value is superseded by the website override.
Full source snapshots, URLs, hashes and compiled-style evidence are preserved
in `reference-radius-stylesheets.json`, `reference-website-globals.css` and
`reference-base-nova-style.json`. This correction affects only Badge. Shared
component radius mappings require their owners' separate audit: additive and
multiplicative small-radius formulas can coincide at 10 and diverge elsewhere.

Four host-palette large RTL exports and actual migration fixtures were also
rendered. The profile overlay export confirms staff/count composition; its
route inherits default text scaling, so it does not establish 200% overlay
coverage. That earlier browser-only checkpoint was later completed by the native review recorded in badge-native.md. The reference dark theme was
restored, no viewport override was applied, the sole task tab was closed, and
the browser slot was explicitly released.

## Exterior ring correction (2026-09-09)

Six pixel regressions reproduced interior tinting from Flutter BoxShadow in
light/dark ghost, outline and destructive badges. For example, a white ghost
interior changed under focus although the background token remained transparent.
`ring-pixel-regression.json` records exact before pixels; `ring-before/` contains
exports rendered from the previous committed source. Updated `flutter-*-ring-*`
images cover idle, focus, invalid idle and invalid focus for the three treatments.

The ring now paints only the difference between the outer and inner rounded
rectangles as an animated foreground decoration. It remains outside the child
clip, adds no layout size, interpolates width/radius/color over the existing
150ms duration, and respects reduced motion. Pixel tests replace the old
BoxShadow-count assertion and verify unchanged interiors, 3px exterior extent,
state colors, rounded corner exclusion, animation, disabled and focus removal.

Frozen badge.json and the same hashed live compiled stylesheet confirm that
aria-invalid only sets border and ring color. The 3px width utility is scoped to
focus-visible. Idle invalid now has only the destructive border; focused invalid
uses the destructive exterior ring. This is source fidelity, not a native
adaptation. Exact compiled selectors and initial shadow value are preserved in
`reference-ring-css.json`. No browser or native UI was accessed for this followup;
the subsequent assigned native/browser review is recorded in badge-native.md.

## Completed native migration review

The final assigned desktop slot completed native styleguide and actual migration
inspection, including root-navigator profile badges at verified 200% scale.
The Groups member-count footer overflow at 360px/200% now wraps in an Expanded
text region beside the membership badge. A meaningful narrow RTL regression and
native reinspection confirm the correction. The extra root-scaled profile and
focusable invalid fixtures live only in the isolated review entrypoint; shared
styleguide and dialog navigation are unchanged. See `badge-native.md` for exact
checks, signed source/kernel identity, evidence and remaining device limits.
