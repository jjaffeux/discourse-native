# Input audit

Audited 2026-09-10 against the live shadcn/ui Base UI Input page and the
current `base-nova` source. Implementation:
`lib/src/ui/components/d_input.dart`. Examples:
`lib/src/styleguide/examples/input_examples.dart`. Focused tests:
`test/d_input_test.dart`, `test/d_input_render_test.dart`,
`test/input_reference_render_test.dart`, and
`test/styleguide/input_examples_test.dart`.

## Reference

| Source | Revision |
| --- | --- |
| [Input docs](https://ui.shadcn.com/docs/components/base/input.md) | SHA256 `1ea19da544283cee29e704fc9c7e930b55fef45018710427e7243e4be93879f4` |
| [base-nova Input registry](https://ui.shadcn.com/r/styles/base-nova/input.json) | SHA256 `bbad1bba130ac9750a61844eeb8f043e8a710846e07689fa85398b80a46c2741` |
| [shadcn/ui source](https://github.com/shadcn-ui/ui/tree/main/apps/v4) | commit `3ba91b1cc83e1bbe4ab35a422ff2a694849c5048` |

The live hashes are unchanged from the earlier frozen reference recorded in
`docs/component-library/input-reference.md`. The current Base UI primitive is
a thin prop-forwarding wrapper; `style-nova.css` supplies `h-8`, `rounded-lg`,
one-pixel `border-input`, transparent/light and `input/30` dark fills,
`px-2.5 py-1`, responsive 16/24px to 14/20px text, muted placeholder,
disabled opacity/fill/cursor, destructive invalid treatment, and a three-pixel
focus or invalid ring. Its `transition-colors` uses Tailwind's 150ms standard
ease and does not transition the box-shadow ring.

## Comparison

| Area | Flutter result |
| --- | --- |
| API and composition | `DInput` is a single-line `FormField<String>` over the platform `TextField`. Controller, parent value, and local initial-value modes are exclusive and documented. Labels/descriptions are native slots; complex Field, Input Group, Button Group, Badge, Select, OTP, and multiline compositions remain with their owners. `DFileInput` keeps file handles and permissions with the host picker. |
| Geometry and tokens | 32px desktop minimum, 10px horizontal and 5px vertical content inset plus one-pixel border, mapped large radius, 14/20px desktop and 16/24px touch text, muted placeholder, transparent light fill, and `input/30` dark fill match the base-nova mapping. Large text grows instead of clipping. |
| States and dark mode | Disabled opacity and light/dark fills, pointer suppression, focus border/ring, destructive invalid border/ring, read-only selection, and live error text match. Invalid labels previously stayed foreground; they now inherit the destructive Field color. |
| Pointer interaction | The reference's full input box is editable. The Flutter editor previously covered only the inner content, leaving its 10×5px padding with an arrow cursor and swallowed presses. The complete surface now shows the text cursor and forwards padding presses to the focus node; disabled surfaces show the forbidden cursor and remain inert. Nested prefix/suffix controls retain their own gestures and cursor regions. |
| Motion | Border and fill now use `Curves.fastOutSlowIn`, Flutter's equivalent of the reference cubic, for 150ms (or zero with reduced motion). The three-pixel ring moved out of the interpolated decoration and paints immediately, matching `transition-colors`. |
| Keyboard and focus | Native editing owns Tab traversal, Return actions, selection, clipboard, undo, context menus, autofill, formatters, secure entry, and IME composition. Labels and the newly active surface inset focus the same borrowed/owned node; disabling drops focus. |
| Accessibility | A bounded text-field semantics node carries the visible or semantic label, value, required flag, and invalid result. Visible labels add no duplicate node, errors are live regions, and adjacent actions do not merge into the editable role. |
| RTL and scaling | Logical alignment/direction flow through `Directionality`; mixed long text scrolls natively. Four styleguide palettes render at 200% in a 320px RTL viewport without overflow. |
| Examples | The seven runnable examples cover basic editing, Field and state treatments, required validation/Form reset-save, secure and controlled ownership, inline search/keyboard submission, native file selection, and RTL/long-text scaling. Current docs' Badge, Input Group, Button Group, Select, and Field layouts are intentionally demonstrated by those component owners rather than duplicated here. |

## Issues

1. Fixed: the standalone surface padding did not focus and showed the wrong
   desktop cursor; disabled padding did not show `not-allowed`.
2. Fixed: the focus/invalid ring faded with border and fill on a linear curve,
   although upstream transitions colors only and shows the ring immediately.
3. Fixed: `labelText` did not take the destructive color when the field was
   invalid.
4. Intentional: responsive web typography maps to touch versus desktop
   platforms, preserving 16px text on mobile; touch controls retain a 48px
   transparent hit target; native selection colors and fonts come from the app
   theme; file selection uses the platform picker rather than a browser file
   control.

No controller, Form, IME, semantics-boundary, file-picker race, dark-token,
RTL, or large-text defects were found in this pass. Borrowed controllers and
focus nodes remain undisposed, equal controlled updates preserve composing and
selection, changed controlled values end composition, and pending file-picker
results remain invalidated by reset or disable.

## Verification

Verification commands and final results are recorded in the integrating commit
and task report. The focused widget tests explicitly cover the corrected inset
focus/cursor, invalid-label color, and immediate ring behavior in addition to
the existing editing, semantics, pixel, styleguide, and real-editor harnesses.
