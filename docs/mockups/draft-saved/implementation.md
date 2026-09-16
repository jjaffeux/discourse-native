# Adopted: header status

The composer uses direction 02 from these studies. Routine autosave feedback
now lives immediately before the header controls, without adding a footer row
or moving the editor. The Native `DIcon`, `DSpinner`, and `DTooltip` components
provide the indicator and its details; no UI kit API changed.

- Successful site saves show a muted check and **Saved**.
- New edits show **Saving…** immediately; the spinner animates throughout
  the pending autosave delay and the actual save request, respecting the
  system's reduced-motion preference.
- Site-only failures show **Device only**, while failed local persistence shows
  **Not saved**. Existing detailed footer messages remain visible.
- Minimized composers show **Resume editing**, with draft status and close
  controls restored on expansion. Very large text uses a status icon with
  full tooltip and accessible description if the label exceeds the header height.
- The controller reports the transition into pending edits once, preserving
  the existing policy of avoiding a whole-composer rebuild per keystroke.

The change was integrated with current main's discard-prompt and minimized
composer behavior before final verification.

## Verification

159 focused tests pass across header status, draft failures, panel controls,
docking, the composer controller, background draft saves, and close safety.
Coverage includes stable editor geometry, immediate invalidation of the saved
label, persistent failure states, minimized status, header-control alignment,
320px RTL headers at 100–300% text, and live-region semantics.
The final narrow-label refinement also passed all 22 header and docking tests.

The spinner follow-up adds frame-by-frame rotation checks before the first
request, while the request is pending, and after editing a saved draft. Those
checks reproduce the stationary-spinner bug before the fix and pass afterward
in both dock placements. All 159 focused tests pass again; dialog tests now
wait for dialog transitions instead of waiting for a pending spinner to settle.
An isolated macOS build also confirms changing spinner positions across frames
in light and dark themes, followed by the Saved check when the request completes.

Focused Dart analysis passes without diagnostics. The macOS debug review build
passes. Commands used the locally installed Flutter 3.47.4 / Dart 3.13.3; the
repository's Flutter pin and dependency lockfile were not changed.

The production composer was inspected in an isolated macOS app using in-memory
draft callbacks. Native checks covered light/dark themes, 420px and 320px
composers, saving and saved states, typing through an autosave cycle, device-only
and failed-local-save warnings, and minimizing/restoring with the new Resume
editing control. The full Device only label remains readable at 320px. Native
accessibility exposes the complete status independently of the editor and
header controls. The review app was closed after inspection. No iOS/Linux
device testing or spoken VoiceOver session is claimed.
