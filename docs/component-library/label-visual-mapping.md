# Label visual mapping

Reference inspected on **2026-09-08**:

- [Frozen Label documentation](https://ui.shadcn.com/docs/components/base/label).
  Captured Markdown SHA256:
  `7263b641bac78acd5ec6cfbffefeddda484eaedb1d32b8a73a675b53da0644c2`.
- [Official base-nova registry](https://ui.shadcn.com/r/styles/base-nova/label.json).
  Raw response SHA256:
  `89b01e14fd39dceece9fa421e71e78ea83286bd43a2ca1c2f55d2e8d3958fff2`.
  SHA256 of the UTF-8 `files[].content` for
  `registry/base-nova/ui/label.tsx`:
  `b3b7b21d2877838fc73713df48a47248392de04a3b3fafa8961369f33ab14530`.
- The linked Base UI Label HTML and Markdown API pages returned HTTP 404.
  The frozen documentation and official registry source remain the contract.

| Registry treatment | Flutter mapping |
| --- | --- |
| `text-sm` | Existing unscaled `DiscourseTypography.sm`: 14 logical pixels. |
| `font-medium`, `leading-none` | Weight 500 and line height 1; no added letter spacing. Host font family and inherited text scaler are retained. |
| `flex`, `items-center`, `gap-2` | Child composition; icon/text examples use a centered `Row` with `DSpacing.sm` (8 pixels). Text receives flexible width and wraps. |
| No outer spacing, border, background or radius | DLabel adds none. Control hit areas belong to the associated control. |
| Inherited foreground | Live `DTokens.foreground`, including light, dark and custom site palettes. |
| Disabled opacity and cursor | Whole-label opacity 0.5 and forbidden pointer cursor, including composed icons and spans. |
| Disabled interaction | Disabled semantics, `IgnorePointer` and `ExcludeFocus`; the owner also disables its callback. |
| `select-none` | `SelectionContainer.disabled`. |
| Native HTML label association | Existing Flutter control label slots combine the label's accessible name with the control's state and activation. DLabel adds no tab stop or gesture handler. |

The captured outline, horizontal and submit props belong to neighboring Button
and Field examples. Label has no corresponding variants.

Current examples use Flutter checkbox/switch tiles and TextFormField as temporary
composition while **Checkbox, Switch, Input and Field** are pending. Their
appearance does not define the finished library's visuals. Those catalogue tasks
must reproduce their shadcn reference styling while retaining native interaction,
accessible naming and Form lifecycle behavior.

Existing `InputDecoration.labelText` stays with Input/Field ownership for now;
its floating appearance is not a blanket final native exception. The Label page's
larger payment/billing **FieldDemo**, including FieldLabel, descriptions, errors,
field sets, layout and validation composition, is handed off to the scheduled
**Field** task. Label's local form example demonstrates ownership and behavior,
without claiming completion of that component.

## Native inspection

Inspected on macOS on **2026-09-08**, after the coordinator granted the shared
desktop slot. The isolated `Discourse Label.app` used bundle identifier
`org.discourse.native.label-review` and URL scheme `discourse-label-review`.
Its temporary target mounted the styleguide and actual production widgets with
in-memory callbacks. No account data, network request, room join or microphone
capture was involved. Temporary native project overrides were restored.

Screenshots are local inspection artifacts under
`build/label-inspection/screenshots/` in this worktree:

| Evidence | Observed behavior |
| --- | --- |
| `light-disabled.png`, `dark-enabled.png` | Label clicks and Tab/Space toggle the native checkbox; visible focus belongs to the control. Disabled label clicks do nothing, with the reference opacity. Live theme changes retain state. |
| `forest-rich-360-200.png` | At 360 pixels and 200% text, the icon and emphasized text wrap. The separate terms action changes its own content without toggling the checkbox. |
| `plum-rtl-360-200.png` | Arabic and Hebrew labels wrap at 360 pixels and 200% text; both leading controls appear on the right and toggle from their label text. |
| `plum-form-error-360-200.png`, `plum-form-saved-360-200.png` | Empty submission shows the native validation error. Clicking the email label focuses the field; literal text entry, checkbox activation and submission save locally. Reset clears the field, checkbox, result and error. |
| `post-flag-busy.png`, `post-flag-retained-error.png` | Real PostFlagEditor in Dark: the legal label toggles its checkbox, saving disables it, the local error retains the explanation and selection, and retry succeeds. |
| `voice-privacy-forest-200.png` | Real VoiceMeshPrivacyDialog in Forest at 200% text: the full dialog fits, the privacy label toggles its checkbox, and Cancel returns to the fixture. |
| `voice-diagnostics-consent.png`, `voice-diagnostics-on.png`, `voice-diagnostics-off.png` | Real VoiceDiagnosticsView in Forest: the recording caption opens the existing consent dialog. Cancel leaves recording off; confirming updates the local state and caption to On; clicking the caption stops it. |

The native accessibility snapshots exposed the named PostFlagEditor and Voice
privacy checkboxes with checked state, plus the diagnostics switch named
`Recording Off` / `Recording On` with its corresponding state. Snapshot excerpts
are in `build/label-inspection/*-ax.txt`. The styleguide route exposed only its
native search field through this macOS accessibility snapshot; preview semantics
are covered by widget tests, and VoiceOver speech was not run. iOS and Linux
were not inspected on devices.

The isolated app was quit through its own native menu. A subsequent global CUA
state confirmed its identifier was absent before the desktop slot was released.
Exact automated checks and remaining component handoffs are recorded in the
Label row of [progress.json](progress.json).
