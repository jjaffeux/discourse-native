# Toggle independent review evidence

- Reviewed source: `d39eb0f3` (`Revert "FIX: match Toggle icon edge padding"`)
- Bundle: `/private/tmp/discourse-toggle-review-d39eb0f3/Discourse Toggle Review d39eb0f3.app`
- Bundle ID: `org.discourse.toggle-review-d39eb0f3`
- URL scheme: `discourse-toggle-review-d39eb0f3`
- Built/copy kernel SHA-256: `3eea3bb75a19aeab195e3ced4e91c3d6b2d01fe5fc46aad6fb9dc49d75334529`
- Signature: ad-hoc, deep strict verification passed
- Entitlements: sandbox, JIT, network client/server, user-selected files,
  audio input and camera only; no APS or developer identifiers

## Official rendered comparison

The live Base UI Toggle documentation was inspected in light and dark. The
documented examples render 28/32/36px surfaces, 14px small and 16px regular/
large icons, 4px icon gaps, 10px symmetric horizontal padding, 8px radius,
input-token outlines, muted hover/pressed surfaces, disabled opacity and
logical RTL ordering. Although the registry includes optional icon-edge
selectors, the documented Lucide examples do not emit the matching `data-icon`
annotation; the accepted Flutter example therefore keeps its symmetric 10px
padding.

## Native interaction pass

The isolated app mounted the exact production `VoiceToolbarControl` adapter and
the public styleguide examples. Pointer activation toggled mute/unmute,
deafen/listen, camera on/off, share/stop sharing, raise/lower hand and start/stop
recording; Media settings remained a one-shot button. Default bookmark,
independent outline preferences, text composition, sizes, disabled, Arabic RTL,
controlled/uncontrolled ownership, icon-only and invalid states all rendered
and behaved correctly. Live Light, Dark, Forest and Plum themes, RTL and 200%
text retained state. Tab traversal followed by Space and Return activated real
Voice toggles. Disabled controls did not activate.

The app was quit and the exclusive desktop lease released immediately after
inspection. The later latest-main integration did not modify Toggle, shared
theme/tokens used by it, Voice adapter code or this fixture.

## Verification and limits

After latest-main integration, 81 focused tests passed with randomized seed
`9052032`; root and `profiles/full` static analysis passed, locked dependency
resolution made no dependency changes and `git diff --check` was clean. No
physical iOS/Linux device run or spoken VoiceOver verification was performed.
Browser/native font rendering differs, so this is measured behavioral and
visual acceptance rather than a pixel-equality claim.
