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
| `borderRadius:` | Any `BorderRadiusGeometry`; directional corners resolve from the current direction. Defaults to the live site's radius. Use a large radius for pills or zero for square corners. |
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

## Native adaptations

The component extends the app's existing shared skeleton rendering owner.
`DMotion.pulse` retains its 675 ms leg and ease-in-out opacity of 0.62–1.
A region shares one animation across its shapes; standalone shapes also work.
Reduced motion and disabled `TickerMode` stop the controller at full opacity;
live preference changes restart it when appropriate. Removing a region disposes
its animation, including while scrolling or switching examples.

The fill reads `DTokens.skeleton`, derived by blending the existing foreground
into the muted surface. Native inspection exposed the old light-theme fill as
white on white, so retaining `surfaceContainerHighest` would hide placeholders.
The derived token stays visible on content, floating and muted panels, including
at the dimmest pulse; it follows site palette changes without hardcoded swatches.
The default radius now follows the site, while custom radii and circles
remain available. Light/dark/site changes do not restart the pulse.
Native directional layout handles RTL; the component does not translate text.

The seven styleguide examples cover standalone geometry and motion, avatar,
card, text, form, table, and RTL. Ready/error/retry transitions use local sample
state. Ready card actions and the editable, validated form work. Flutter
primitives provide the card/form/table compositions while those independent
catalogue components are still planned.

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
