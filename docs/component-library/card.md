# Card reference and adoption

The frozen Card Markdown has SHA256
`718dec761e0ad426b53d4673d206ab6dbfbbff5757f9714b883a04126f75db3e`.
Scope remains Installation, Usage, Composition, Size, Spacing, Image, RTL,
all seven APIs and the shared-spacing changelog. Installation is the public
`package:discourse_native/discourse_ui.dart` import.

Registry inspected: https://ui.shadcn.com/r/styles/base-nova/card.json

- Raw JSON SHA256: `e73e3fe00ab2e14c4db1dccb1ff5c67041a94c0926ac3216c1dc6dd6dee9d7e0`.
- Decoded `card.tsx` UTF-8 SHA256: `645c3d73e387a99f1492220cc619453b0c7f5454134ee3cd548be7a80f7eccde`.

Official theme CSS (`/_next/static/immutable/chunks/17udeju1vgrir.css`)
SHA256 `19dd8fe80f1fb07e156ed3ceaaaacb7a600a3444e97c3baf6483c4363a15668d`
confirms `--radius-xl: calc(var(--radius) * 1.4)`, consistent with the existing
Skeleton mapping.

At a 16px root and 100% native text scale, CSS pixels map to logical pixels:

| Reference | Flutter |
| --- | --- |
| `bg-card`, `text-card-foreground` | live `DTokens.surface`, `foreground` |
| `rounded-xl` | configured large radius × 1.4 |
| `ring-1 ring-foreground/10` | outside 1px spread, no blur/offset, foreground at 10%; no Material elevation/tint |
| `--card-spacing: --spacing(4)` / small `--spacing(3)` | 16px normal / 12px small; finite nonnegative `spacing` overrides both |
| root gap and vertical padding | shared spacing; leading image removes top inset, footer/trailing removes bottom inset |
| `text-sm` | 14px / 20px, weight 400, zero tracking; host font family |
| header `gap-1`, `px-(--card-spacing)` | 4px text/action gap, shared logical horizontal inset |
| header `1fr auto`, action row-span 2 | title/description column gets remaining width; intrinsically sized action at top logical end, capped at half width |
| title `text-base leading-snug font-medium` | 16px / 22px, weight 500; small 14px / 19.25px |
| description `text-sm text-muted-foreground` | 14px / 20px with live muted foreground |
| header `.border-b` + shared bottom padding | `border: true`, 1px semantic border and spacing inset |
| content horizontal spacing | `DCardContent`; `edgeToEdge` cancels the inset |
| content negative bottom shared margin | `joinNext` removes the following root gap |
| footer border-t, muted/50, shared padding | 1px semantic top border, 50% muted fill, spacing on four sides |
| image first/last edge rounding, overflow hidden | explicit `leading` / `trailing` slots and surface anti-alias clipping |

A direct `DCardFooter` in `children` also removes root bottom padding. The
explicit `footer` slot works without searching through arbitrary Flutter wrapper
widgets. A wrapped footer should use that slot or explicit full-surface `child`
composition. `child` plus `spacing: 0` supports an existing full-surface InkWell
and caller-owned padding. The zero-elevation Material provides ink; a semantic
container preserves the grouping previously supplied by Material Card. The
surface creates no callback, tab stop, disabled policy, selection policy,
controller, animation or network request.

Native adaptation: below 240px inner header width or above 150% text scale,
action moves below text. The Flex changes direction without replacing action
or text elements, preserving native focus and state. The cap prevents oversized
actions from consuming the complete text column. Footer callers use ordinary
Wrap/Row/Column; they own wrapping and button lifecycle. Selected, disabled,
error, empty and busy examples use explicit text/semantics and child control
state, rather than inventing Card variants.

The login, small report, adjustable spacing, terms, image and Arabic examples
precede application states. They use local callbacks and input controllers.
The final compositions use accepted `DButton` primary, outline and link
treatments; `DInput` email/password editors; associated `DField`,
`DFieldLabel` and `DFieldControl` metadata; a secondary `DBadge`; and a
controlled outline `DToggleGroup` for the four spacing values. Flutter owns
form submission through the local callback rather than an HTML button `type`.
Validation, drafts, editing selection, focus and spacing selection remain
local and survive theme, direction, text-scale and width reflow. The image uses
the already bundled package asset, grayscale and reference 60%/40% brightness
plus its 35% black overlay, without runtime network fallback.

## Presentation audit

Audited Material Card, named card classes, decorated surfaces and rounded
Material owners across core and all bundled plugins. Migrated:

- Groups directory, compact members, activity posts and membership requests:
  DCard owns surface; original InkWell, permission actions, search/paging,
  request state and semantic labels remain app-owned.
- Chat browse-channel cards: keep follow/join busy guard, local request ownership,
  route service and InkWell. Chat preferences share the Card surface with core
  preferences while preserving FormField and save/reset ownership.
- Poll interactive and cooked fallback cards: retain vertical layout margins,
  vote draft and async guards, read-only fallback, semantic title updates.
- Events loaded, unavailable and cooked fallback cards: retain hydration,
  permission, RSVP, export/navigation callbacks and error/loading handling.
- Core Preferences, Badge directory and Category directory: replace competing
  rounded Material surfaces, preserving forms, ink, artwork, category accent
  strip and directory layout constraints.
- Aggregate panels: remove `_AggregateCard`'s independent purple shadow/radius
  styling and use the shared surface; topic/feed ownership remains unchanged.
- Voice diagnostics control panel: shared surface around existing native
  capture switch and local export/copy callbacks.
- Skeleton reference Card: remove temporary surface styling and use DCard;
  loading/ready state owners remain unchanged.

Retained alternatives and concrete ownership reasons:

- Core user-card popup, menus, emoji picker, selection toolbar and sheets:
  route/overlay geometry, elevation, dismissal and focus restoration belong to
  Hover Card/Popover/Menu/Sheet owners, not passive Card.
- Topic sidebar `_TopicSidebarCard`: a divider-only stacked metadata section,
  not a bordered surface. Topic/inbox/list rows, group tables/tab bars and
  directory error notices retain their list/table/tab/alert ownership.
- Core onebox embeds retain external-link merging, engine-specific nested links
  and markup/media composition. Compact Tag directory rows and User Summary
  statistic/badge items retain Item/metric presentation; summary excerpts and
  category rows use partial borders, and failures use Alert roles.
- Core image grids, inline video, category/badge art, flair, chips and avatars:
  media cropping or identity/status artwork, not Card shells.
- Chat latest-reply/thread-summary previews: message-stream selection/focus,
  unread emphasis and linked preview contract belong to Chat message components.
  Channel-info sections are divider groups; drawers, search chrome, composer,
  upload thumbnails, pinned bar and header badges retain their own roles.
- Assign member panel: bounded navigation/filter pane with independent scrolling
  and selected member rows, not a passive content card.
- Voice ringing/video participant tiles: media and live speaking/mute/ringing
  status surfaces; preserve video clipping and explicit speaking border.
  Diagnostics log/metric cells remain table/status presentation.
- Events calendar cells/event chips/composer and Local Dates sheet preview:
  calendar positioning, color meaning, field/overlay layout remain their owners.
- Poll option/results/ranking decorations are voting controls and charts.
- GitHub onebox labels, Prometheus tables/status chips, GIF picker media and
  reaction picker controls retain markup/media/table/selection semantics.
- AI and lazy-video modules have no separate passive Card surface. Domain
  Chat/Voice UserCard data and plugin post-card adapters remain domain owners.

## Verification

Recorded seeded tests, native comparison evidence and platform limitations are
in the Card progress row. Native fixtures are temporary build artifacts and
use local fake data, not connected accounts. No runner files, Flutter pin,
lockfiles or shared workflow metadata are changed.

Executed focused commands (ordering seed `834729`):

```sh
flutter test --no-pub test/ui/d_card_test.dart test/styleguide/card_examples_test.dart test/styleguide/skeleton_examples_test.dart test/groups_page_test.dart test/group_page_test.dart test/chat_browse_channels_view_test.dart test/poll_card_test.dart test/event_card_test.dart test/event_card_lifecycle_test.dart test/preferences_page_test.dart test/badges_page_test.dart test/categories_page_test.dart --test-randomize-ordering-seed=834729
flutter test --no-pub test/ui/d_card_test.dart test/styleguide/card_examples_test.dart test/voice_diagnostics_view_test.dart test/aggregate_view_test.dart test/preferences_page_test.dart test/d_button_adoption_test.dart --test-randomize-ordering-seed=834729
flutter test --no-pub test/ui/d_card_test.dart test/styleguide/card_examples_test.dart --test-randomize-ordering-seed=834729
```

These passed 181, 48 and 12 tests respectively (overlapping suites, not a sum
of unique tests). The last run includes the added header lifecycle regression.
`dart format --output=none --set-exit-if-changed` passed for all 19 touched Dart
files. Root and `profiles/full` each passed `flutter pub get --enforce-lockfile`
and `flutter analyze --no-pub`. `git diff --check` passed.

### Native inspection

The exclusive macOS pass compared official rendered light/dark Card examples and
computed metrics against all eight local examples. Light, dark and Plum palettes,
RTL, 320px layout and 200% text were inspected. Login submission, retained spacing
drafts, terms scrolling/acceptance, image details and application states worked.
The actual bundled styleguide Card page and snippets were inspected as well.

Real local-data Groups, Members, Activity, Poll, Events, Chat and Badge fixtures
were inspected, exercising navigation, retries, voting, RSVP and join/unfollow.
Preferences, Categories, Aggregate, Voice diagnostics and cooked/request fallbacks
received focused tests but were not individually inspected natively. No VoiceOver
audit or iOS/Linux device inspection was performed. Some AX snapshots were sparse;
widget tests provide the keyboard activation and focus-retention evidence.

Screenshots and AX observations are inline in task
`01a082d9-6c59-7443-8e64-f76105fd5e56`, not saved PNG files. Ignored temporary
`build/card-review/native-manifest.json` and `byte-match.json` identify the build.
The isolated `/tmp/DiscourseCard5995.app` was ad-hoc signed and its App.framework
payload verified against the build. The inspected build preceded only the final
styleguide status promotion from baseline to implemented.
