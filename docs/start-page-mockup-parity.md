# Start page parity

## Current launcher layout

Reference: `/Users/joffreyjaffeux/Code/discourse-native-mockups`, Start launcher
change `09b38e04872e6c7ca23e6bf4c4922630fb9fb6c2`, checked against snapshot
`7c86328` on 2026-10-13. This layout supersedes the section list and pinning
below and the Topics pin layout in `start-page-topics-mockup-parity.md`.

| Start change | Native behavior |
| --- | --- |
| Recently closed is the only content list | It leads the shortcuts when nonempty and disappears when empty. Entries stack in bare Native Item rows, with their existing identity marks and titles. The section has no card, pin, timestamps, counts or excerpts. Reopening, link menus, and desktop dragging are retained. |
| Every other destination becomes a square shortcut | The approved Native Button launcher variant owns the icon tile, centered label, transparent resting surface, neutral hover/focus fill, keyboard activation, scaling and matching hit bounds. |
| Responsive grid | Cells wrap within the shared reading column with equal row and column spacing. The minimum cell extent grows with text size. Removing the alphabet rail restores the trailing content space and removes the artificial scroll tail. |
| Alphabetical destinations, then settings | Available destinations sort by their displayed labels. Preferences and Settings follow the alphabet, in that order. |
| Remove section previews | Topics, Bookmarks, Categories, Chat, Messages, Groups, Badges, Users, Activity, Channels, Threads and Events provide destination buttons without cached content rows. Opening Start requests no additional feeds or directories. |
| Remove pinning and the A–Z rail | Start has no pin controls, pinned cards, alphabet shortcuts, scrubbing or session pin controller. Saved legacy density preferences do not restore these layouts. The reusable alphabet component remains in the kit. |
| Drafts is conditional | The Drafts shortcut appears for authenticated readers with resumable cached drafts. It opens Native's existing Drafts page and uses the existing resume lifecycle. Start does not fetch drafts to decide whether to show it. |
| Search affects only Recently closed | Its match count includes only matching closed entries. Destination shortcuts stay available independently of the query. The existing chrome search interface is retained. |
| Upcoming events becomes Events | Enabled event destinations use Events on Start, in the sidebar and in retained destination navigation. The event route and site setting checks remain the same. |
| Keep the forum header and Filters | The forum switcher, external website link, Filters action, account permissions and enabled plugin destinations remain available. |

Changes to post reactions, general back/forward transitions, mobile docks,
platform glass and the Lab in the same mockup history are outside Start's
layout change.

The owning widget tests replace obsolete preview and pin assertions with grid,
conditional destination, closed-row and navigation contracts. Button checks
cover exact hit bounds, keyboard activation, disabled semantics, hover, text
scaling and both text directions. Rendered shell fixtures cover desktop and
phone, light/dark themes and 200% text. These are Flutter renders, not a
physical-device deployment.

## Latest account pages and desktop shell

The latest four mockup changes are implemented from `c0313acc`, `4e0e388b`,
`aedd6a65`, and `8d94d099` (through 2026-10-06).

| Mockup change | Native implementation |
| --- | --- |
| Summary tabs and stacked content | The profile heading and line tabs share the reading column. Highlights has four statistics and stacked topic/reply sections. Connections and Reading use boxed Native tables. Tables retain horizontal scrolling where large text needs more room. |
| Activity topic rows and filter | Native rows show the user's contribution, date, category, and whether they started a topic or replied. The All activity, Topics, and Replies filter retains pagination and exact-post navigation. |
| More Start previews | Cached activity, group memberships, earned badges, ranked summary connections, messages, and public channels populate the existing standard rows. Start does not fetch these directories on entry. Badge rows share the Native avatar medal composition. |
| Actions in the desktop title bar | New topic, New message, and Reply follow the focused panel. Expanded composers hide the action; minimizing restores it for the focused reader. The existing topic draft menu remains available. |
| Split view from the title bar | The secondary panel and divider disappear completely when hidden. The title-bar toggle restores its retained tabs, reader, and split width. The main panel retains its minimized rail. The Native toggle uses 18px open/close icons in a 32px control, a transparent background, color-only hover and press, and an accent color when selected. |
| Chat input and topic progress | The desktop chat input has an outlined well inside its page. Topic progress floats at the reader's lower trailing corner, and desktop topic/list footers no longer duplicate title-bar actions. |

Focused checks cover account-page navigation and pagination, cached previews,
large text, title-bar actions, retained panel state, fold animations, resizing,
RTL rail placement, composer docking, and chat composition. Summary and Start
were reviewed with rendered widget images; no physical-device run was made.

## Previous Start page changes

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
