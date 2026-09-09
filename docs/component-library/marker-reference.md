# Marker source and implementation

Captured 2026-09-09 against the frozen 2026-09-08 catalogue. The Markdown is
byte-identical to the assigned frozen snapshot. Primary sources are preserved in
`reference/marker/`; no catalogue resnapshot or dependency changes.

| Primary URL | SHA256 |
| --- | --- |
| https://ui.shadcn.com/docs/components/base/marker.md | `6945086da60adc35853f120678096e8a6e6485dc7b4e9e8eb8e7dfc023a69b90` |
| https://ui.shadcn.com/r/styles/base-nova/marker.json | `3e02a701ba7d9d4c4b41522e33c45171722d14c285c02995b8577b8a426a7a3d` |
| https://ui.shadcn.com/docs/utils/shimmer.md | `b245c422e81f8e29e3889d9007698ab1c61f3f185440cf6f136e2214d0616817` |
| https://raw.githubusercontent.com/shadcn-ui/ui/main/packages/shadcn/src/tailwind.css | `bc7d83425702955b4cb67cb14ede9d603f9d912376d57a2d81d661094d2a782a` |
| https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/book-open-check.svg | `1c637f1ef7909ed5764f546c7b01534fcfeb724706303781d083df9294fb17bf` |

The docs' manual-install source tag says base-rhea, but the project explicitly
selects base-nova. This implementation follows the fetched base-nova registry.
The supplied Spinner is the already merged component, with its Lucide artwork.
Example GitBranch/Search/BookOpenCheck paths use Lucide's 24-unit view box and
2-unit round strokes; attribution remains `licenses/lucide.txt`.

| Source CSS at 16px root | Flutter logical geometry |
| --- | --- |
| flex w-full min-h-4 items-center gap-2 | Full available width, intrinsic height ≥16, centered cross axis, 8px icon/content gap |
| text-sm text-muted-foreground | Host font, unscaled DiscourseTypography.sm=14, 20px leading, weight400, tracking0; live mutedForeground |
| MarkerIcon size-4 shrink-0, aria-hidden | 16×16, fitted child, no semantics, focus or pointer action |
| border-b border-border pb-2 | Bottom border1 using `DTokens.border`, 8px bottom inset: normal 20px line yields29px total |
| separator before/after h-px flex-1 plus mr/ml-1 | Two equal remaining-width 1px rules; 8px flex gap+4px margin=12px to content; label uses intrinsic width |
| MarkerContent min-w-0 wrap-break-word | Flexible wrapping label; separator centers text and preserves intrinsic width until bounded |
| flex-col example | axis: Axis.vertical, centered icon and text with8px vertical gap |
| root anchor underline | Explicit link action has underlined text and foreground hover; native text decoration uses font metrics (no independent CSS underline-offset support) |
| shimmer duration2s, angle20deg, spread3ch+40px | Owned2s linear ticker, 20° gradient, measured zero-glyph width×3+40; sweep −spread→width+spread, reversed in RTL |
| shimmer light currentColor alpha×.2; dark Oklch max(.8,L+.4), alpha+.4 | Oklab conversion changes lightness while preserving chroma/hue; premultiplied-alpha Oklab intermediate stop; sRGB gamut clipping |
| reduced-motion shimmer-none | Plain original text; no mask/ticker. App inactivity/TickerMode additionally pause motion |

The root has no fill, radius or shadow. Thus no radius-scale substitution is
needed. Borders retain alpha. The native action focus ring is an outside-only
2px stroke using the live focus token; this adds a visible keyboard affordance
where the unstyled polymorphic source leaves it to browser defaults.

## Public composition and semantics

`DMarker`, `DMarkerIcon`, and `DMarkerContent` have one reusable owner and are
exported from `discourse_ui.dart`. `variant` is inline/border/separator. Flutter
child composition, axis, color, borderColor and icon size replace CSS overrides;
there is no CSS-string or polymorphic DOM prop. Explicit `DMarkerAction` button
or link plus nullable onPressed distinguishes presentational and disabled
content. Host navigation stays in the callback. Borrowed focusNode is retained
without disposal. Enter/Space and pointer activation use Flutter actions;
focus-visible follows FocusableActionDetector. iOS/Android actions have48px
bounds; macOS/Linux stay intrinsic. Status is explicit `liveRegion`; callers
own task state and progress numbers, and no Form value is invented. The
semanticLabel can name icon-only content. Labeled separators expose ordinary
text, never a separator role. Decorative Spinner semantics are excluded.

The source allows arbitrary content, so inner actionable children retain their
normal owners. Avoid nesting an independent action inside a root action.
Marker is width-bound by its parent; separator layouts need finite width.
Large text wraps rather than truncating, including RTL and separator content.

## Adoption audit

- `StreamDaySeparator` (shared Topic and Chat timeline surface) now composes
  DMarker/DMarkerContent for labeled boundaries. The app retains dayLabel,
  floating/pinned background/border/shadow, tooltip, date-only jump callback,
  and existing44px timeline measurement. Only the date label is clickable;
  lines stay inert. Opening dates and floating dates retain no-divider policy.
  `marker_review_main.dart` mounts these actual widgets with only local data.
- Chat `_NewDivider` retains its trailing bold destructive New label and
  one-sided line. Replacing it with the reference's centered separator would
  change its intentional unread-boundary signal; it already uses DSeparator.
- Chat message delivery failure/retry and upload action spinners remain in
  their action/domain owners. Presence/user-status dots and unread count pills
  remain indicators/badges, not conversation markers.
- Core list refresh/loading, Topic numeric reading progress, Assign search,
  Events fetch progress, Voice activity and AI summary loading retain Spinner
  or Progress ownership. They do not become Marker merely because they show
  status. Poll results remain chart/domain presentation. Other bundled plugins
  (GIFs, Reactions, GitHub, Lazy Videos, Local Dates, Prometheus) have no matching
  conversation note/date owner beyond the shared timeline.

Four self-contained styleguide groups cover the frozen overview, all variants,
status+Spinner, shimmer, separator/date/elapsed notes, borders, inline/stacked
icons, buttons/links/disabled actions. Complete/restart and details/revert use
local state and accurate public API snippets. Examples remain baseline and the
progress row in_progress until actual reference-rendered/native review.

No CUA, browser rendering or native inspection has occurred. Tests establish
behavior/geometry only; shimmer raster/color-space interpolation and underline
placement must be checked visually. No pixel parity, VoiceOver, or device claim.
