# Collapsible implementation and review handoff

Source task: `01a08445-7647-7a83-a366-e06252405043`.
Branch: `codex/ui-collapsible`. Status: **in_progress / awaiting_slot**.

## Reference provenance and measured mapping

The fetched official Markdown exactly matches frozen SHA256
`51c94ec0874f01cd67a62616d74dabb98334f8a31c1db74207f7c86a2402ea6a`.
It contains the actual demo, Basic, Settings, File Tree and RTL source. Individual
example registry URLs returned 404; no substitute preset was used. See
[sources.json](sources.json) for official URLs and SHA256 of every retained
source, including base-nova Collapsible/Button, Base UI root/trigger/panel and
Lucide artwork. Retrieved sources are supporting evidence; the frozen catalogue
was not changed. Live source reads are not rendered browser comparison.

All measurements below are CSS-derived, with 16px/rem and 1 CSS pixel = 1 Flutter
logical pixel at 100% scale. Native and browser measurement remains pending.

| Reference | Flutter mapping |
| --- | --- |
| Root/trigger/content wrappers have no classes | Scope, passive visual trigger builder, content; no root padding, fill, border, radius or motion |
| Base UI open/defaultOpen/onOpenChange/disabled | Nullable controlled `open`, default local state, value callback and disabled activation |
| Base UI trigger button/aria-expanded/focusableWhenDisabled | Enter/Space and pointer button with expanded/enabled semantics; disabled remains focusable; native exterior 2px focus outline |
| Panel keepMounted=false, hidden/inert closed | Default unmount; explicit retained subtree uses Offstage, ExcludeSemantics/Focus, IgnorePointer and TickerMode |
| No base-nova transition classes | Default zero duration; explicit clipped-height duration/curve; reverse mid-transition; reduced motion snaps |
| Order w350, gap2, header px4/gap4, size8 icon | Max 350; 8px gaps only around mounted content; header 16px inset/gap; 32px icon visual |
| Order text-sm/semibold, medium values, muted supporting text | Host font family, 14/20px leading, 600 heading, 500 values, live semantic foreground/muted |
| Detail rounded-md border px4 py2 | Radius host×0.8, border 1px, inset 16×8px, intrinsic wrapping text |
| Basic Card max-w-sm, content p2.5 pt0 gap2 | Actual DCard max384, 10px body sides/bottom, 0 top, 8px content gap, open muted root |
| Settings Card small/max-w-xs, 2-column grid gap2, icon size8 | Actual small DCard max320; flexible two-column fields, 8px gap, 32px action |
| File tree max-w-sm, folder h7, text0.8rem, icon3.5, gap1, ml5 mt1 | Max384, 28px minimum rows, 12.8/20px text, 14px folder/chevron artwork, 4px gap; directional 20px nesting/4px top |
| Default/ghost button h8/rounded-lg and sm rounded min(md,12) | Example passive trigger skins: 32px default, host radius; 28px small, min(host×0.8,12). No Button props on public Collapsible |
| SVG size4/stroke2/round cap/join | Official Lucide SVG strings rendered with flutter_svg at 16px (14px small); RTL right chevron mirrored |
| Ghost open/hover muted, dark hover muted/50; outline border vs dark input | Live token roles; alpha multiplication; border and input remain distinct; state supplied through trigger builder |

## Public composition and native adaptations

`DCollapsible` is an inherited scope, not a forced Column. Trigger/content can be
placed in Rows, Cards, nested folders, or any ordinary layout. The nearest scope
owns each part. Triggers render passive child/builder content; nested buttons
are explicitly unsupported because they would create competing interaction
owners. Builder exposes open, disabled, hovered, pressed and visible-focus state.
The trigger borrows caller focus nodes without disposing them. Root records
registered triggers and restores focused content to the last activated trigger
(or another mounted trigger) before collapse. External controlled changes do not
emit interaction callbacks. Dropping control retains the last controlled value.

A disclosure is not a field. Child Form fields retain their own save, reset,
validation and controllers. `keepMounted: true` retains fields even before first
open and keeps them registered in Form while hidden; callers choose whether
hidden fields should validate. Browser `hiddenUntilFound`, CSS attributes,
DOM ref/render props and browser find-in-page do not map to fake native flags:
app search reveals results through controlled open. Flutter child composition,
focus nodes and semantics replace DOM wiring. No menu/Accordion keyboard model
or exclusive sibling selection is introduced.

Examples have native touch bounds of 48px and intrinsic growth for large text;
desktop visual rows remain compact. Plain trigger defaults have no forced target
size because their associated composition owns bounds. A 2px exterior rectangular
outline is the native fallback on the unstyled trigger; it never paints behind
translucent content. Source button-specific focus skin remains a Button review
reconciliation item, not a claim that the baseline Button owner is complete.

## Examples and pending adjacent owners

Six actual-component groups: controlled order, Basic, Settings Panel, full nested
File Tree, Arabic RTL order, and lifecycle/disabled/Form/optional-animation lab.
All state and actions are local. Learn More and file selection show feedback.
Explorer/Outline use existing StyleguideAction while Tabs is pending; the Outline
pane gives explicit empty feedback. Settings uses TextFormField editing and
visible labels while Input/Field are pending. Basic Learn More and file actions
use baseline DButton; their exact xs/link Button visuals remain dependency
reconciliation, clearly stated in styleguide notes. These examples do not import
or implement pending public owners. Retained nested folder state is intentional.

## Adoption audit

- Events `EventComposerSheet`: More options replaces ExpansionTile. Existing
  text controllers, custom fields, booleans, stale-editor guard, Apply/Remove,
  markdown serialization and date-picker ownership remain in the plugin.
  Retained content preserves active editing/selection and validation rather
  than disposing/recreating editor elements on collapse.
- Local Dates `LocalDateComposerSheet`: Display options replaces ExpansionTile.
  Recurrence, format, calendar, timezone menu values, preview timezone chips,
  draft Apply, source-is-current guard and asynchronous picker lifecycle remain
  app-owned. Retained subtree avoids dropping active local menu/editor state.
- Prometheus `AlertTables`: independent status/datacenter group disclosures use
  controlled Collapsible, retaining group default/user override across data
  refresh. Body remains lazy/unmounted while closed (important for large groups).
  Existing horizontal ScrollController/PageStorage offset, table layout,
  selection, links, quote callbacks and permissions stay with the adapter.
  Existing compact app row sizing remains distinct from reference examples.

Retained alternatives after searching core and all bundled plugins:

- `instance_sidebar.dart`: section persistence and destination rows are lazy
  slivers in SliverMainAxisGroup. A box panel would eagerly lay out destinations
  or change scroll ownership. Sidebar's offcanvas/icon mode is its own component.
- `composer_reply_context.dart`: bounded split header/Expanded excerpt uses
  available vertical space to determine whether expansion is possible. Its
  existing conditional Flexible/scroll pane cannot be replaced with a box height
  panel without changing the composer's resize contract.
- Topic inbound links and Chat deleted-message reveal are one-way show-more
  operations with domain-owned selection/reveal state, not toggled panels.
- AI summary and inbox AnimatedSize are loading/response or responsive layout
  transitions, not disclosure controls. Markdown collapsed syntax/images/quotes
  are editor projections with cursor/source replacement contracts.
- Sidebar styleguide project submenu is an adjacent reconciliation candidate;
  coordinator can migrate it with the completed Sidebar owner. No competing
  source owner was added in that task's example file.

## Checks and native gate

Focused suites cover root/trigger/content state, semantics, keyboard, focus,
retained/lazy editors, transition reversal, reduced motion, RTL/large text/live
theme, Form reset/validation, actual example interactions, both editor Apply
outputs, stale permissions and picker completion after disposal. Prometheus
suites cover quote permissions/actions, group refresh, compact geometry, lazy
large groups and horizontal scrolling across collapse. Styleguide page tests
cover the affected shared registration surface.

Use the exact command/results recorded in progress.json and native-build.json.
Flutter remains 3.47.2; root/full enforced resolution and analysis required, no
pins/lockfiles updated. Full suite is explicitly not required by the user.

`tool/collapsible_review_main.dart` mounts actual production Events, Local Dates
and AlertTables with fixed local data, plus full styleguide access. It includes a
stale-event editor to exercise the existing error state. No fixture performs
account requests. The unique local macOS bundle is built in this worktree,
never `/Users/joffreyjaffeux/Code/discourse-native/build`. Runner edits used for
identity are temporary and restored. Source commit, source equality, embedded
kernel SHA256 and deep strict signature outcome are recorded after building.

**No native app/browser was launched or inspected.** The Mac was locked and no
desktop slot was granted. Browser comparison and native styleguide/production
fixture inspection, including representative themes and viewport states, are
required before changing status to review_ready. Tests do not prove native
VoiceOver, device behavior, pixel parity or typography/font rasterization parity.

## Isolated build result — 2026-09-09

Source checkpoint `e05de6002a37f1dfbc7483a29f921086dffb0d3d` built successfully.
The exact bundle path, unique identifier/scheme, copied kernel locations and
SHA256, source equality command and strict signature evidence are in
[native-build.json](native-build.json). Signing is local ad-hoc. The normal
provisioned identity could not sign the new review ID, so temporary runner
settings used ad-hoc signing and omitted the APS development entitlement only
for this local fixture. All four runner files were restored byte-for-byte; the
real app build, push configuration and account provisioning were untouched.
No app launch occurred. Native review remains awaiting_slot.

## Pinned-main integration refresh

Merged e612ad7b47413fa890b35ae3b55a6f6d37b08cf7, preserving every other
component progress row and the merged Group/Sidebar/Topic Inbox fixes. Events
retains current DCheckbox/DInput and Local Dates retains DInput. Examples now
use DInput for radius/draft fields and DButton for actions, including extra-small
Learn More. Field/Tabs remain explicit pending owners. CollapsibleTrigger stays
the sole disclosure interaction owner; its child is passive visual content.
Prior notes describing baseline Button/Input are historical and superseded.
Browser and native inspection are prohibited in this locked/admin-policy-denied
session; no attempt or workaround was performed.
