# Shared page surface

`DPageSurface` is the Native owner for bounded main-content pages. It composes
`DCard` for the desktop border and clipping, persistent `tabs` and `footer` slots,
an optional retracting `header`, and the existing scrollable `child`.
`framed: false` composes the same header/body behavior inside an existing frame
or the touch shell. The component does not create or dispose scroll controllers.

Headers are fixed by default. Topic lists (including Aggregate) and topic views
opt in with `hideHeaderOnScroll: true`: downward user scrolling hides the header
and upward scrolling reveals it. Other pages keep their headers visible. The
existing thresholds, reduced-motion behavior, retained header state, focus
protection, and route-identity reset are preserved. Horizontal viewports around
a main vertical table are supported; embedded vertical scrollers do not control
the page header. Tabs and footers stay outside the retracting region.

`limitContentSize` centers the page header, scroll body, and footer together in
an 825px-wide column when enabled. The outer frame and tab strip remain full
width. `DPageReadingLane` still computes padding for content inside that column
and supports fixed sidebars and non-scrolling content. The shell's
`ContentReadingLane` adapters supply app settings and retain desktop text-zoom
breakpoint calculations. The generic Native components do not depend on shell
controllers or settings stores.

## Adoption

- MainContent supplies the common frame and tabs for ordinary routes, including
  Users, Drafts, Groups, Upcoming Events, Categories, Tags, Badges and Preferences.
- Topic workspace list and reader panes use the same frame and tab slots. Their
  existing header builders compose an unframed DPageSurface within the frame.
- Aggregate uses the same page structure and retracting header.
- Users and Upcoming Events now consume the reading-width setting.
- Drafts, activity, group pages and Preferences no longer impose competing
  page-wide maximum widths when the setting is disabled.
- Plugins declaring ownership of their chrome retain that explicit contract.
  Sidebars and the composer continue using their existing WorkspacePanel.
- The obsolete shell ScrollRetractingHeader implementation was removed.

The application catalogue includes an interactive **Page surface** styleguide
example with tabs, width toggle, scrolling, and a fixed footer. The frozen
upstream component catalogue is unchanged.

## Width behavior — 2026-09-25

Normal now constrains the page header, body, and footer in one centered column.
The tab strip and panel frame keep their full width. New tabs use the same page
policy, and nested list and reader pages inherit it from their enclosing pane.

## Verification — 2026-09-19

- New DPageSurface widget tests: frame and tab/footer geometry, width switching
  without replacing the viewport or losing offset, route reset, main vertical
  scrolling inside a horizontal viewport, ignored nested vertical scrolling,
  and interactive styleguide at 360px / 200% text in light and dark themes.
- Existing scroll-retracting-header and reading-lane tests passed, including
  touch drag, keyboard focus, reduced motion, RTL sidebar geometry, and topic /
  group / aggregate integration.
- Event directory, group host, group page, and Preferences tests passed. Updated
  the Preferences assertion to expect the available lane rather than its old
  unconditional 680px cap.
- Broader Users, Groups, Drafts and topic-inbox tests contain 16 existing failures.
  The identical failures were reproduced in an isolated unchanged checkout of
  `573493177`; this change adds no failures to those suites.
- Aggregate view tests passed. Six existing styleguide-shell failures were also
  reproduced unchanged on `686905521`; the new Page surface example tests pass.
- Static analysis has no new findings; the existing prefer-const info in
  `test/content_route_test.dart:19` remains.
- Inspected native macOS dark Users and topic-workspace surfaces. Light/dark,
  narrow-size and interaction checks above are Flutter widget tests, not iOS or
  Linux device testing. No account data was submitted as part of this review.
