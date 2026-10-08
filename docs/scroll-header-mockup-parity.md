# Scroll header parity

Reference: native mockups `2e80422`, `05fe535` and `31bdc07`, resolved against
the final four-day snapshot `54ba01c`.

Scroll distance now moves one continuous target for each page/panel. Coupled
mobile headers and navigation use the same displayed progress. A frame loop
smooths toward the target with a 40 ms time constant. Direction changes consume
40 px of slack, completed movement holds for 400 ms, and a 120 ms pause settles
partial movement. Direction is the default settling rule; Halfway uses a 50%
threshold, and Stay where left preserves the partial target.

The Preferences page offers the mockup's settling, threshold, pause, reversal
slack, hold and smoothing choices through Native selectors. These interaction
settings save locally per forum account, using the existing serialized
preference repository. Late reads cannot overwrite an edit or publish from a
retired account. Forgetting a forum includes these preference keys.

Floating headers move through render offsets and retain their paint layer.
The body viewport and full-header spacer stay fixed. Header masks, sticky day
geometry and floating controls follow the same visible extent. Only relevant
visibility boundaries rebuild widgets. Header size changes remeasure the
current head while retaining the full reserved extent. Native column pages and
mobile docks still release layout space with reading-anchor compensation.

Top reveal, short pages, focus protection, nested-scroll isolation, programmatic
restoration, page identity changes, optional bottom reveal and reduced motion
remain supported. Timers and tickers are cancelled on disposal. Day separators
switch between resting and floating Native surfaces; their rule stays in the
scrolling row. Desktop spacing, sidebar treatment and glass surface rendering
belong to their separate implementation groups.

Focused regressions cover continuous reversals, hold/pause timing, all settling
rules, 60/120 Hz elapsed-time smoothing, rendered geometry without content
rebuild/layout, account persistence, preference controls, mobile anchors, topic
paging and sticky dates. Production topic widget renders were inspected at
390×844 and 1100×800, light/dark, and 100%/200% text in shown, partial and hidden
states. Selected chat checks report zero held-message rebuilds while scrolling
and cover date navigation and resize/edit measurement updates. These are
widget/render tests, not physical-device performance measurements.
