# Custom sidebar link reordering

Desktop users can drag links within a custom sidebar section. The Native
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
or truncated server sections cannot be reordered. Moving links across sections
and dragging external links into the sidebar are outside this feature.

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
