# Live upstream review, 2026-11-04

Reviewed all 20 commits that touch `plugins/live` in the supplied Discourse checkout, from the 2026-10-20 rename through 2026-11-03. The checkout head is `b738bca4ebacd303899f1ca230489ad8a8b26432`. This review uses local source history; it does not claim coverage of newer remote commits.

The native changes add automatic screen-share presentation and visibility of other participants' local recordings. Connection diagnostics are excluded at the user's request.

## Commit decisions

| Upstream commit | Native decision |
| --- | --- |
| [8155780c8b6](https://github.com/discourse/discourse/commit/8155780c8b6) DEV: Correct the live_stun_servers description (#45533) | Server setting description only. The app consumes the server-supplied ICE configuration. |
| [0f920c7be16](https://github.com/discourse/discourse/commit/0f920c7be16) DEV: Correct the server-reflexive candidate assumption in live ICE config (#45532) | Server comment only. No runtime ICE policy changed. Native mesh already preserves the supplied STUN and TURN servers and transport policy. |
| [cc26fe11ae0](https://github.com/discourse/discourse/commit/cc26fe11ae0) UX: Surface missing public addresses and dedupe errors in live connection diagnostics (#45530) | Diagnostics changes excluded at the user's request. The error deduplication belongs to the new diagnostics collector. |
| [6bea1bd88b3](https://github.com/discourse/discourse/commit/6bea1bd88b3) FEATURE: Add connection diagnostics for mesh live rooms (#45525) | Diagnostics feature excluded at the user's request. No native diagnostics collector, probe, report, or UI added. |
| [8838f486ba0](https://github.com/discourse/discourse/commit/8838f486ba0) FEATURE: Switch Live rooms to the presentation layout when someone shares their screen (#45518) | Integrated Auto, Presentation, and Tiled layouts. Auto gives remote screen shares the main area and returns to tiles when they end. Own screen shares do not trigger Auto. Stage rooms use presentation. Explicit choices stay fixed. Browser view transitions, fullscreen DOM handling, and participant pinning are outside this port. |
| [fc62a80e0b4](https://github.com/discourse/discourse/commit/fc62a80e0b4) FIX: Fix Live background blur failing in Brave (#45366) | Browser background blur attaches a hidden video to the DOM for Brave. Native has no DOM-based blur pipeline, so this fix does not apply. |
| [2717adfbc02](https://github.com/discourse/discourse/commit/2717adfbc02) UX: Match the Live reactions picker to post reactions and animate on hover (#45337) | Native already uses Native buttons, wrapping choices, and animated reaction overlays. The web picker's exact spacing, hover zoom, and hover-only animated artwork remain a UI parity gap. |
| [9d54510ed67](https://github.com/discourse/discourse/commit/9d54510ed67) FEATURE: Let Live participants record calls to their own device (#45308) | Integrated the participant is_recording_locally flag, recording indicators in the room, floating call, and native PiP, and one notice per recorder start. Existing recordings at join show the indicator without a new-start notice. Native capture and file export remain unimplemented. |
| [f72218bc9f1](https://github.com/discourse/discourse/commit/f72218bc9f1) FEATURE: Add an animated emoji component and use it for live reactions (#45305) | Animated reaction overlays already resolve catalog artwork through DAnimatedEmoji, with reduced-motion and static fallback behavior. |
| [f34710d1e1b](https://github.com/discourse/discourse/commit/f34710d1e1b) UX: Wrap the live reactions picker and allow any emoji when the site does (#45231) | Already supported by the wrapping native reaction picker, allowAnyEmoji setting, and replacement full emoji picker. |
| [7f1302a2974](https://github.com/discourse/discourse/commit/7f1302a2974) FEATURE: Add floating emoji reactions to live calls (#45178) | Live reaction sending, receiving, expiry, rate limiting, and room and floating-call overlays already exist. Native transcript capture is not implemented. |
| [8f31fb60503](https://github.com/discourse/discourse/commit/8f31fb60503) UX: Fill the live room stage with uniform cropped video tiles (#45177) | Camera cover fit and uncropped portrait and screen-share feeds already exist in the native adapters. Native retains its grid sizing; the web grid solver and two-person self-view arrangement are not ported. |
| [8a6f01ca81c](https://github.com/discourse/discourse/commit/8a6f01ca81c) FIX: Keep live captions visible in fullscreen (#45175) | Browser fullscreen caption portal fix. Native has no Live caption overlay or DOM fullscreen subtree, so this fix has no native target. |
| [d2c57fd4b4a](https://github.com/discourse/discourse/commit/d2c57fd4b4a) FIX: Let live room owners delete their rooms (#45110) | Already integrated through can_delete, the room deletion flow, and preservation of viewer-specific permissions across broadcasts. |
| [01eb99f0db9](https://github.com/discourse/discourse/commit/01eb99f0db9) UX: Make live room page consistent with chat channels (#45149) | Native already has room controls, participant actions, invite handling, a chat conversation panel, and Native sheet presentation. Web CSS and DOM fullscreen changes do not transfer directly. |
| [97a5569ac79](https://github.com/discourse/discourse/commit/97a5569ac79) FEATURE: Add oneboxes for Live room links (#44936) | Already integrated through native Live room oneboxes and live participant presence. |
| [23949cfdec8](https://github.com/discourse/discourse/commit/23949cfdec8) DEV: Use builtin ember truth keywords (#44955) | Ember template keyword cleanup. No Dart change applies. |
| [03831277244](https://github.com/discourse/discourse/commit/03831277244) FIX: Keep mesh Live calls alive through a server outage (#44846) | Already integrated. Resuming roster members retain existing mesh peers; no new peers are created for absent resumable members. Capacity and expired-session refusals retain their native handling. |
| [6aceaa778cd](https://github.com/discourse/discourse/commit/6aceaa778cd) FIX: Improve voice -> live rename implementation (#44847) | Server migration corrections only. No native client change applies. |
| [8560d4ac0e9](https://github.com/discourse/discourse/commit/8560d4ac0e9) DEV: Rename Discourse Voice to Discourse Live (#44542) | Live namespaces and routes already work, with compatibility for older Voice servers. Native module names remain internal implementation names. |

## Native ownership

All changes remain in `lib/src/plugins/voice`, apart from localization resources and tests. `VoiceParticipant` parses the server flag. `VoiceRoom.isBeingRecorded` combines server recording state with participant flags. The existing room-event handler announces new local recorders and preserves their flags during role, hand-raise, and idle-state updates.

The room composes the existing Native `DSelect`, `DCard`, `DBadge`, and `DTooltip` components with Flutter layout widgets. No UI kit API changes are needed. Video remains call-owned and uses the existing adapters, which preserve complete screen-share frames.

## Verification

- The 11 directly related test files completed with 854 passing checks and five failures. Every new regression passed.
- All five failures reproduce on unchanged main at `8da8c46c5`: the media-settings and invite sheet geometry assertions in light and dark themes, and the localization assertion for the existing math example `E=mc^2`.
- Replacing only the room implementation with its original version makes all three new room regressions fail on their behavioral assertions. Restoring the fix passes those regressions.
- Static analysis of the voice plugin and changed tests reports no issues.
- The localization scanner reports the same existing math example as unchanged main.
- Phone and desktop layout captures use the widget-test renderer. No physical-device screen-share session or recording interoperability call was run.

Focused test command:

```sh
flutter test --no-pub test/voice_room_view_test.dart test/voice_controller_test.dart test/voice_call_controller_port_test.dart test/voice_picture_in_picture_test.dart test/voice_models_test.dart test/voice_video_adapter_test.dart test/voice_reaction_widgets_test.dart test/voice_reactions_test.dart test/voice_room_deletion_test.dart test/voice_media_test.dart test/localization_test.dart --reporter expanded
```
