# Start page parity

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, commits
`67200bc`, `9285bb0`, and `f8f48f6` (2026-10-02). These are the three updates
following the app's recorded mockup reference, `912027c`.

| Mockup change | Native implementation |
| --- | --- |
| One A–Z list in the reading column | All available destinations share one column. Preferences and Settings follow the alphabet. Only Filters remains on the header bar. |
| Sections and items have the same row shape, with no gaps | Headings and previews use Native `DItem` rows. Preview rows are transparent and indented to the heading's label. Native sizing and text scaling remain authoritative. |
| Pin any destination above the alphabet | Each heading has an independent Native `DToggle`. Pinned sections appear in separate Native cards, in pin order. Recently closed is pinned initially. Pins are shared by a forum's Start tabs for the account session. |
| Press or drag the alphabet to jump | The approved `DAlphabetIndex` component supports press, drag, cancellation, keyboard navigation and semantic activation. It includes shortcuts for pinned sections and settings. Scrubbing suspends list interaction and scrolling leaves enough space for the last destination to reach the header. |
| Drafts, Channels, Threads, Summary and Activity | Start shows authenticated destinations and enabled plugin destinations. Summary and Activity open the app's existing pages. Cached drafts resume through the existing draft lifecycle. |
| Events and threads show their latest items | A generic `StartPagePlugin` capability supplies cached previews. Chat supplies cached thread lists; Events retains the last unfiltered upcoming result. Start does not load these directories on entry. Account retirement clears private previews and pins. |
| Different marks for Summary, Activity, Users and Groups | Activity uses bars-staggered, Users uses users, and Groups uses user-group. Current navigation and restored default tab icons agree. |
| Rounded composer selectors and an inset action bar | Category/tag triggers use the existing Native pill shape. The desktop footer has 14px horizontal and 10px vertical insets. |
| Group Back, Forward and Reload in a pill; readable popup surfaces | Native already groups these controls in one pill with a separator before Reload. Native popup surfaces already use an opaque palette fill, so the mockup's browser-specific backdrop-filter workaround does not apply. |

Cached search continues to match titles, excerpts and tags before limiting
previews to four rows. Rows retain existing link menus, topic restoration,
unread/reminder metadata and desktop drag behavior. Destination availability
continues to follow the current account, category permissions and installed
plugins. Seeded mockup data is not copied into the app.

The Native alphabet index has a styleguide example. Focused checks cover list
order and resize behavior, pin/unpin and navigation, cached drafts and threads,
account invalidation, press/drag/keyboard/semantic index interaction, text
scaling and RTL. Related composer, navigation, plugin and styleguide tests are
run by file path. Real-font shell renders are inspected at phone and desktop
sizes, in light/dark themes and at 200% text. These are widget renders; a
physical-device deployment is not part of this change.
