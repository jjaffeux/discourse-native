# Desktop topic workspace

The inset **Topic view** toggle in the tab bar offers **Keep topic tabs with the
list** and **Split with the list**. The preference is stored locally in
`discourse_native.topic_presentation`. Existing Sheet preferences migrate to
merged tabs; Dock right preferences migrate to split tabs. The old topic
popover and Display menu's “Open topics” section are removed.

In merged mode, list and topic tabs share one bar. Opening a topic retains its
source list tab. Selecting that list returns to it without closing the topic.

In split mode, list tabs belong to the list panel and topic tabs belong to the
reading panel. Selecting another list keeps the selected topic open. Each
panel has a diagonal-arrows action that minimizes it to a rail of its tabs; see
[desktop panels](desktop-panels.md). Tab switchers, reordering, recently closed
tabs, and “Close other tabs” use the panel's scope. The reading panel does not
display a new-list-tab action.

The list resizes between 304 and 480 logical pixels. A split requires at least
520 pixels for the reader. Narrow windows use one combined tab bar, where list
tabs remain selectable. The split preference is retained for wider windows.
Switching mode or minimizing a panel retains the reader, list, and composer;
reading anchors and draft contents remain owned by their tabs and draft.
Touch platforms retain their existing inline topic navigation.

The composer surrounds both panels and supports left, bottom, right, and
full-screen placement. Its **Dock side / Full screen** selector uses the same
Native inset Toggle Group treatment. Dock side opens the three physical dock
choices. Full screen occupies the content workspace, leaving forum navigation
available; returning to a dock preserves the draft and selection.

## Verification

`test/desktop_topic_page_test.dart` covers scoped tabs, minimizing, merged lists,
narrow fallback, retained positions, composer placement, full-screen bounds,
shortcuts, and mobile navigation. `test/composer_docking_test.dart` exercises
editor retention, physical docking, and full screen. Toggle Group and preference
store tests cover the shared component and legacy preference migration.

`tool/topic_panels_review_main.dart` mounts production widgets with local fake
data and provides light/dark, narrow-window, and inset-toggle styleguide controls.
No account data is required.

Verified on September 18, 2026: static analysis is clean; 60 focused widget and
preference tests pass. The native macOS local-data fixture was inspected in
light/dark palettes for split tabs, swapping, merged tabs, the inset styleguide
control, full-screen composition, and returning to the bottom dock with retained
text. iOS behavior was exercised through widget tests, not a device run.
The broader forum-tabs bar/integration suites have 32 existing failures; the
same 32 were reproduced in an unchanged checkout of main at `6a00b42a7`.
