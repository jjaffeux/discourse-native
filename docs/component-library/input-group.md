# Input Group

Implementation task: `01a085af-d606-7281-ac25-34c83adc855e`.
Branch: `codex/ui-input-group`.
Implementation source: `30078b3bf4e4eac96411c19c3bc16b2732ceff59`.
Independent review: task `01a085d3-1acf-7361-9dc8-fc4a99de7c45`, branch
`codex/review-input-group`.

## Reference

- Frozen Markdown: `https://ui.shadcn.com/docs/components/base/input-group.md`
- Frozen Markdown SHA256: `6a1c182773fd4981af63da9ca5b2cb70cd0743f658a728b8fb9f6a6bd2a71a96`
- Primary registry source: `https://ui.shadcn.com/r/styles/base-nova/input-group.json`
- Registry source inspected during implementation: `registry/base-nova/ui/input-group.tsx`

The Base Nova source defines:

- `InputGroup`: `role="group"`, `relative flex h-8 w-full min-w-0 items-center rounded-lg border border-input transition-colors outline-none`.
- Disabled state: group opacity `50%`; dark disabled fill uses input `80%`.
- Focus state: focus-visible control changes group border to ring and paints a `3px` ring at `ring/50`.
- Invalid state: destructive border plus a `3px` destructive ring at `20%` light / `40%` dark.
- Block addons switch the group from fixed `32px` height to auto height and column layout.
- Addons: `py-1.5`, `gap-2`, `text-sm font-medium text-muted-foreground`, `select-none`.
- Inline addon inset: start/end `8px`; group adjusts the adjacent input side to `6px`.
- Block addon inset: horizontal `10px`, top/bottom `8px` and `4px` depending on edge.
- Buttons: default `ghost`, `xs` height `24px`, icon-xs `24px`, icon-sm `32px`, radius `host radius - 3px`.
- Inputs and textareas reuse the base Input/Textarea owners with border, background, shadow and ring suppressed inside the group.

## Flutter mapping

`DInputGroup` owns the joined visual surface only. It provides the single border,
fill, disabled opacity, focus-within ring and invalid ring. It does not own text
editing or button activation.

`DInputGroupInput` subclasses `DInput`, and `DInputGroupTextarea` subclasses
`DTextarea`. The surrounding `DInputGroupControlScope` suppresses their
standalone surface while preserving:

- controller/value/initialValue and Form save/reset/validation;
- borrowed controller/focus/scroll/undo ownership;
- native text editing, selection, IME and keyboard behavior;
- bounded text-field semantics;
- independent focus nodes, including focus restoration from addon taps.

`DInputGroupAddon` positions icon/text/button/Kbd/spinner content at
`inlineStart`, `inlineEnd`, `blockStart` or `blockEnd`. Addon taps focus the
first available control; nested buttons keep their own gesture/action owner.

`DInputGroupButton` composes `DButton` with input-group sizes and radius. This is
the public replacement surface for Button Group’s temporary local Input Group
handoff fixture: joined input/action geometry, independent input and button
semantics/actions, RTL and large-text behavior are covered by
`InputGroupButtonHandoffExample` and focused tests.

`DInputGroupControl` adapts custom native editors. The caller supplies the real
focus node to its builder; the group consumes only focus/enabled/invalid state.

## Examples

The styleguide registers nine actual examples:

- Default search.
- Inline/block alignments.
- Text addons.
- Button actions / Button Group handoff.
- Kbd and spinner.
- Textarea footer.
- Custom input.
- Form validation and reset.
- RTL.

Empty's functional search example now uses the final Input Group while
preserving its Form validation, save, submission and local state. Dropdown,
Popover and Field overlays remain separate catalogue owners. Their
Input Group examples use local non-overlay stand-ins until those owners merge;
this avoids importing unmerged branches or duplicating overlay components.

## Verification

Independent review fixed two shared-surface state bugs before native review:

- The group now subscribes to every reported control `FocusNode`, repaints the
  exterior ring on focus changes, and removes those subscriptions when controls
  change or the group disposes.
- `DInputGroup(enabled: false)` now dims the whole surface and makes composed
  DInput/DTextarea/custom controls non-interactive and non-focusable.

The regression suite checks the actual parent decoration replacement on focus,
the disabled editor state/opacity/focus exclusion, and listener lifecycle through
the existing focus-node replacement and teardown coverage.

- `flutter test --no-pub test/d_input_group_test.dart test/styleguide/input_group_examples_test.dart test/styleguide/spinner_examples_test.dart test/styleguide/empty_examples_test.dart --test-randomize-ordering-seed=497094161` passed: 30 tests.
- `flutter test --no-pub test/d_input_test.dart test/d_textarea_test.dart test/styleguide/input_examples_test.dart test/styleguide/textarea_examples_test.dart --test-randomize-ordering-seed=3777303596` passed: 38 tests.
- `flutter test --no-pub test/chat_navigation_test.dart test/chat_shell_integration_test.dart --test-randomize-ordering-seed=79316425` passed: 172 tests.
- `flutter analyze --no-pub` passed.
- `cd profiles/full && flutter analyze --no-pub` passed.
- `git diff --check` passed.

Noted but not modified: `test/d_spinner_test.dart` currently fails an isolated
loading-button color expectation unrelated to the Input Group/Spinner styleguide
fixture replacement.

The implementation has not completed official browser/native inspection yet.
The independent review task must re-run affected verification, compare against the official rendered
reference, inspect native macOS styleguide/app surfaces, and then perform the
local main merge under the review protocol.

The independent reviewer added `tool/input_group_review_main.dart`, an isolated
offline entry point that mounts the real application, accepted styleguide and
all three migrated Chat search surfaces using in-memory fakes. It makes no
account or network request and is the source-exact macOS inspection target.

## Coordination

Textarea dependency:

- Prepared review source included in this branch: `4ca5aaa85681ced6dd2668a8158b7551ee176f73`.
- Textarea reviewer: `01a08558-7a1f-7ba0-b3be-a27b46bc2b42`.
- Final Input Group acceptance is gated on the accepted Textarea main revision,
  not only this prepared source pin.

Button Group dependency:

- Implementation task: `01a08581-831f-7751-b714-096b5aebf86a`.
- Reviewer task: `01a0859e-170c-7821-b0fd-9ff24a9bfaac`.
- The Button Group styleguide’s explicitly labeled local Input Group handoff
  fixture must be replaced with the final public `DInputGroup` composition
  without reducing the example surface.
- Spinner’s former local Input Group validation fixture now uses public
  `DInputGroup` while preserving its example coverage.
