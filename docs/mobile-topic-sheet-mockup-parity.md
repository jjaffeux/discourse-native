# Mobile topic sheets

Reference: `discourse-native-mockups` at `3700183`, `App.tsx`'s
`phonePushed`/`pushedCard` presentation and `app.css`'s `.pushed-sheet` rules,
plus the supplied October 15 topic screenshot.

Mobile topics fill the content area below the persistent header. The Native
`DSheetVariant.page` paints the panel with 22px corners and overlays a 36×5px
handle 7px below its top. It adds no menu margins or reserved handle row. The
outer mobile surface stays mounted with a transparent fill, so the corners
show the window ground without a square panel beneath them.

The source list stays mounted but unpainted, unfocusable, and absent from
semantics at rest. Pulling the sheet reveals that same list without allowing
input to it; the sheet becomes opaque during the pull. Releasing below 120px
restores the sheet unless there is a downward flick above 500px/s. Cancellation
always restores it. Accepted dismissals finish moving off screen before going
Back. The handle, downward overscroll at the top of the reader, wheel input,
and native trackpad pans share dismissal. Ordinary reading continues to scroll.
Reduced motion completes an accepted dismissal immediately.

Both horizontal history callbacks are disabled on an open topic, including
across the header and dock. They become available again after dismissal.
The mobile header drops the old list backlink; the compact topic menu retains
its explicit Back action. Topics opened from Start also use the sheet.

Focused validation covers iOS and Android, light and dark appearances, Standard
and Liquid Glass settings, transparent panels, cancellation, list retention,
reading and wheel/trackpad input, 320px, 800px, and 1024px widths, large text, safe areas,
and reduced motion. `captureTopicSheet=true` renders open/pulled fixtures to
`/private/tmp/topic-sheet-*.png` for visual inspection. Captures use fake forum
content and do not establish physical-device rendering performance.
