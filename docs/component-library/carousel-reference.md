# Carousel reference mapping

Reference frozen on 2026-09-08:

- Documentation: `https://ui.shadcn.com/docs/components/base/carousel`
- Frozen Markdown SHA256: `98fdaa46f982b7ebf29b3c18f5e848f478244a766a0270f9c520f5e2eaf2fd59`
- base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/carousel.json`
- Registry response SHA256, fetched 2026-09-09: `14737a7cf92048df9de47f9d1a9527d6d3beafba12115f52a3c353134ee2b50b`
- Behavior contract: Embla options, events and autoplay documentation linked by the frozen page.

The frozen Markdown hash was reproduced before implementation. The registry
defines a relative carousel region, an overflow-hidden viewport, a flex track,
full-width slides, a `16px` leading slide gutter/negative track gutter,
horizontal or vertical axis, and outline `icon-sm` circular controls centered
`48px` outside the viewport. The icon artwork is `16px`. The host font and
palette remain authoritative. Circular controls use the live `3xl` radius
factor (`DTokens.radius * 2.6`), and DButton supplies the base-nova outline,
hover, press, focus, disabled and touch-target behavior.

## Flutter contract

| Reference behavior | Native mapping |
| --- | --- |
| Carousel / Content / Item / Previous / Next composition | `DCarousel`, `DCarouselContent`, `DCarouselItem`, `DCarouselPrevious`, `DCarouselNext` |
| `basis-full`, fractional and responsive basis | `extentFraction` and live `extentResolver(availableExtent)` |
| `pl-*` plus matching negative track margin | logical/end or bottom `spacing`; default `16px`, with no trailing visual bleed outside the clipped viewport |
| horizontal / vertical axis | `orientation: Axis.horizontal/vertical`, matching pointer paging and axis arrow keys |
| `align: start` and centered snaps | `DCarouselAlignment.start/center`; unsupported Embla options are not exposed as inert values |
| `loop` | adjacent virtual snaps in both directions with logical public indices; controller enabled states stay true when more than one item exists |
| `setApi`, select and scroll events | borrowed `DCarouselController`, `onSelected`, `onScrollStart`, `onScrollEnd`, and observable index/count/enabled/progress state |
| autoplay plugin | `DCarouselAutoplay` with delay, play-on-init, stop-on-interaction, mouse-enter and focus behavior plus `play`, `stop`, and `reset` |
| RTL direction option and flipped arrows | inherited `Directionality` controls page direction, logical control placement, key direction and chevron artwork |

The native API deliberately supports the behavior that can be implemented
faithfully by Flutter paging. It does not pretend to accept Embla's DOM-specific
watch callbacks, CSS containment, or free-drag options. A controller supplied
by a caller is borrowed. `plugins` are borrowed and detached; `ownedPlugins`
are detached and disposed by the carousel. Internally created controllers are
owned and disposed by the carousel. Theme, text scale and size changes rebuild
geometry without replacing selected logical state. Reduced motion converts
animated selection to a jump and suppresses autoplay. Looping is backed by a
high, item-count-aligned virtual page so previous, next, drag and autoplay cross
either logical boundary by one physical snap rather than traversing intervening
slides. The public controller continues to report finite logical indices and
progress.

The Flutter hit-test tree cannot activate a child painted beyond its parent's
bounds. `navigationInsets` therefore reserves the same `48px` offset in the
carousel's outer bounds and positions the controls around the inset viewport.
This preserves the reference geometry while making the entire control target
real. Consumers that compose no reference navigation, such as the cooked-post
image carousel, set `navigationInsets: false`.

## Application audit

`ImageGridCarousel` is the appropriate production adoption: it now delegates
its page track, swipe, selection controller, looping and keyboard behavior to
`DCarousel`. Its existing image tiles, lazy media ownership, gallery opening,
44px dot/counter controls and outer-topic scroll isolation remain unchanged.
Its existing widget fixtures are local-data production-widget coverage.

`LightboxGallery` is retained because each page owns photo-view zoom/pan and
scale controllers, resize bounds, download state, keyboard chrome and media
lifecycle. Nesting that specialized viewer in the generic track would create
competing gestures and duplicate controller ownership. Composer image-gallery
markup and its grid/carousel mode selector are retained because they edit post
markup rather than render a carousel. The event calendar PageView is retained
because it pages unbounded domain dates and publishes calendar state after
layout; it is not a finite content carousel. No plugin PageView was an
appropriate generic adoption.

## Prepared verification

- `flutter test --no-pub test/d_carousel_test.dart --test-randomize-ordering-seed=940219`: 9 passed.
- `flutter test --no-pub test/image_grid_test.dart --test-randomize-ordering-seed=940219`: 33 passed.
- `flutter test --no-pub test/styleguide/styleguide_access_test.dart test/styleguide/styleguide_page_test.dart --test-randomize-ordering-seed=940219`: 17 passed.
- Root `flutter analyze --no-pub`: clean.
- `profiles/full`: locked dependency resolution and `flutter analyze --no-pub`: clean.
- `flutter build macos --debug --no-pub -t lib/styleguide_main.dart`: built `build/macos/Build/Products/Debug/Discourse.app`.

The implementation task did not claim a browser pixel comparison or native
interaction run. The independent reviewer owns those checks, any fixes they
surface, source/kernel/signature evidence if it creates an isolated review
bundle, and the final local-main merge.
