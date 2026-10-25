# Port the mockups dashboard to Discourse Native

## Goal and source

Port the staff dashboard in `discourse-native-mockups/src/App.tsx`, from `DASH_PERIODS` through `DashboardView`, to the native app. Keep its six sections, date presets, responsive composition, role boundaries, traffic legend, site advice, and section configuration. Fetch real forum metrics instead of the mockup's seeded numbers.

The contract reference is the local Discourse source at `/Users/joffreyjaffeux/Code/discourse`. Its redesigned dashboard is gated by `dashboard_improvements` on the server.

## Existing architecture

Core pages use `CorePage`, `ContentRoute`, the route codec, `ContentPageContract`, and the `MainContent` page switch. Staff capability comes from `DiscourseUser.staff`; administrative actions require `admin`. Community navigation receives plugin entries such as Chat after its core links.

The API transport already owns authenticated same-site JSON requests. `AccountRequestSession` binds credential reads and network work to a `SiteLease`. A dashboard must drop permission-gated data when the account, lease, connection, or role changes.

The Native kit owns page headings, cards, tables, selection, menus, progress, and charts. The user authorizes extending or replacing chart code for this dashboard, while retaining only useful behavior. Existing chart consumers must remain functional.

## Design decision

A shell-owned account directory would provide a persistent dashboard cache, but would add lifecycle and shell wiring for a single page consumer. Choose a page-local `DashboardController` owned by `DashboardHost`. The host replaces it when its site/account/role identity changes. Request generations prevent a slower earlier date range from replacing a newer selection.

The domain is an immutable dashboard snapshot with ordered typed sections, per-section failures, server problems, and optional admin configuration. Date range is one typed value shared by every section and pinned-report request. Unsupported server and plugin data remain explicit states.

The page takes state and callbacks. The controller owns authenticated reads and confirmed mutations. The API adapter owns endpoint payloads and parsing. `ShellController` receives only route and refresh plumbing where required.

## Implementation sequence

1. Add typed dashboard periods/ranges, KPI values, section models, report metadata/results, problems, configuration, and legacy/error states. Add a narrow API adapter over the existing transport.
2. Add the lease-bound page controller. Fence credential reads, network results, range changes, disposal, and role changes. Preserve server configuration order and unknown plugin entries on save. Publish mutations only after success.
3. Extend Native charts only for the line and stacked traffic plots used here. Keep shared chart selection, tooltip, legend, colors, and semantics where useful. Check existing chart consumers before removing code.
4. Build `DashboardHost` and a responsive Native page with `DPageSurface.headed`. Show Highlights, Reports, Site traffic, Engagement, Search, and System. Keep server omissions and missing values distinct from zero. Render permission-filtered rows only when returned. Use real storage capacities; remote storage has no invented denominator.
5. Register the staff-only core route, sidebar and start-page entries, persistence/URL mapping, page rendering, and refresh behavior. Keep the existing external Admin entry.
6. Run dashboard model/API/controller/widget tests and directly affected route/navigation/chart tests by file path. Run scoped static analysis and existing relevant repository gates. Inspect narrow and wide rendered output, empty/partial/error states, and staff/admin differences.
7. Review the immutable patch independently, fix accepted findings, and merge the verified branch into local `main` from the main checkout. Preserve unrelated concurrent work. No remote push is requested.

## Server operations

| Operation | Contract |
| --- | --- |
| Read dashboard | `GET /admin/dashboard.json` with inclusive `start_date` and `end_date`; returns ordered `sections`, `problems`, and admin-only `configuration.sections`. |
| Load pinned reports | `POST /admin/dashboard/reports/bulk.json` with `items` and date `filters`; results are keyed by `source:identifier`, with per-report errors. |
| Save configuration | `PUT /admin/dashboard/configuration.json` with ordered `{id, visible}` sections. Admin only. |
| Refresh advice | `POST /admin/dashboard/problems.json`; returns refreshed `problems`. |
| Dismiss advice | Use `DELETE /admin/admin_notices/:id.json`, verified against the server route and dismiss service. Admin only. |

An index response without `sections` is a legacy dashboard. Show an availability message and a browser action. Do not manufacture metrics. Unknown plugin sections and unsupported report formats receive a browser action.

## Throughput checkpoint

- Blocking first steps are source investigation, role/API contracts, and chart authorization. These precede implementation.
- One implementation owner works in an exclusive worktree. A separate reviewer examines the completed patch.
- Dashboard mutable state belongs to a page/account lease. Main and the implementation branch remain separate until integration.
- One feature owner is the smallest safe decomposition because route integration, six section contracts, and Native charts must agree. Independent read-only investigation and review can run alongside it.

## Verification contract

Exercise date boundaries, null and zero KPIs, report errors, absent optional ranks, legacy payloads, unknown sections, and search logging disabled. Exercise range races and retirement during credential reads and in-flight requests. Confirm member denial, moderator read access, administrator mutations, failed mutation recovery, and account/role replacement. Verify 390-pixel and desktop layouts without overflow, chart legends and tooltips, section configuration, refresh, and route round trips.

## Implementation notes

The six sections now use the server payloads through a page-local controller. Dashboard navigation appears after the contributed community shortcuts, including Chat, in the sidebar and mobile dock. The start page also exposes Dashboard for staff.

`DCartesianChart` replaces the former bar-only owner. Its used modes are grouped bars, lines, and stacked areas. Existing bar callers and tests migrate in the same change. The styleguide includes an interactive dashboard plot example. Missing values remain gaps.

The focused dashboard tests render readable phone and desktop previews and exercise authenticated transport, date ranges, role denial, request retirement, stale responses, advice mutations, and confirmed configuration. The disconnect integration test uses bounded frames because app-wide animation settling after logout is not a reliable predicate; it asserts the actual dashboard denial and cleared loading state.

The repository Native ownership scanner reports an existing import violation in unchanged `lib/src/app_bootstrap.dart`. Dashboard code adds no ownership violations. The localization audit passes.
