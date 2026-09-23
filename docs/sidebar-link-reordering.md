# Custom sidebar link dragging

Users can drag links within a custom sidebar section or into another editable
custom section. Drop on either side of a destination row to choose its position,
or on a section header to append, including empty and collapsed sections. The Native
`DSidebarReorderableMenu.sliverBuilder` owns the drag proxy, insertion gap,
shared-viewport auto-scroll, Alt+Up/Down shortcuts and Flutter's accessible
reorder actions. Its caller supplies stable row keys and persists the order.
A null callback disables reordering. Touch uses a long press to start dragging;
ordinary swipes still scroll and taps open links.

The app saves with `PUT /sidebar_sections/:id/reorder.json` and a JSON
`links_order` array containing every SidebarUrl ID in the resulting order.
It replaces only the affected section with `sidebar_section` from the response.
The dropped order stays visible while confirming and saving, so links do not
jump back between the drag animation and the response. This preview belongs to
the displayed section; the controller retains the saved order until success.
Cancellation or failure restores that order, and failures show a retryable error.
Replacing the section or losing reorder permission discards its preview.
Same-position drops do not write, and another reorder is disabled while saving
or confirming. Site lifecycle leases prevent a response from restoring an
account's sidebar after sign-out.

Only signed-in users can reorder. Public sections require an administrator and
confirmation that the change affects everyone. Built-in sections and incomplete
or truncated server sections cannot be reordered. Dragging external links into the sidebar is outside this feature.

Cross-section moves use `PUT /sidebar_sections/:id/move_link.json` with
`link_id`, `target_section_id` and zero-based `position`. Both returned
`sidebar_sections` replace the saved source and destination together. The UI
previews both lists during confirmation and saving, restores them on cancellation
or failure, and disables overlapping edits. Public source or destination sections
require administrator rights and one confirmation. Full sections reject drops;
site lifecycle leases discard late responses after sign-out.

`DSidebarReorderScope` connects the menus in the same viewport.
`DSidebarReorderableMenu.sectionId`, `onMove` and `canMove` opt into transfers;
`DSidebarDropTarget` lets headers accept append drops. The Native kit paints a
2px insertion line with the theme's primary color. Flutter retains ownership of
pointer recognition, touch long press, the proxy, same-section reorder gaps,
keyboard/accessibility reorder actions and edge scrolling. Rejected custom-section
headers cancel a drop rather than rearranging the source. Application code owns
permission checks, confirmation, optimistic state and API persistence.

Core references inspected in `/Users/joffreyjaffeux/Code/pr-discourse`:

- `frontend/discourse/app/lib/sidebar/section.js`: permissions, no-op detection,
  confirmation, reorder request and response replacement.
- `frontend/discourse/app/components/sidebar/common/custom-section.gjs`:
  touch-first exclusion.
- `app/controllers/sidebar_sections_controller.rb` and
  `app/services/sidebar_section/reorder_links.rb`: complete-ID validation,
  permission checks and public-section updates.

## Verification

- `flutter analyze --no-pub`.
- `test/sidebar_reorder_test.dart`: real request method, path, credentials and
  JSON body; returned order; incomplete sections; mouse drags in both directions;
  unchanged drops; pending/failed saves; public confirmation/cancellation;
  anonymous and non-admin exclusions; mobile long-press dragging; late response
  after sign-out. Frame-by-frame drop checks cover a delayed successful save on
  macOS, iOS and Android platform overrides; failed saves restore the old order
  and can be retried.
- `test/d_sidebar_reorder_test.dart`: keyboard movement with retained focus,
  boundaries and shared-viewport drag scrolling in light/dark at 200% text.
- Existing Sidebar, lazy Sidebar, styleguide examples, sidebar icons, API,
  shell navigation and control-adoption regression tests passed. The new
  styleguide example remains last to preserve existing example ordering.
- Built the offline `tool/sidebar_review_main.dart` macOS fixture. Launched an
  isolated ad-hoc signed bundle with development-only entitlements and verified
  production-sidebar and styleguide dragging. Inspected production light and
  styleguide dark/200% RTL views. Keyboard behavior was verified in widget tests;
  native automation key combinations did not produce a reliable result.
- Native review used fake accounts and API responses. No real forum data was
  changed. iOS behavior was checked with a widget-test platform override, not a
  physical device. The final disabled-state accessibility adjustment was checked
  by focused tests after the native review.

## Cross-section verification — 2026-09-23

- 97 focused tests passed across sidebar reorder, Native reorder, sidebar,
  lazy sidebar, examples, active destination, section store, panel tabs and icons.
  Coverage includes row gaps, empty/collapsed destinations, moving the last source
  row, rejected public/full destinations, failed saves, cancellation, sign-out,
  iOS/Android long press and shared-viewport scrolling with 200% light/dark text.
- Updated the older drag helpers to use continuous pointer movement and open the
  mobile Shortcuts page. Three existing layout expectations now match the current
  34px regular / 40px large control scale. No control geometry was changed.
- `flutter analyze --no-pub` and the offline macOS review build passed. Lockfiles
  and the Flutter pin were unchanged.
- Native inspection used the isolated, ad-hoc signed Sidebar Cross Section 4200
  fixture (`org.discourse.sidebar-cross-section-4200`), with fake accounts and
  responses. Observed same-section reordering, sequential transfers into Team
  links, a drop into the collapsed destination, and the empty source header after
  moving its final link. The actual styleguide example accepted transfers in both
  directions and rendered dark 200% RTL without overflow. No real forum data was
  changed. Physical iOS/Android devices and spoken screen-reader output were not
  exercised.
- The broader control-style adoption guard has a pre-existing, unrelated failure:
  `composer_block_surface.dart` supplies `backgroundColor` but is absent from its
  exception inventory. That source and guard were left unchanged.
