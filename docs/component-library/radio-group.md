# Radio Group implementation — awaiting native review

Reference: frozen 2026-09-08 Radio Group catalogue entry, all documented sections
(Usage, Composition, Description, Choice Card, Fieldset, Disabled, Invalid, RTL).
The local registry and example source are preserved under `reference/radio-group/`;
the shared `reference/LICENSE.shadcn.md` applies.

Sources retrieved 2026-09-09:
- https://ui.shadcn.com/docs/components/base/radio-group
- https://ui.shadcn.com/r/styles/base-nova/radio-group.json
- https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/radio-group-example.tsx

The registry's Base UI Markdown API link returned 404. Flutter 3.47.2's actual
`RawRadio` and `RadioGroup` source was inspected for native focus, checked
semantics, arrow wrapping and RTL behavior. No browser/native app was opened.

| Reference source | Flutter logical metric / behavior |
| --- | --- |
| `size-4`, `border`, `rounded-full` | 16×16 circle, 1px border |
| indicator `size-2` | centered 8×8 primary-foreground circle |
| checked primary background/border | live DTokens.primary |
| focus `ring-3 ring-ring/50` | 3px outer spread, focusRing at 50% |
| invalid `ring-destructive/20`, dark `/40` | 3px spread at 20%/40%; dark unchecked border 50% |
| dark `bg-input/30` | border token at 30% |
| disabled opacity 50%, forbidden cursor | 50% entire associated item; no activation or traversal |
| label composition `gap-3` | 12px indicator/content gap; DLabel 14px/500/1 |
| root `gap-2` | explicit 8px gaps in reference examples; child layout remains caller-owned |
| CSS after inset x=12/y=8 | 40×32 pointer bounds; 48×48 native touch bounds around compact circle |

The host owns fonts, palette, radius and inherited text scale. Choice-card
presentation uses 16px padding, a 1px border, radius token+4 and selected primary
at 5%; native rendered comparison is still required. There is no animated
transition in the registry; changes are immediate, including reduced motion.

The labelled row's layout reserves non-overlapping hit bounds. This increases
row pitch compared with web examples whose pseudo-element can overlap the grid
gap. The circle remains 16px. This native adaptation avoids overlapping touch
and semantics targets; it is explicitly subject to the pending native review.

## Public API and ownership

`DRadioGroup<T>` owns initial selection. `DRadioGroup<T>.controlled` reads the
parent's `groupValue`; callbacks are requests and a rejected request preserves
the accepted value in Form save/validation. Both expose initialValue,
onChanged, validator, onSaved, autovalidateMode, forceErrorText, enabled,
invalid and label/description slots. Reset requests initialValue; a controlled
parent may decline or accept later without diverging Form and visible state.

`DRadioGroupItem<T>` provides value, label, description, trailing,
semanticLabel, enabled, invalid, focusNode, autofocus, card and toggleable.
Use distinct values and the same generic type throughout a group. Label slots
are activated together and merge semantics; independent interactive links
belong outside them. Borrowed focus nodes survive removal/replacement.

Native RadioGroup owns one Tab entry, wrapping arrow selection, disabled-item
skipping, Space activation and RTL horizontal navigation. Poll opts into
`toggleable` to preserve withdrawal of an existing vote. This is a domain
adaptation, not the default radio behavior. Form reset never silently changes
an accepted controlled selection. The existing merged DLabel is composed;
Field remains pending and is not implemented by this task.

## Application audit

- `topic_move_posts.dart`: destination radios retain search, automatic sole-result
  selection, async ownership checks, chronological ordering and submission.
- `topic_change_owner.dart`: user radios retain avatar, username/name, search,
  disabled saving state, permission and account/target ownership checks.
- `post_flag_editor.dart`: associated reason rows replace nested InkWell/Radio
  focus owners; message requirements, legal confirmation and async save remain.
- `plugins/poll/poll_card.dart`: single-choice and numeric options use a real
  radio group. Immediate voting, withdrawal, async rollback, results/tallies,
  permissions and deadline disabling remain in PollCard.
- Shell and Chat recognize RawRadio as a focus owner so pane shortcuts cannot
  steal radio navigation. Focus ownership regression uses the actual component.

Retained: Poll multiselect remains Checkbox task-owned; ranked-choice remains
its web workflow; menu-item radios in choice_menu retain menu semantics and
belong to menu tasks. Existing generic Label examples using native controls
remain under their component owners. Input owns search fields in change-owner;
Button owns Poll actions. No dependencies, lockfiles, pins or runner sources
are changed.

## Review fixture

`tool/radio_group_review_main.dart` mounts real PostFlagEditor and PollCard,
opens the real owner/move dialogs through ShellController, and links to the
actual styleguide. Stores, authenticator and API are in-memory fakes; the site
is radio-review.invalid. Search `review` for two options; other terms produce
empty results. Light/dark, RTL, 200% text and simulated save-error controls are
local. No credentials or account data are read or written. Widget verification
checks the actual search results can be selected in both dialogs.

Native review remains **awaiting_slot**, not review_ready. No claim of rendered
visual parity, VoiceOver speech, iOS device or Linux device inspection is made.
The coordinator must inspect styleguide and all four migrated surfaces before
merge. Bundle provenance and final automated verification are recorded below.

## Captured source hashes (SHA256)

- `examples.tsx`: `abb4e0ca3f42884001666c790aa061c31f6e1ae01c1451d80ed8c6f699f55ea0`
- `radio-group.json`: `874b30662ba338d06362491b663cae9198281a4bc385b6be6425f2de442384d7`
