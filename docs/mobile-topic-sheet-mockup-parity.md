# Mobile topic sheets

Reference: `discourse-native-mockups` at `a4c4875`, `App.tsx`'s
`phonePushed`/`pushedCard` presentation and `app.css`'s `.pushed-sheet` rules,
plus the supplied October 20 Start-page screenshot.

Mobile topics fill the content area below the persistent header. The Native
`DSheetVariant.page` paints the panel and overlays a 36×5px handle 7px below
its top. All four corners use the standard 22px page radius. The shared mobile
body stops above the bottom safe-area inset for Start, topic lists, ordinary
pages, plugin roots, topic sheets, and chat channel and thread sheets. Page
sheets add no menu margins or reserved handle row. The outer mobile surface
stays mounted with a transparent fill, so the corners show the window ground
without another panel beneath them. The dock and chat composer share the
body's consumed safe area and keep their existing screen positions.

The inbox topic source list stays mounted but unpainted, unfocusable, and
absent from semantics at rest. Pulling the sheet reveals that same list without
allowing input to it; the sheet becomes opaque during the pull. Releasing below 120px
restores the sheet unless there is a downward flick above 500px/s. Cancellation
always restores it. Accepted dismissals finish moving off screen before going
Back. The handle, downward overscroll at the top of the reader, wheel input,
and native trackpad pans share dismissal. Ordinary reading continues to scroll.
Reduced motion completes an accepted dismissal immediately.

Chat channel sheets, thread sheets, and topics opened outside a retained inbox
reveal the previous history visit's captured frame. Native owns the bounded
snapshot cache and image lifetime. The underlay does not mount another reader.
The snapshot follows its original capture coordinates, including the mobile
host's top gap, and keeps its aspect ratio. Keyboard changes retain the departure
frame. History, account, appearance, width, memory pressure, and lifecycle
changes clear it. Reduced motion still captures departures for vertical pulls.

Both horizontal history callbacks are disabled on an open topic, including
across the header and dock. They become available again after dismissal.
The mobile header drops the old list backlink; the compact topic menu retains
its explicit Back action. Topics opened from Start also use the sheet.

Focused validation covers iOS and Android, light and dark appearances, Standard
and Liquid Glass settings, transparent panels, cancellation, list retention,
reading and wheel/trackpad input, 320px, 800px, and 1024px widths, large text, safe areas,
and reduced motion. `captureTopicSheet=true` renders open/pulled fixtures to
`/private/tmp/inset-body-topic-*.png` for visual inspection. Captures use fake forum
content and do not establish physical-device rendering performance or exact
full-screen parity with the reference's different content.
