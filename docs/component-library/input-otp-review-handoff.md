# Exact task-creation prompt: Review and merge Input OTP

Create a **new Codex project task** titled **Review and merge Input OTP** with
the following prompt. This file is transport only because task creation was not
callable in implementation task `01a08606-ca44-78f3-98f2-d147200278ef`.

---

Review, fix, accept and locally merge the complete Input OTP component for
discourse-native. You own all remaining work and must not return routine review,
fixes, acceptance or merge to the coordinator.

Implementation task: `01a08606-ca44-78f3-98f2-d147200278ef`

Implementation branch: `codex/ui-input-otp`

Implementation commit: `953692fe1de87078c58a50bb73bb4200553414d4`

Start a fresh review branch named `codex/review-input-otp` from latest local
main. Follow `docs/component-library/review-and-merge.md` exactly. Bring the
implementation branch/commits into the fresh candidate; do not merge main into
the implementation worktree. Preserve current-main migrations, exports and all
other progress rows. Input is accepted at merge
`7df72ef294826616e8ba24c31c6129d8e9041fec`; Field is accepted at merge
`5cd7f3694498e4e09e3c114639baca834b56705e`. Reconcile their current-main source
and verify all overlap. No unaccepted parent may reach main through this branch.

Read the full brief, conventions, visual-fidelity rules, frozen catalogue row,
current-main progress row and `docs/component-library/input-otp-reference.md`.
Verify the frozen Markdown SHA-256
`913027458ed577e6345687c3d42b62f28e2813e1d8b000e1b8b9e52f554b1a6e`,
official base-nova registry SHA-256
`1f8309b2749a129b011c93928416a0da7d6009b55ae8118d45850e488eac8989`,
and exact extracted TSX SHA-256
`800f2398fc404a1fa529d7af8c7647e22553205c482a15bc0c26775f145a6465`.

Review the public `DInputOTP`, `DInputOTPGroup`, `DInputOTPSlot` and
`DInputOTPSeparator` API and implementation. It must retain exactly one bounded,
accessible native TextField owner for typing, selection, paste, context menu,
autofill and IME. Visual slots must not become independent editable fields.
Verify controlled/local/borrowed ownership, controller/focus lifecycle,
max-length and pattern filtering, paste transform order, completion transitions,
selection/backspace/delete, one-time-code autofill configuration, Form
validate/save/reset, required/error association, disabled/read-only state,
semantics, keyboard/touch, logical RTL selection/corners, 200% text, narrow
layout, reduced motion and live host palette/font/radius changes.

Review all ten actual styleguide examples: Default/Composition, Pattern,
Separator, Disabled, Controlled, Invalid, Four Digits, Alphanumeric, Form and
RTL. The Form example already composes accepted Card, Field and Button owners;
do not replace them with temporary primitives. Preserve the exact base-nova
32px slot, 14/20 text, adjoining input borders, lg radius, 3px outside-only
active/invalid rings, dark input/30 fill, 1×16 caret, 16px minus separator and
44×48/20px Form slot mapping unless actual official measurement proves a
correction. Keep the 296px large-code geometry horizontally reachable below
that width rather than distorting it.

The implementation audit found no real core or bundled-plugin OTP/passcode/code
entry UI. Re-run the audit against latest main and migrate any genuine new use
while preserving security/submission/network callbacks. Do not invent an auth
surface or touch accounts/external authentication settings. Diagnostics
`one_time_password` redaction is intentionally retained non-UI behavior.

Existing source verification: 15 focused Input OTP/example tests passed with
seed 9092026; 55 Input OTP/Field/Input/Button/styleguide checks passed with seed
9092027; 31 accepted Card/Button checks passed with seed 9092028; root and
profiles/full analysis are clean; locked dependency resolution, formatting and
diff checks pass. Reuse this evidence for unchanged code and rerun affected
checks after fixes or reconciliation. The earlier aggregate command included a
nonexistent `test/d_card_test.dart`; that invocation-only error was corrected to
the real `test/ui/d_card_test.dart` and is not a product failure.

Use `tool/input_otp_review_main.dart`, which contains every real example with
Light/Dark/Forest/Plum, LTR/RTL, 100/200 percent, reduced-motion and 320/448px
controls and performs no network/auth work. First actual official rendered
browser comparison and native macOS launch/interaction/AX inspection are still
required. Acquire and release the shared `desktop` lease directly with
`/Users/joffreyjaffeux/Code/discourse-native/tool/component_review_lock.py`;
never hold it while waiting on another resource. The host is AZERTY; do not use
unsafe super+a input. Verify actual displayed values and callbacks for typing,
paste, selection/replacement, backspace/delete, completion, validation/save/reset,
resend, disabled state, theme changes, narrow/200%/RTL and reduced motion.
Browser/build screenshots alone do not count as native inspection. Do not claim
iOS/Linux devices or spoken VoiceOver unless actually tested.

Fix every issue in the review task. Promote the example to implemented only
after acceptance. Update only the Input OTP progress row with review task ID,
review branch, evidence, limitations and source pins; regenerate progress.md.
Commit a latest-main candidate. Acquire the `main` lease, ensure shared main
still equals the integrated revision, then perform the authorized `git merge
--no-ff codex/review-input-otp` only from
`/Users/joffreyjaffeux/Code/discourse-native` on `main`. Record the merge SHA in
a follow-up main commit, release the lease, and notify the coordinator and any
dependents directly. No pushes, GitHub writes, release/provisioning/security
changes, account access or external auth changes.

---
