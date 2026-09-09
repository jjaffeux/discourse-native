# Carousel independent review evidence

Reviewed 2026-09-09 from `codex/review-carousel`. The frozen Markdown and
base-nova registry SHA256 values were independently reproduced as
`98fdaa46f982b7ebf29b3c18f5e848f478244a766a0270f9c520f5e2eaf2fd59` and
`14737a7cf92048df9de47f9d1a9527d6d3beafba12115f52a3c353134ee2b50b`.

## Browser reference

The approved browser surface rendered the official dark default example at a
320px content viewport. The item measured 336px including its 16px leading
gutter. Previous/next controls measured 28x28px and sat 48px outside the
viewport edges, matching `icon-sm`, the frozen registry, and the documented
mapping. The live palette, outline, circular shape, card spacing, clipped
track, and bounded disabled state were inspected. This was a geometry and
behavior comparison, not a cross-font pixel-equality claim.

## Native review

The isolated macOS bundle was built from the reviewed production source at
`/tmp/carousel-review-2d5354ca.YLhl2F/build/macos/Build/Products/Debug/Carousel Review 2d5354ca.app`.
It used bundle identifier `org.discourse.native.styleguide.carousel.2d5354ca`
and URL scheme `discourse-carousel-review-2d5354ca`. Deep strict ad-hoc
signature verification passed. Signed entitlement readback contained only the
debug/runtime and local app capabilities required by the build; restricted
APS, team, and application identifiers were absent. The final embedded kernel
SHA256 was
`ce5acb89990f8acd5c1b7bec62fdd5062266048ed936f9514d1440198143482f`.

Approved native inspection covered dark, light, and Forest custom palettes;
Fit and 360px widths; 100% and 200% text; RTL and reduced-motion preview
settings; horizontal and vertical examples; pointer drag and axis keyboard
navigation; enabled/disabled previous and next states; adjacent loop
wraparound; autoplay play, stop, and stable stopped state; and accessibility
nodes for the carousel, slides, and named controls. Focused widget tests cover
controller select/scroll events, autoplay interaction pause, and reduced-motion
suppression. The corrected centered loop exposed adjacent
`5, 1, 2` slides at the first snap and previous moved to the adjacent logical
last slide rather than traversing intervening pages.

The fixture button mounted the production `ImageGridCarousel` with three real
`ImageGridItem` values derived from local article data. Its gallery region,
local metadata, previous/next controls, dots, pointer paging, and selected
slide semantics were inspected without network or account writes.

Review fixes made loop boundaries physically adjacent, serialized autoplay
advances, added explicit autoplay and loop regressions, matched the official
28px control geometry, removed a 32px Card overflow in examples, and enabled
mouse drag paging through the host scroll behavior.

## Limits

No physical iOS/Linux device run or spoken VoiceOver session was performed.
The production fixture used deterministic local media metadata and did not
open an authenticated gallery or network session. Browser/native font
rasterization differs, so the review claims mapped geometry and behavior, not
pixel equality.
