# Empty reference and adoption record

Scope is the frozen 2026-09-08 Base UI page. Captured Markdown is byte-identical
to SHA256 `052a80cfb1f64c836d1aa39c739da20ab26848f94555cd13f3c6a598267c9d37`.
The complete page includes all seven example sources; registry example JSON
endpoints returned 404, so the fenced source in the frozen Markdown is used.
Source URLs and SHA256 values are in [the manifest](reference/empty/manifest.json).
Registry source is `https://ui.shadcn.com/r/styles/base-nova/empty.json`.
Tabler folder-code/cloud/bell SVGs are captured with MIT license and displayed
without the app's DIcon glyph scaling. Production status icons retain their
existing domain artwork, inheriting the new media's 16px bounds.
The final review also captured the frozen examples' Lucide RefreshCcw, Plus and
ArrowUpRight artwork with its ISC license. These restore the documented button
compositions instead of substituting platform glyphs.

## Source-to-Flutter measurements

These are source-derived measurements, with unit-test geometry verification;
browser-rendered/native comparison is pending. CSS root rem is 16px.

| Source | Flutter logical pixels / role |
| --- | --- |
| Empty `p-6`, `gap-4`, `w-full`, `rounded-xl` | 24 padding, 16 gap, bounded available width, radius ×1.4 |
| Outline `border border-dashed` | 1px inward stroke and 1px box-model inset, live `border`; 3px dash/3px gap pending renderer comparison |
| Header `max-w-sm`, `gap-2` | maximum 384 width; centered column with 8 gap |
| Media `mb-2` | 8 bottom margin, additional to header gap |
| Icon `size-8`, `rounded-lg`, `bg-muted`, SVG `size-4` | 32 square, radius ×1, live muted/foreground, 16 icon |
| Default media | no background, no fixed size; arbitrary child |
| Title `text-sm font-medium tracking-tight cn-font-heading` | 14/20, weight 500, −0.35 letter spacing, host heading family |
| Description `text-sm/relaxed text-muted-foreground` | 14/22.75, weight 400, live muted foreground |
| Content `max-w-sm w-full gap-2.5 text-sm` | available width up to 384; 10 gap; 14/20 |
| Background `bg-muted/30`, description `max-w-xs` | multiply existing muted alpha by .3; 320 description maximum |
| Avatar and group `size-12`, `-space-x-2`, `ring-2` | public 48px DAvatar, public DAvatarGroup with 8 overlap and existing exterior 2px group ring |
| Search `sm:w-3/4` | native field 75% of content at preview width ≥640, otherwise full width |

DEmpty itself is presentational, without state, controllers, focus stops,
transitions or Form ownership. Title and description offer string and arbitrary
child constructors. Content accepts arbitrary children. Callers use an Expanded
for flex allocation and Center/SingleChildScrollView for a short pane; the generic
column is intrinsic so 200% text can scroll rather than clip. Native paragraph
wrapping replaces browser text-balance/text-pretty. Header semantics are optional
because the source title is a div; the no-sites page preserves its level-1 heading.
Interactive rich children retain native link/focus/semantics ownership rather
than attempting to inspect and restyle arbitrary descendants. No generic
loading/error/selected/input props are exposed. Reduced motion requires no special
handling because Empty has no motion.

Outline and background are idiomatic equivalents of the source className
composition. Button and Input are merged catalogue owners. The example
uses DButton and DInput with Form
validation, Enter submission and local support feedback. Its field is explicitly
labeled native composition, with later Input Group reconciliation required. The
slash keycap is a hint as in the source, not an invented keyboard binding. Local
48px avatar fallbacks replace remote portraits; their fallback states are part of
the reference. The merged Button owner supplies pointer versus 48px touch bounds. Badge, Checkbox and Radio owners are inherited unchanged; Empty has no selection or badge-specific API.
Self-contained displayed source is generated from the actual sample widgets with
`dart run tool/generate_empty_example_source.dart`.

## Application migration audit

All changes affect presentation owners; API requests, permission checks,
controllers, loading branches, callback types and lifetime ownership stay in
callers. Existing initial-error retry keys are retained. No domain dependency
enters `lib/src/ui/components/d_empty.dart`.

- Core: `EmptyState` (add-site sheet and heading); `_AggregateEmptyState`
  (filter/add-site callback); category and tag initial states; draft empty/error/
  signed-out states; activity empty/error/sign-in and pull-to-refresh; topic-feed
  initial error/no-topics and retry; groups directory no matches; shared group
  activity/request/permission states and async callback; users directory state
  and existing progress child; badge catalogue no entries; private-message
  signed-out state with existing connecting/error/button behavior.
- Chat: channel/thread empty messages, browse-channel no matches/errors and
  actions, full search empty/error/retry, thread-list messages and retry.
- Assign: no matching active assignments. Voice: empty room with original cooked
  HTML versus raw description choice; no change to links or permissions.

Retained alternatives after searching all core/plugins/packages:

- Forum search `_PanelMessage`, picker no-results (emoji, tags, categories, GIFs,
  new-DM/users), chat channel-info/search inline rows: compact results/overlay
  feedback, not page states. Turning these into cards would enlarge control popups.
- Topic/category/tag/group/Assign stale-content error banners and pagination
  failures remain inline beside usable data. Loading skeletons/spinners are
  separate owners and remain unchanged.
- User-summary empty subsections, badge awards subsection, inline thread latest
  reply labels, Voice chat “No messages yet”, event-directory period feedback,
  diagnostics timelines/captures and unsupported embedded media remain compact
  within their existing dense surfaces.
- `_ContentPlaceholder` is the existing developer route demonstration, not an
  empty/error/no-results owner. Poll, AI proofreading, reactions, local dates,
  GitHub, lazy-video and Prometheus adapters have no appropriate page-empty owner.
- Business error strings/controllers, transport code and vendored packages are
  unchanged. No new dependency or pending component API is imported.

## Review fixture

`tool/component_fixtures/empty_main.dart` mounts actual production EmptyState,
CategoriesPage (empty/error), TagsPage, DraftListView, UserActivityView, GroupsPage
and ChatThreadListMessage plus the real styleguide. All API/store/authentication
inputs are local fakes, with an in-memory preference backend. The category-error
case is an explicit fixed presentation fixture; real retry mutation is covered
by downstream tests. Chat retry changes the actual public production widget to
its empty state. Light/dark/custom palette, RTL and 200% controls are available.
The fixture smoke test checks these owners mount and Chat retry completes.

This fixture is for native review after unlock. It has not been launched. Other
migrated production owners have downstream widget coverage, not claimed native
inspection. No VoiceOver, iOS/Linux device or pixel-parity claim is made.

## Pinned-main integration

Merged `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` into the Empty branch,
preserving all non-Empty progress rows exactly and the 17 merged components.
Coordinator Group/Sidebar/Topic Inbox changes remain intact. Examples now use
DButton variants/sizes and DInput Form/prefix/suffix APIs; independent action
callbacks and page scrolling remain intact. Input Group is still not imported
or implemented. Native/reference review is still required; no desktop action
is authorized by this integration build.
