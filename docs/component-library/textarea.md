# Textarea implementation and review checkpoint

Branch `codex/ui-textarea`, base `adcb5a9fcc0468aa60f4e95a7c8919f55c1df2d0`.
Task `01a08437-208f-7332-b373-192eaada5844`. Status remains **in_progress**:
source/checks are complete, reference/browser and native review await a slot.

## Primary reference

Frozen 2026-09-08 Base UI catalogue, retrieved 2026-09-09 without UI/browser use.
Exact responses are in `reference/textarea/`:

| Source | SHA256 |
| --- | --- |
| [Frozen docs and all six examples](https://ui.shadcn.com/docs/components/base/textarea.md) | `7f2112811eec73ffe6ddc4f250ab4daad7a9894bd274817dda6e26dec0a03759` |
| [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/textarea.json) | `8f01f6bc4ee556263bae7644e8b527022fa77ff203f33a258bb47142ef7d9c81` |
| [Official example source](https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/textarea-example.tsx) | `3199a0816889450768a891d9c3c97ca7618d7d03eca0867cf359bb2d3c9b30d9` |
| [Field composition supporting source](https://ui.shadcn.com/r/styles/base-nova/field.json) | `586110f5563cbb5dc0929207ee34361f1349cf2f816465799c60b98821e4cedc` |

The frozen Markdown hash matches; no catalogue resnapshot. Label is merged.
Field and Button are pending: examples use DLabel, native Form/Column/Text,
and the already available StyleguideAction. No unmerged dependency or pending
public API was introduced. Input in worktree `faaa` was read for consistency;
Textarea has no import/dependency on that worktree or DInput.

## CSS to Flutter mapping

CSS pixels are logical pixels at 16px/rem, 100% text scale.

| Registry | Actual mapping |
| --- | --- |
| `min-h-16 w-full field-sizing-content` | 64px border-box minimum, stretch to finite parent width, `TextField(maxLines: null)` grows with content. Five 20px lines produce 118px total. Native `minLines`/`maxLines` reserve/bound lines; three bounded desktop lines produce 78px and scroll. |
| `px-2.5 py-2 border` | 10px horizontal, 8px vertical, plus 1px border: text inset 11px x 9px. No Material internal padding/fill/outline. |
| `rounded-lg` | `DTokens.radius × 1.0`, including live custom radii. |
| `text-base md:text-sm` | Touch-platform 16px/24px and desktop 14px/20px, weight 400, tracking 0. Host font family and inherited scaler. Platform choice follows reviewed Input policy rather than changing typography when an app side pane narrows. |
| `border-input` | `colors.outlineVariant`, independent of `DTokens.border`. |
| transparent; dark `bg-input/30` | Transparent light fill; input alpha multiplied by .3 in dark. |
| disabled `bg-input/50`, dark `/80`, opacity .5 | Input alpha multiplied by .5/.8 respectively, then one .5 surface/text/ring opacity layer; no pointer editing/focus, forbidden cursor. |
| placeholder muted foreground | Same explicit text metrics, live muted foreground; no Material hint animation/label floating. |
| focus border-ring, ring-3 ring-ring/50 | Live focus border, 3px exterior-only annulus at ring alpha × .5. No spread shadow tint behind transparent content. |
| invalid destructive border/ring | Border destructive (dark alpha × .5); always-visible exterior 3px ring alpha × .2 light / .4 dark, plus invalid semantics and caller-visible explanation. |
| `transition-colors` | 150ms interpolated decoration colors, zero duration with inherited reduced motion. No size animation. |
| Field label and description | DLabel style uses 14px/19.25px, medium; invalid label destructive. Description/error uses 14px/21px and 8px composition spacing. Field's intricate sibling CSS margins are not a new generic Field implementation. |

No artwork/icons are present in the reference. There is no stock Material
outline, ripple or shadow. The native browser resize grip is omitted: automatic
content growth and explicit line bounds respect native parent layout constraints.
The 64px field already exceeds the 48px native touch minimum. Native selection,
clipboard/context menus, undo, shortcuts, IME and scrolling remain Flutter-owned.

## Editing API and lifecycle

One reusable owner: `lib/src/ui/components/d_textarea.dart`, exported by
`discourse_ui.dart`. A FormField wraps the native TextField. Controller, value,
and initialValue modes are exclusive. Same-string parent updates preserve the
entire editing value. Changed strings collapse selection at the end and end
composition. Reset restores the text captured on mount and emits onChanged.
Switching to an external controller takes its text; switching to local ownership
copies the previous complete editing value. Borrowed focus, editing, undo and
scroll controllers are never disposed. Selection-only and IME-only notifications
do not write into the controller. `onChanged` retains native user-change semantics;
programmatic changes still update Form state and the optional grapheme counter.
Validation/save/autovalidation/reset, formatter/length enforcement, keyboard
configuration, read-only selection, context menus and external callbacks are
forwarded. Required semantics does not invent a validation rule.

Native extensions justified by existing consumers: static label/helper/error,
reserved/bounded lines, borrowed editing/focus/scroll/undo owners, length limits
and optional grapheme counter (Chat channel description), text capitalization,
formatters and caller-owned submit/editing callbacks. Domain writes stay outside
this component.

## Adoption audit

Current core and all bundled-plugin Dart sources were searched for TextField,
TextFormField, EditableText, CupertinoTextField, multiline keyboard, minLines,
and maxLines. Ordinary multiline fields migrated:

- Core InviteEditor custom message and group invitation message.
- Group membership-request reason, management request template, and profile bio.
- Post flag message, staff notice, and selected-text fast edit.
- Assign optional note.
- Chat channel description (280-character limit/counter retained).
- Events Markdown description.
- Voice room description, moderator flag message, and simple room chat message.

These 14 call sites retain controllers, keys, focus, line bounds, max length,
capitalization, onChanged, save/disabled guards, permission checks, request target
ownership, async completion handling and persistence callbacks. Group schema
helpers choose DTextarea only for multiline rows; single-line fields remain
with their adjacent owner. Core/plugin imports use the public barrel. Existing
migration tests were updated to target DTextarea instead of casting its key to
TextField or testing a Material OutlineInputBorder.

Retained alternatives:

- `shell/composer_panel.dart`: rich `MarkdownEditingController`, selection
  projection, atomic pills/images/quotes, custom context menus, cursor hiding,
  composer focus/scroll and lifecycle generation, syntax formatters, expanding
  layout, desktop submit shortcuts. This is the shared post/chat composer
  editing owner, not an ordinary boxed textarea. Replacing it with a generic
  field would violate lossless Markdown and native editing contracts.
- `shell/composer_surface/composer_surface.dart`: hybrid projected composer
  surface and its plain-text fallback; maintains coordinate/selection adapters,
  hidden markers and IME under the composer migration gates.
- `styleguide/examples/spinner_examples.dart`: borderless multiline text within
  the pending Input Group's shared outer border and addon/footer. Wrapping it in
  a boxed DTextarea would create two field surfaces; Input Group must own that
  composition. Its note remains explicitly temporary.
- All remaining directory/search/title/member-picker and group schema
  single-line controls belong to Input/Field/Combobox owners, not Textarea.

Coordinator must reconcile shared export/registration/progress files and
adjacent Input migrations in InviteEditor, Events, Chat and Voice metadata.

## Verification and native review

Root/full-profile enforced-lockfile resolution passed, without SDK/pin/lockfile
changes. Root/full-profile analysis is clean. The main focused run passed **215
tests** (seed 928374611): component state/geometry/semantics, all seven examples
at 216px/200% RTL in Light/Dark/Forest/Plum, Assign, Events, Groups, Invites,
post flag/notice ownership, fast edit, Chat channel info and Voice room behavior.
The user-authorized focused policy replaces the blanket full-suite gate.
No compatibility bridge/package implementation changed.

Logs: `/tmp/textarea-final-focused.log`, `/tmp/textarea-analysis.log`,
`/tmp/textarea-full-analysis.log`, `/tmp/textarea-visual.log`.

Eight 344×88px Flutter software-renderer exports are under `evidence/textarea/`,
using real macOS Arial loaded as TextareaReference, 320×64px field, 12px canvas
inset, 1× raster scale. Test theme has radius 10 and deliberately separate border
and input roles; dark input alpha .149. Pixel checks prove alpha multiplication,
unchanged interior focus/invalid pixels, and exact exterior ring extent. Export:
`TEXTAREA_EXPORT=docs/component-library/evidence/textarea flutter test --no-pub test/d_textarea_visual_test.dart`.
These exports are source/renderer evidence, not browser or device parity.

`tool/textarea_review_main.dart` mounts actual production InviteEditor and
EventComposerSheet with local data, plus the actual seven Textarea examples and
full styleguide. Invite writes can succeed, fail, or wait for the fixture's
finish button, entirely in memory; an email and send-email selection reveal its
message field. Events edits operate on a local parsed event block. No account,
network, real application state or platform service is required.

Native bundle/source/signature evidence is recorded below after the build.
Native app has not been launched. Reference-rendered comparison and native
styleguide/production fixture inspection remain required after unlock. No iOS,
Linux device or spoken VoiceOver verification is claimed.


### Exact-source native bundle — 2026-09-09

- Build command: `flutter build macos --debug --no-pub -t tool/textarea_review_main.dart`.
- Committed implementation source: `118fa0f10a4d838f50117c0aa0b0b7edc2cfd44b`.
  Tracked working tree was clean at build and copy. Later evidence/progress-only
  commits do not alter `lib/`, `tool/`, `test/`, platform files or dependency pins.
- Source app: this isolated checkout's `build/macos/Build/Products/Debug/Discourse.app`.
  The user's `/Users/joffreyjaffeux/Code/discourse-native/build` was not used.
- Review copy: `/private/tmp/DiscourseTextareaReview-01a08437.app`.
  Bundle identifier `org.discourse.native.textarea.01a08437`, bundle name
  `DiscourseTextareaReview-01a08437`, URL scheme
  `discourse-textarea-review-01a08437`.
- Source and copied `App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin`
  SHA256 both `add8ac7965e911c3e129d7ed80b33913983d13f7e161f9257a83232effc23650`.
- Copied Info.plist changes only identity/scheme; ad-hoc signing preserves native
  entitlements. `codesign --verify --deep --strict --verbose=2` passed.
- Logs: `/tmp/textarea-native-build.log`, `/tmp/textarea-codesign.log`.
- Final pointer refinement: 12 component/visual/example tests passed afterward;
  root/full-profile analysis remained clean. `/tmp/textarea-final-component.log`.
- Bundle is **unlaunched**. No CUA, browser tab, application focus or account
  interaction was used. Awaiting coordinator slot; this is not review_ready.


### Accessibility boundary correction

Source correction `c2d7026f` adds `container: true` to the native editor Semantics.
The unadorned-field regression failed before the correction: editable semantics
covered 320×64 rather than the 298×46 native TextField. The corrected test checks
exact editor bounds and excludes the surrounding heading and any button beneath
an editable ancestor. Separate Column/Row cases check each label/value, required
and invalid metadata, independent heading/actions, and visible error semantics.
The error remains its own announced live region instead of merging into the
editor. Label activation still passes. Repro: `/tmp/textarea-ax-repro.log`.

60 focused component/example/visual and migrated form tests passed. Final
analyzer API cleanup passes all 12 component tests. Root and full-profile
analysis are clean (`/tmp/textarea-ax-tests.log`, `/tmp/textarea-ax-final-test.log`,
`/tmp/textarea-ax-analysis.log`, `/tmp/textarea-ax-full.log`).

Native fixture rebuilt from correction source `c2d7026f`; later changes only
modernize test assertions and record evidence. Production `lib/`, `tool/`, native
and lockfile sources remain equal to that commit. New unlaunched bundle:
`/private/tmp/DiscourseTextareaReview-01a08437-AX.app`, identifier
`org.discourse.native.textarea.01a08437.ax`, scheme
`discourse-textarea-review-01a08437-ax`. Source and copied kernel SHA256 both
`be9603f36ffc05f2b2a1f7473cf99eec79f07852c369e93ae0ccf140df37e3fa`.
Ad-hoc entitlements explicitly omit APS, team and application identifiers;
readback confirms absence, and deep strict signature verification passes.
Logs: `/tmp/textarea-ax-build.log`, `/tmp/textarea-ax-sign.log`.
This bundle supersedes the earlier review copy. No UI actions were taken;
Button owns the slot. Status remains in_progress/awaiting_slot, pending actual
reference comparison and native AX/styleguide/production fixture inspection.


### Pinned-main integration checkpoint

Merged pinned main `e612ad7b47413fa890b35ae3b55a6f6d37b08cf7` in source commit
`d286e1188bc57c2f2b1a26c3439c69d636606d9b`. All non-Textarea progress rows equal pinned main. Final
Button/Badge/Input/Radio/Checkbox, shared styleguide/Sidebar semantics and Topic
Inbox fixes were preserved. Textarea examples now use completed DButton;
multiline adapters retain neighboring final DInput controls. Rich composer
boundaries and the reviewed c2d7026f editor container are unchanged.

221 focused integration/component/migration tests pass (seed 928374611); root
and full-profile analysis and enforced-lockfile resolution pass. No pins or
lockfiles changed. Logs: `/tmp/textarea-integration-tests.log`,
`/tmp/textarea-integration-analysis.log`, `/tmp/textarea-integration-full.log`.

Native debug fixture built from clean committed source `d286e1188bc57c2f2b1a26c3439c69d636606d9b`.
New unlaunched bundle `/private/tmp/DiscourseTextareaReview-d286e118.app` has
identifier `org.discourse.native.textarea.d286e118` and URL scheme
`discourse-textarea-review-d286e118`. Source/copied kernel SHA256 both
`2b33e2ae6338e5aa17e889731b44b50e459cdc497d37216643f6aa1f45093faf`. Deep strict ad-hoc signature verification passes;
signed entitlement readback verifies debug/JIT enabled and APS/team/application
identities absent. Logs: `/tmp/textarea-integration-build.log` and
`/tmp/textarea-integration-sign.log`. This supersedes previous review bundles.
No native/browser actions occurred. Mac lock and browser admin-policy blocker
were not retried or bypassed. Reference/native review remains pending.

### Independent acceptance review — 2026-09-09

The reviewer verified the frozen source hashes and all eight render artifacts,
then compared the official Base UI page in light/dark, focused and invalid
states. Native macOS inspection used the exact `d286e118` bundle and covered
multiline growth, label focus, independent semantics, invalid/form save/reset,
controlled/read-only ownership, live palettes, 320px/200%/RTL layout, and the
actual local-data Invite and Events editors. No component or migration behavior
defect remained. The one acceptance correction changed the styleguide's stale
baseline/pending metadata to implemented/completed.

The independent focused run passed 163 tests with randomized seed 1079605986;
root and full-profile analysis, formatting and `git diff --check` passed. After
the metadata correction, 16 component/visual/styleguide tests passed with seed
933940314. After latest-main integration, the 163-test set passed again with
seed 1478152398 and both analyzers remained clean. Fresh source `35a7959e` built as
`/private/tmp/textarea-final.rvUv9Z/DiscourseTextareaReview-final-35a7959e.app`;
its embedded kernel SHA256 is
`c12e0e3007dc8baaeb0ff917bbd9fef78258a87d1eb49e64523b26ffb59e988f` and
deep strict ad-hoc signature verification passes. The final serialized native
launch is reserved to confirm the corrected styleguide status before merge.

No iOS/Linux device or spoken VoiceOver verification is claimed. Browser Geist
and native host font rasterization differ, so the review compares geometry,
palette, state, interaction and semantics rather than claiming pixel equality.
