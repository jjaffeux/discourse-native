# Input OTP reference and implementation

Captured **2026-09-09** for the catalogue frozen on 2026-09-08.

## Primary sources

- Frozen official Markdown: `https://ui.shadcn.com/docs/components/base/input-otp.md`
  - SHA-256: `913027458ed577e6345687c3d42b62f28e2813e1d8b000e1b8b9e52f554b1a6e`
  - Re-fetched and verified byte-for-byte on 2026-09-09.
- Official base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/input-otp.json`
  - SHA-256: `1f8309b2749a129b011c93928416a0da7d6009b55ae8118d45850e488eac8989`
  - Exact UI source is stored in `reference/input-otp/input-otp.tsx` with
    SHA-256 `800f2398fc404a1fa529d7af8c7647e22553205c482a15bc0c26775f145a6465`.
- Upstream `input-otp` README: `https://github.com/guilhermerodz/input-otp/blob/master/README.md`
  - SHA-256 on capture: `44adbdf7084e81ff10ac88ff526260c1ee6bbcaa112bb87f3ab2eea8ab9e9cac`.
  - Confirms the single-field accessibility/autofill model, required max length,
    controlled/uncontrolled value, completion transition, pattern,
    paste transformer and forwarded native input behavior.

## Exact visual mapping

| Base-nova source | Flutter mapping |
| --- | --- |
| `flex items-center` container | One intrinsic horizontal composition; disabled opacity is applied once to the whole editor. |
| `size-8` slot | 32×32 logical pixels at 100% text; slots grow vertically when scaled line height no longer fits. |
| `text-sm` | Host font family with explicit 14px, 20px leading, weight 400 and zero tracking. |
| `border-y border-r border-input`, first left border | One-pixel `colors.outlineVariant` adjoining borders without doubled interior strokes. |
| `rounded-lg` | Host `DTokens.radius × 1`, preserving the shadcn theme radius scale. Corners follow logical group order in RTL. |
| dark `bg-input/30` | `colors.outlineVariant` with its existing alpha multiplied by 0.30. |
| active `border-ring ring-3 ring-ring/50` | Focus border plus an outside-only three-pixel annulus at multiplied 50% focus-ring alpha. |
| invalid destructive border/ring | Destructive border; outside-only three-pixel annulus at 20% light / 40% dark multiplied alpha. |
| caret `h-4 w-px`, 1000ms cycle | 1×16 caret with a 500ms reverse half-cycle; remains visible under reduced motion. |
| separator 16px Minus icon | 16×16 custom-painted round-capped two-pixel minus; no Material icon metrics. |
| Form slots `w-11 h-12 text-xl`, separator `mx-2` | 44×48 slots, 20px text with measured 28px leading, eight-pixel separator insets. A horizontal viewport preserves exact geometry below its 296px intrinsic width. |

Focus and invalid rings are painted only outside their surface; no spread shadow
tints the translucent dark fill. Colors, font family and radius are read during
every build, so live host palette changes reach focused and invalid controls.

## Behavior and API mapping

`DInputOTP` is one `FormField<String>` containing exactly one `TextField`.
`DInputOTPGroup`, `DInputOTPSlot` and `DInputOTPSeparator` are projections of
the editor's value, selection and focus, never independent editors. This keeps
one native editable role, one tab stop, one selection, platform paste/context
menu, IME ownership and `AutofillHints.oneTimeCode`.

The caller chooses exactly one value mode: borrowed `TextEditingController`,
controlled `value`, or local `initialValue`. Borrowed controller/focus resources
are never disposed. `inputTransformer` runs before per-character `pattern` and
length filtering, matching the upstream paste-transform order. Completion fires
only when editing transitions from incomplete to exactly `maxLength`; deleting
then completing again fires a new completion. Form validate/save/reset use the
ordinary Flutter lifecycle and reset restores the sanitized mount snapshot.

Pointer presses map to a logical slot selection; native keyboard selection,
replacement, backspace/delete, paste and composing updates remain owned by the
single editor. Visual children are excluded from semantics and merged with the
bounded editable node. Field compositions add the visible label, description,
required and error association without becoming another value owner.

## Frozen example coverage

The styleguide registers actual Default/Composition, Pattern, Separator,
Disabled, Controlled, Invalid, Four Digits, Alphanumeric, Form and RTL examples.
The Form card uses accepted `DCard`, `DField` and `DButton` owners, including the
24px outline resend action, 44×48 slots, submit validation/save, reset and help.

## Application audit

The full tracked Dart/source tree was searched for OTP, one-time password,
passcode, verification/security/authentication code and two-factor/TOTP inputs.
There is no current core or bundled-plugin authentication/code-entry UI to
migrate. Diagnostics only redact the server-side `one_time_password` key and are
not an interactive surface. No account, external authentication or security
setting was opened or changed. Future authentication adapters should compose
`DInputOTP` and keep submission, expiry, resend, attempt limits and network
errors in their domain owner.

## Acceptance checklist and limits

- Frozen hashes and source mapping recorded.
- All documented compositions use final accepted component owners.
- Focused tests cover paste, pattern, completion, selection/deletion, controlled
  updates, borrowed lifecycle, autofill configuration, Form validation/save/reset,
  disabled behavior, semantics, pointer slot selection, RTL and 200% text.
- Independent browser inspection measured the live Base UI default slot at
  32×32, 14/20 text, 1px border and 10px radius, the focused 3px ring, and the
  Form slot at 44×48 with 20/28 text. The measured Form leading corrected the
  earlier 20px Flutter line box; the exact 296px composition remains horizontally
  reachable at the narrow preset.
- The exact isolated macOS bundle at
  `/private/tmp/input-otp-review-final/Input OTP Review.app` used identifier
  `org.discourse.native.inputotp.review.final`; its built/copied kernel SHA-256
  was `a589040ad9cae4432da1bae0daa73bf0e37fb5c372fa11389f2e196a88c37c20`.
  Deep strict ad-hoc signing and the restricted-free debug entitlement readback
  passed.
- Native macOS inspection verified literal typing with transform/pattern
  filtering, completion and Return submission counters, keyboard range
  replacement, Backspace/Delete, visible validation, save/reset and resend,
  one editable AX node per OTP composition, an inert disabled composition, and
  the native Paste context menu. Light, dark, Forest and Plum palettes, 6/12px
  host radii, LTR/RTL, 100/200 percent text, 448/320px width, reduced-motion
  caret and the horizontally scrollable Form code were inspected.
- The CUA native paste helper changed only its accessibility proxy value and did
  not enter Flutter's TextInputFormatter/controller callback path. Paste
  transform/filter order remains verified by focused widget tests; no native
  paste-success claim is made. The proxy artifact was cleared by normal literal
  typing and did not affect the visible Flutter value owner.
- No iOS/Linux device or spoken VoiceOver claim is made.
