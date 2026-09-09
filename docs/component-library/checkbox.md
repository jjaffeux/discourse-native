# Checkbox implementation and verification

Task `01a083ad-91cf-7e91-9083-a861d5c4fa28`, branch `codex/ui-checkbox`.
Dependency Label is merged at `9bbc2806020646451fd1c283d347283fe4e45f67`.
Native comparison remains pending; this is not `review_ready`.

## Reference capture

Read on 2026-09-09. Files are preserved in `reference/` with the upstream
shadcn MIT license and the Base UI MIT license.

| Source | SHA256 |
| --- | --- |
| [Frozen Checkbox Markdown](https://ui.shadcn.com/docs/components/base/checkbox.md) | `7fc35f61a68fa13939af760acf7655d03441b9b44085183e033dcb80bfb25458` (matches catalogue) |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/checkbox.json) | `e6df7b595f25a7ee97c3fb94e0ddc35998f74c98b990d3030e485905ec677178` |
| Registry `checkbox.tsx` UTF-8 content | `0cc30ddee3fa93818799f48ad47a58a30652c956ce940373c3feb3559167f0af` |
| [Field composition registry](https://ui.shadcn.com/r/styles/base-nova/field.json) | `586110f5563cbb5dc0929207ee34361f1349cf2f816465799c60b98821e4cedc` |
| [Base UI CheckboxRoot source](https://raw.githubusercontent.com/mui/base-ui/master/packages/react/src/checkbox/root/CheckboxRoot.tsx) | `4cfe969f4d1b3f046f3024d37fd48f4dc9abe6961877cda54290856e40d76605` |

The [official page](https://ui.shadcn.com/docs/components/base/checkbox) and
[Base UI API](https://base-ui.com/react/components/checkbox) were read. No
rendered browser comparison has occurred: all CUA/browser interaction is
serialized by the coordinator, and the desktop is currently locked.

## Visual mapping

| Reference | Flutter mapping |
| --- | --- |
| `size-4`, border, `rounded-[4px]` | 16×16 logical pixels, 1px token border, fixed 4px radius |
| `size-3.5`, Lucide Check | 14×14 painter, 24-unit viewbox, path (20,6)→(9,17)→(4,12), 2-unit round stroke/caps/joins |
| `border-input`, dark `bg-input/30` | live DTokens.border and its 30% dark fill |
| Checked primary background/border and primary foreground | live primary/primaryForeground |
| Focus-visible ring 3 and ring/50 | 3px outer ring, focusRing at 50%; no hover/pressed fill absent from source |
| Invalid border/ring | destructive border, 3px 20% ring in light; 50% border and 40% ring in dark; checked keeps primary border |
| Disabled opacity 50%, forbidden cursor | whole control composition opacity .5, no activation/focus; no doubled DLabel opacity |
| Read-only Base UI prop | normal appearance and focus, no value changes via pointer/Space/semantics |
| Label gap 2 and text-sm/medium | 8px horizontal gap, DLabel 14px/500; basic leading 1 |
| FieldContent gap .5, leading-snug and description leading-normal | 2px description gap; 1.375 title leading and 1.5 description leading; description controls align at top +1px |
| transition-colors / transition-none indicator | 150ms color container, instantaneous artwork; zero duration with disableAnimations |
| `after:-inset-x-3`, `after:-inset-y-2` | 40×32 pointer target, 48×48 touch target; transparent area around fixed 16px artwork |

The target reserves actual native layout space so hit/semantic bounds stay
inside the parent (Flutter does not hit-test overflowing children outside
parent bounds). Consequently tightly stacked pointer rows can be taller than
CSS's overlapping pseudo-element targets. Labels wrap and scale naturally;
RTL uses directional layout, padding and start alignment. Host fonts and
semantic palettes remain live; the checkbox's explicit 4px source radius does
not follow a theme's unrelated general radius.

Mixed state is a native API extension represented by nullable bool when
`tristate` is enabled. Activation changes mixed to true, then toggles boolean
states; it never cycles through mixed. Base UI uses a separate indeterminate
prop and boolean change callback. The registry hardcodes CheckIcon; this port
currently gives mixed a 14px Lucide Minus path (5,12)→(19,12) so partial selection
has distinct artwork. This extension is explicitly pending coordinator visual
review, not claimed as an upstream Minus specimen.

## API and composition

`DCheckbox(value:, onChanged:)` is controlled; null callback disables it.
`DCheckbox.defaultValue(defaultValue:, onChanged:)` owns initial state and permits
an optional observer. Both support title/subtitle, optional separate secondary
content, semanticLabel, tristate, enabled, invalid, readOnly, borrowed focusNode,
autofocus and directional contentPadding. Labels share one gesture/semantic
owner and tab stop; independently interactive secondary actions stay outside.
Pointer activation takes focus before changing state, so subsequent Space acts
on the clicked control. Only internally created focus nodes are disposed.

`DCheckboxFormField` uses the native FormField owner with initialValue,
validator, onSaved, onChanged, autovalidation, reset and error announcements.
`.controlled(value:, onChanged:)` synchronizes external values without marking
them as user interaction. Reset restores initialValue and notifies the caller.
Errors use an announced description and invalid semantics rather than color
alone. Required consent is expressed through the validator, as in the example.

Six local interactive styleguide specimens cover basic/description, all states,
device groups, actual table selection with a mixed header, form error recovery,
and long Arabic/Hebrew/English labels. The existing Sidebar shell is untouched.
Its shared preview settings exercise narrow/200%/RTL/reduced-motion and live
Light/Dark/Forest/Plum themes. Label examples use the new checkbox too.

## Adoption audit

All `Checkbox`, `CheckboxListTile`, `check_box` and appropriate manual selection
uses were searched under core and every bundled plugin.

- Core: UserStatusEditor notification pause; InviteEditor email consent;
  PostFlagEditor legal confirmation; TopicMovePosts chronological order;
  UsersPage column visibility and ordering; Composer existing-image gallery;
  GroupMembersView user/email multi-selection; TopicView post selection;
  AggregateView included-forum selection.
- Plugins: Local Dates time inclusion; Events all-day/dynamic boolean fields;
  VoiceMeshPrivacyDialog preference; ChatMessageTile selected messages; PollCard
  multiple-choice options, retaining expiration/permission/busy guards and
  results. Poll action-button regions are untouched for the Button task.
- Bare post/message/forum controls now have explicit semantic names. Keyboard
  navigation and Chat drawer shortcut guards recognize DCheckbox. Column
  reorder buttons remain separate focusable actions via secondary composition.
- No old generic project checkbox renderer remains. Native Checkbox type guards
  remain to protect third-party/plugin controls that own their keyboard input.
- Retained alternatives: single-choice Poll radio rows belong to Radio Group;
  Switch/Radio/segmented controls, menu checkmarks, status icons and reactions
  have distinct semantics and belong to their respective catalogue tasks.
  Rich Poll content remains application-owned; its multi-choice label has one
  plain semantic name and row activation, not nested link focus targets.

## Automated and native evidence

- Root `flutter analyze --no-pub` and full-profile `flutter analyze --no-pub`
  passed. Root/full-profile `flutter pub get --enforce-lockfile` passed without
  lockfile changes. Formatting and `git diff --check` passed.
- 392 focused tests passed with seed 734129 across component, Label examples,
  Checkbox examples, User Status, Users, Composer uploads, Aggregate, Chat
  lifecycle, legal confirmations and ownership, Topic Move, Groups, Events,
  Local Dates, Poll, keyboard navigation, Invites and Voice room views. That
  run included two minimal stale Avatar test-cast corrections. Those two
  Avatar-only corrections were subsequently reverted because the coordinator
  owns them; base Users tests still cast DAvatar to ClipRRect. Checkbox-related
  migration tests passed; no other migration failures were found.
- Final Checkbox/Label checks passed all 34 tests with seed 927315, including read-only, pointer focus, mixed activation and caller-declined controlled-form changes. The bordered notification composition then passed all seven Checkbox example tests.
  Logs: `/tmp/checkbox-final-tests.log`, `/tmp/checkbox-readonly-tests.log`,
  `/tmp/checkbox-analysis.log`, `/tmp/checkbox-full-analysis.log`.
- `tool/component_fixtures/checkbox.dart` mounts real PostFlagEditor and
  VoiceMeshPrivacyDialog plus the actual shared styleguide. All data is local.
  The legal fixture simulates busy state, retained failure and successful retry;
  privacy choices never join a room or persist preferences.
- The first native build found a missing ephemeral generated Swift package.
  `flutter build macos --debug --no-pub --config-only -t
  tool/component_fixtures/checkbox.dart` generated it, then the debug build
  succeeded. Final clean-source rebuild from `0df1b03ca000166c1901825b001dbad750b04ce6` passed. Unique copied bundle: `/private/tmp/DiscourseCheckbox132a-0df1b03c.app`, identifier `org.discourse.native.checkbox.132a`, URL scheme `discourse-checkbox-132a`. Source and copied kernels match SHA256 `50658162f62e4a78954bfc3470df11c70cf72e04f308efa777562b3646d9894b`; deep strict ad-hoc signature verification passes. See `checkbox-native-provenance.json`. No app was launched.
- Native reference comparison, pointer/keyboard interactions, representative
  theme checks and real production fixtures remain uninspected pending the
  coordinator's desktop slot. No iOS/Linux device or VoiceOver claim is made.

Additional Topic Inbox verification passed 98 tests and failed compact-title Escape restoration. The exact failure reproduced on pristine base `2e894b5e` in a temporary detached worktree, which was removed afterward. Logs: `/tmp/checkbox-baseline-topic.log` and `/tmp/checkbox-topic-retry.log`. This base failure is assigned to the coordinator.
