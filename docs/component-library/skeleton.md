# Skeleton

The frozen [Skeleton reference](https://ui.shadcn.com/docs/components/base/skeleton)
was captured on 2026-09-08. Its Markdown SHA256 is
`cab955b03db8fe7a9f4e5bc71be4f72054782d29476b19fb2029f569a880df16`.
Installation, Usage, Avatar, Card, Text, Form, Table and RTL are all covered.
The reference has no component-specific prop table: CSS classes configure
geometry, while the language selector is a demonstration control.

## Public API

Import `package:discourse_native/discourse_ui.dart`.

| Widget / option | Behavior |
| --- | --- |
| `DSkeleton(width:, height:)` | Rectangular decorative shape. Omitted dimensions fill bounded axes and collapse on unbounded axes. Explicit dimensions obey parent constraints. |
| `DSkeleton.circle(diameter:)` | Circular placeholder, subject to the parent's constraints. |
| `borderRadius:` | Any `BorderRadiusGeometry`; directional corners resolve from the current direction. Defaults to the live site's base radius × 0.8, matching `rounded-md`. Use a large radius for pills or zero for square corners. |
| `color:` | Optional local background override; defaults to `DTokens.muted` (`bg-muted`). Used by sidebar shapes because their backdrop is itself muted. |
| `animate: false` | Static at full opacity. A shape can opt out of an animated region; it cannot override a region's disabled animation. |
| `DSkeletonRegion(semanticsLabel:, child:)` | Synchronized animation with one caller-localized loading label. All descendant semantics, pointer interaction and keyboard focus are excluded. |
| Region `liveRegion: false` | Exposes the label without requesting a live announcement. |
| Region `expand: true` | Fills bounded axes while preserving natural size on unbounded axes. Useful for full loading panels; defaults to false for inline compositions. |

Use `Expanded`, `FractionallySizedBox` and `AspectRatio` for relative geometry.
Placeholder dimensions are logical pixels; actual text continues to use the
host's text theme and text scaling. Skeleton introduces no text-scale owner.

```dart
DSkeletonRegion(
  semanticsLabel: 'Loading profile',
  child: Row(
    children: [
      const DSkeleton.circle(diameter: 40),
      const SizedBox(width: DSpacing.lg),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DSkeleton(height: 16),
            const SizedBox(height: DSpacing.sm),
            const FractionallySizedBox(
              widthFactor: 0.75,
              child: DSkeleton(height: 16),
            ),
          ],
        ),
      ),
    ],
  ),
)
```

The caller chooses when to mount the loading region and replaces it with ready
or error content. It owns networking, retry actions, loaded child state, focus
and any completion announcement. There are no hidden interactive descendants
or asynchronous continuations in the component. Place real controls outside
the region. To scroll a wide skeleton table, place the region **inside** a
horizontal scroll view, as the Table example demonstrates.

## Reference-to-Flutter visual mapping

The official [base-nova Skeleton registry](https://ui.shadcn.com/r/styles/base-nova/skeleton.json)
uses `animate-pulse rounded-md bg-muted`. The
[Card registry](https://ui.shadcn.com/r/styles/base-nova/card.json),
[theme radius scale](https://ui.shadcn.com/docs/theming#radius-scale) and
[Tailwind pulse](https://tailwindcss.com/docs/animation) were inspected on
2026-09-08. These are the design specification; no Material Skeleton/Card
presentation is substituted.

| Reference | Flutter rendering |
| --- | --- |
| `bg-muted` | Live `DTokens.muted`, with no foreground blend. |
| `rounded-md` / Card `rounded-xl` | Site base radius × 0.8 / × 1.4; explicit geometry overrides remain available. |
| Pulse | 2-second 1 → 0.5 → 1 opacity cycle, `Cubic(0.4, 0, 0.6, 1)`. `DMotion.pulse` is the 1-second leg. |
| Demo / RTL | 48px circle; 16px horizontal gap; 250×16 and 200×16 lines separated by 8px. RTL mirrors their reading-start alignment. |
| Usage | 100×20 pill. |
| Avatar | 40px circle; 16px gap; 150×16 and 100×16 lines, 8px apart. Total width 206px. |
| Card | Maximum 320px; 16px padding; 4px header gap; 16px header/content gap; 2/3 and 1/2 title widths; 16:9 cover; 1px foreground/10 outer ring. |
| Text | Maximum 320px; three 16px-high lines, 8px gaps; final line 75% wide. |
| Form | Maximum 320px; 80px/96px labels, 16px high; 12px label/input gap; 32px inputs and 96×32 button; 28px group gaps. |
| Table | Maximum 384px; five 16px-high rows separated by 8px; 16px column gaps; flexible first column and 96px/80px trailing columns. |

The current registry's aggregate example file has a square cover, taller form
controls and three table rows. The frozen documentation remains authoritative
for example geometry: this task retains its 16:9 cover, 32px controls and five
rows. The frozen catalogue is unchanged. Example state controls are outside the
reference compositions. Only the Card example has a card frame; the other
examples have no added border, padding or raised surface.

## Native adaptations and palette diagnosis

The component extends the existing shared rendering owner and preserves its
request-independent loading semantics, sizing and disposal. The initial legacy
675ms/0.62 pulse was superseded by the source-matched cycle above. A region shares
one animation; standalone shapes also work. Reduced motion and disabled
`TickerMode` stop at full opacity. Live theme changes retain animation state.

The earlier white-on-white defect was **the wrong color role**: default Light
`surfaceContainerHighest` is #FFFFFF, equal to the styleguide's floating
background. Its actual muted token is #F1F3F5. The initial 16% foreground blend
and decorative contrast threshold were therefore removed, not retained as a
visual deviation.

| Palette | Muted fill | Content background | Floating background | Half-opacity fill on content |
| --- | --- | --- | --- | --- |
| Light | #F1F3F5 | #FFFFFF | #FFFFFF | #F8F9FA |
| Dark | #1A1C20 | #212429 | #272B32 | #1E2025 |
| Forest | #EEF6F0 | #F8FCF9 | #FFFFFF | #F3F9F4 |
| Plum | #2B2030 | #211725 | #302336 | #261C2B |

A temporary Flutter probe measured these live palette values. Skeleton is
intentionally subtle; a text-contrast threshold is inappropriate. The concrete
exception is the navigation sidebar: its background equals muted in all four
palettes. Only those caller-owned shapes set `color: tokens.background`, the
native equivalent of a background-class override. No shared palette is changed.

Narrow constraints shrink the compositions. The table scrolls only below 256px,
where its fixed columns would otherwise leave almost no first column. Its scroll
view stays outside the noninteractive region. Local Ready/Error/Retry samples
exercise lifecycle and keyboard behavior; these are additional demonstration
states, not invented reference variants. Input examples use explicit neutral
borders and external labels, and ordinary actions use public `DButton`.

## Adoption audit

Removed `lib/src/shell/loading_skeleton.dart` after moving its behavior into the
public library. All ten region call sites and their shapes now use
`DSkeletonRegion` / `DSkeleton`, with explicit `expand: true` retaining the
application's existing bounded loading-panel geometry:

- Topic-list first load, including messages and filtered-topic labels.
- Topic first load, recommendations, and both pagination directions.
- Draft list, including wide and compact row geometry.
- User activity and user summary.
- Sidebar navigation.
- Chat channel first load and both pagination directions.

Loading conditions, errors, permissions, reading lanes, minimum post heights,
scroll retention and request ownership remain in their existing application
adapters. Chat skeleton gutters/alignment and topic skeleton avatar stacks now
use directional geometry. Full application loading panels retain their existing
noninteractive treatment until real data arrives.

The audit covered core, every module in `bundled_plugin_manifest.dart`,
`packages/discourse_voice/lib`, and `profiles/full/lib`. Chat owns the only
additional shared-skeleton callers. Assign, AI, Events, GitHub, Lazy Videos,
GIFs, Local Dates, Poll, Prometheus Alert Receiver, Reactions and Voice have no
separate content-skeleton rendering owners to replace.

Retained alternatives:

- Indeterminate activity and linear progress indicators remain under the
  concurrent Spinner task; no Spinner migration is claimed here.
- Avatar and emoji fallbacks retain identity/inline metrics and share their
  existing authenticated media loaders. Avatar presentation has its own
  catalogue task.
- Chat upload dominant-color backgrounds remain visible around actual images
  and preserve image-open interaction; they are media presentation rather than
  an inert loading composition.
- `SiteImage` loading builders and unavailable-image error fallbacks preserve
  caller-specific media sizing, authentication, decoding and errors.
- Unsupported-route placeholders and inline `PlaceholderAlignment` / composer
  atoms describe navigation or editing geometry, not loading content.

Exact automated checks, native inspection evidence and device limitations are
recorded in the Skeleton row of [progress.json](progress.json).
