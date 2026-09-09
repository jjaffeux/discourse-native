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

`DInputGroupButton` composes `DButton` with input-group sizes and radius.
Button Group now consumes this public surface for joined input/action geometry.
Independent input and button semantics/actions, RTL and large-text behavior are
covered by `InputGroupButtonActionsExample` and focused tests.

`DInputGroupControl` adapts custom native editors. The caller supplies the real
focus node to its builder; the group consumes only focus/enabled/invalid state.

## Examples

The styleguide registers nine actual examples:

- Default search.
- Inline/block alignments.
- Text addons.
- Button actions / Button Group composition.
- Kbd, dropdown, and spinner.
- Textarea footer.
- Custom input.
- Form validation and reset.
- RTL.

Empty's functional search example now uses the final Input Group while
preserving its Form validation, save, submission and local state. The Form
example composes the accepted Field owner around the group without wrapping its
multiple independently interactive children in `DFieldControl`. The keyboard
example composes the accepted Dropdown Menu and Popover lifecycle directly;
the editor retains its value and focus ownership while the menu trigger retains
its own focus, expanded semantics and actions.

## Verification

Independent review fixed two shared-surface state bugs before native review:

- The group now subscribes to every reported control `FocusNode`, repaints the
  exterior ring on focus changes, and removes those subscriptions when controls
  change or the group disposes.
- `DInputGroup(enabled: false)` now dims the whole surface and makes composed
  DInput/DTextarea/custom controls non-interactive and non-focusable.
- The mobile 48px wrapper now owns its outer touch bands, so a tap outside the
  centered 32px artwork still focuses the editor; descendant addon buttons keep
  their independent gesture/action ownership.
- Grouped DInput/DTextarea now contribute only their native editor. Their
  standalone label, helper, error and counter blocks are suppressed inside the
  joined border; Field owns supporting text outside the group, while Form state
  and invalid semantics continue to drive the shared surface.

The regression suite checks the actual parent decoration replacement on focus,
the disabled editor state/opacity/focus exclusion, and listener lifecycle through
the existing focus-node replacement and teardown coverage.

- The final affected matrix covering Input Group, Input, Textarea, Field,
  Dropdown Menu, Popover, Spinner, Empty and all three Chat search migrations
  passed 290 tests with randomization seed `314159265`.
- The accepted Input API reconciliation and Chat consumers separately passed
  210 tests with randomization seed `42424242`; obsolete `editorKey` usage was
  replaced by ordinary widget keys without changing editor ownership.
- `flutter analyze --no-pub` passed.
- `cd profiles/full && flutter analyze --no-pub` passed.
- `git diff --check` passed.

Official light/dark browser comparison and exact-bundle native macOS inspection
are recorded in `evidence/input-group/native-review.md`. The accepted Field and
Dropdown Menu reconciliation changed only catalogue composition around the
unchanged inspected Input Group/editor behavior; their final-owner behavior and
the composition are covered by the affected widget matrix, so the source-exact
native pass remains valid under the review protocol.

The independent reviewer added `tool/input_group_review_main.dart`, an isolated
offline entry point that mounts the real application, accepted styleguide and
all three migrated Chat search surfaces using in-memory fakes. It makes no
account or network request and is the source-exact macOS inspection target.

## Coordination

Accepted dependencies:

- Textarea is accepted on main at `6fbecbcefe1cac3fcbe15f8b9af20fa0569682d3`.
- Field is accepted at `5cd7f3694498e4e09e3c114639baca834b56705e`
  with tracking commit `1001ed005ade4aec0d5f5346473054fb976d2260`.
- Dropdown Menu is accepted at `5c6ab6a15d69c7241ab7d9345eb9f6d6418e2787`
  with tracking commit `a5ad2b5883e7b16e1ef3535f8836b5a86581c2bd`.
- Popover is accepted at `dc6ab75f` with tracking commit `365e093a`.

Button Group dependency:

- Implementation task: `01a08581-831f-7751-b714-096b5aebf86a`.
- Replacement reviewer task: `01a085f4-2a6b-7c82-9dc3-c9b14d76b355`,
  branch `codex/review-button-group-recovered`. The earlier reviewer
  `01a0859e-170c-7821-b0fd-9ff24a9bfaac` is superseded.
- The Button Group styleguide now uses the final public `DInputGroup` for its
  message editor, voice action and joined attachment trigger. Its focused tests
  preserve editor text across voice-state changes and retain independent actions.
- Button Group is a downstream consumer and is not a reverse acceptance gate
  for Input Group.
- Spinner’s former local Input Group validation fixture now uses public
  `DInputGroup` while preserving its example coverage.
