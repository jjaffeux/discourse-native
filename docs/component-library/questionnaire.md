# Questionnaire implementation record

## Frozen sources

- Catalogue/reference date: 2026-09-08.
- Styled Markdown: `https://ui.shadcn.com/docs/components/base/questionnaire.md`,
  SHA-256 `174687e701dfa6b70a0583de3bfee8dd2885b4c8fd51a899adfaffd689a9dc7c`.
  This exactly matches `catalogue.json` on 2026-09-09.
- Base-nova registry JSON:
  `https://ui.shadcn.com/r/styles/base-nova/questionnaire.json`, SHA-256
  `7eac8ca2fb479be1a18c97cced020b93c22cec1926dea72c8be324cdb3b62fa9`.
  Its sole `questionnaire.tsx` payload hashes to
  `fb5db703937410dee230586678a859b7add61114d7fbf6d6bbfb7101cdfc86ff`.
- Unstyled/API Markdown: `https://ui.shadcn.com/docs/react/questionnaire.md`,
  SHA-256 `b6b1f21e3b12dcae85fa89a1582b29ec0e8aede97b02ad33bcbd8db748b06d58`.
- Primary behavior package: `@shadcn/react` 0.3.1 tarball, SHA-256
  `0c40a06316d9bac27029f1d81874d894d77ef43a74cad0d12aaab620907563d8`.
  The package declaration and minified implementation were inspected directly.
- Official repository main observed at
  `3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`. The catalogue pin is the
  frozen Markdown hash above, not a moving repository branch.

## Reference-to-Flutter mapping

| Reference | Flutter mapping |
| --- | --- |
| Root `flex`, full width, 16px gap | `DQuestionnaire` column with stationary progress/actions and a keyed active-item region |
| Progress 12px medium, 16px line, tabular figures, minimum 14ch | `DQuestionnaireProgress`, live named progress semantics, exact typography; Flutter's numeric range uses 0 as its lower bound because native semantics reject `min == max` for one-item flows |
| Item 16px gaps, zero fieldset border/padding | `DQuestionnaireItemView`; separate semantic container keeps answer controls independent |
| Title 16px/22px medium heading; description 14px/20px muted | `DQuestionnaireTitle` header and `DQuestionnaireDescription` using host font family and explicit reference metrics |
| Choices grid gap 8px | `DQuestionnaireChoices` column, 8 logical pixels |
| Choice min-height 44, 12px horizontal/10px vertical padding, 10px gap, `rounded-lg` | `DQuestionnaireChoiceTile`; 44px pointer surface and 48px touch-platform minimum, host radius ×1 |
| Input/border tokens, muted hover/checked surface, dark input alpha | `DTokens.colors.outlineVariant`, `muted`, `primary`, and multiplicative alpha; no fixed light/dark swatches |
| 16px round/radius-4 indicator; 20px shortcut key | custom radio/check artwork and a host-radius ×0.8 shortcut surface |
| Focus border plus exterior 3px half-alpha ring | focused border and outside-only custom stroke; transparent tiles are not tinted behind the ring |
| Input 32px desktop/44px touch and native editing | `DInput` with owned/borrowed editing lifecycle, semantic label, keyboard type mapping, IME-safe text handling |
| Previous/Skip outline; Next/Submit primary; 8px action gap | actual `DButton` owners with conditional visibility, async busy state and wrapping narrow layout |
| Optional animated active item | keyed fade/4% logical slide using `DMotion.change`; zero duration under reduced motion |

All colors, fonts and radii are read during build, so light/dark/custom theme changes
apply live. Padding is directional. Labels and actions wrap rather than clipping at
narrow widths or 200% text.

## Behavior and API decisions

- `DQuestionnaireController` is the unstyled/headless behavior owner. The
  styled root does not contain persistence, transport, account or Discourse
  branching logic.
- Item IDs are unique stable strings. Choices keep typed `Object` values;
  `valueFor<T>` and `valuesFor<T>` provide checked reads. Non-JSON values require
  an explicit encoder/decoder when saving.
- `unanswered`, `answered` and `skipped` are distinct. Optional unanswered
  items fail validation until answered or explicitly skipped. Skip stays
  available on optional items, clears an answer, and submits when used on the
  final item.
- Multiple values retain item order of interaction. A freeform answer and fixed
  selection are mutually exclusive. Empty/whitespace text is unanswered.
- Conditional disabled items retain their draft for backtracking but are
  removed from navigation, progress, validation and submission. Disabled
  choices do not receive shortcuts and cannot satisfy validation/submission.
- Previous never validates. Next validates the active item. Submit validates
  every enabled item and returns to/focuses the first invalid item. External
  errors can redirect through `setExternalError` and `goTo`.
- Async validators carry both an operation generation and answer revision.
  Changing/resetting an answer cancels the stale result and clears busy state.
- A navigation delegate returns a boolean acceptance before state changes.
  `currentItemId` plus `onCurrentItemChanged` exposes the styled controlled
  pattern. Saved state restores active item, answers and visited IDs; reset
  restores that saved/default state.
- Letter shortcuts assign A–Z and number shortcuts 1–9 across enabled choices
  without advancing. They do not intercept an editable field. Up/Down wraps
  among answers and updates radio selection; Enter on an already selected
  answer advances/submits; Control/Command+Enter advances/submits.
- Successful navigation focuses the first enabled answer (or input). Validation
  failure retains/focuses the current answer. Inactive content is absent from
  the widget/semantics tree. Choice selection, errors and progress have native
  semantics; error/progress changes use polite live regions.
- `itemBuilder`, `progressBuilder` and `actionsBuilder` preserve controller
  behavior while allowing Card, Dialog and custom composition. `showReset` is
  opt-in, matching the reference's explicit reset button rather than adding one
  to every questionnaire.
- React server rendering maps to deterministic Flutter configuration: the full
  item collection is present before first build, so current item, progress,
  actions and shortcuts are correct on the initial frame.

## Application adoption audit

The current core and bundled-plugin tree was searched for `Stepper`, `PageView`,
`currentStep`, `stepIndex`, wizard/onboarding/survey/questionnaire/intake and
clarification patterns, then all `Form`, dialog and sheet compositions were
reviewed. There is no existing multi-step questionnaire or onboarding flow.

Retained alternatives are intentional:

- `PollCard` is a single server-authored poll with voting permissions, deadlines,
  result modes and network mutation ownership. Turning one poll into a client
  questionnaire would change its semantics and submission contract.
- `PollComposerSheet`, bookmark/invite/account forms, preferences and the Voice
  room editor expose interdependent fields together and save atomically. Hiding
  them one at a time would reduce context and alter validation/permission rules.
- Carousel, event calendar and lightbox `PageView` usages navigate media or dates,
  not questions.
- Shell sheets and dialogs keep their existing close/cancel owners. The
  Questionnaire Dialog example composes the accepted `DDialog` without moving
  dismissal into the generic questionnaire.

Therefore there is no production migration in this component change. The nine
interactive styleguide examples use the real public owners for the documented
basic, multiple, freeform, skip, shortcut, validation, controlled, resume,
conditional, navigation, custom-progress, animation, Card, Dialog and unstyled
compositions. `tool/questionnaire_review_main.dart` mounts those same public
examples with local data and explicit theme, RTL, 200%-text, reduced-motion and
216px-width controls; it is the source-exact macOS review target, not a substitute
for a production adopter that does not exist.

## Independent acceptance

The independent review re-downloaded every frozen source above and reproduced
all recorded SHA-256 hashes. The official rendered Base UI example was inspected
at 1024px and 375px in light and dark states. Its 448px wide root, 16px vertical
rhythm, progress and heading typography, choice padding/minimum height, 32px
desktop input/actions, selection/focus treatment and narrow wrapping matched the
mapping above.

Review found and corrected four behavior/parity gaps:

- ordinary letter/number shortcuts are suppressed while a native text editor is
  active, while Control/Command+Enter remains available outside active IME
  composition;
- shortcut selection focuses the selected enabled choice and keeps disabled
  choices out of shortcut numbering;
- submitting a non-empty freeform answer with Enter advances or submits; and
- item slide transitions use logical direction and therefore mirror in RTL.

Direct widget regressions cover each correction, including an active composing
range. The final focused Questionnaire suite passed 23 tests and 139 composed
Field/Input/Button/Progress/Card/Dialog/Native Select owner regressions passed.
Root and `profiles/full` analysis were clean; locked dependency resolution,
formatting and `git diff --check` passed.

The uniquely identified exact-source macOS fixture was built, ad-hoc signed and
verified with deep/strict codesign. Native inspection exercised the complete
three-step flow, empty validation, radio and checkbox keyboard behavior,
disabled shortcut mapping, ordinary freeform editing, progress/action changes
and public-example geometry. Final kernel SHA-256:
`77e51f8523b54537b4ad78eddd62f7d4a49b95b5c611d001ee4642329245261c`.

No iOS/Linux device or spoken VoiceOver claim is made. Active native IME
composition was not synthesized in CUA; that edge is covered by the direct
widget test and native accessibility-tree inspection is not a spoken-reader or
cross-platform claim.
