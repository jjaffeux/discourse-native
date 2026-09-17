# Event participant design studies

Three standalone HTML/CSS mockups for the participants dialog, following the approved Compact event card. Open `index.html` or serve this directory with a local HTTP server. No build, dependencies, external assets or network requests are needed.

## Directions

1. **Compact list — recommended.** A 520px dialog, compact segmented response filters, initial avatars, a consistent two-line identity, and quiet response labels. Best visual match for the implemented event card.
2. **Status rail.** A 610px dialog with response navigation on the left and a continuous, avatar-free list. The rail becomes a horizontal filter group in narrow layouts.
3. **Directory.** A 610px dialog with search beside the heading, underline tabs and aligned Participant/Response columns. Desktop rows use less height and handles sit beside names when space allows. Narrow layouts put handles underneath names.

## Source fidelity

The supplied screenshot contains six visible rows, all Going. Names and case-sensitive usernames are transcribed in their original order. Initial avatars are derived from names; no profile photos are invented. The example does not infer total attendance, response counts outside the visible sample, organizer roles, online indicators, invitation controls or additional participant fields. “6 shown” describes the local rows, not the event total.

All, Going, Interested and Not going filters are retained. Interested and Not going show an explicit sample empty state because no corresponding participants were supplied. The application already supports participant profile navigation; mockup row clicks show local feedback without inventing a forum hostname or profile content.

## Interactions

- Search matches name or username, including an optional leading `@`.
- Response tabs combine with search. Arrow keys, Home and End move between tabs.
- Clear search and empty-state recovery work independently of the current response filter.
- Close, Done and Escape dismiss the local preview; Open participants restores it.
- Search, filters and closed state are preserved independently for each direction when changing the preview theme or size.
- Desktop/mobile, dark/light, direction selection and Compare all are reflected in the URL hash.

## Production mapping

The selected **Compact list** is implemented in `lib/src/plugins/discourse_events/event_participants.dart`. It composes the existing Native dialog, DInput, DTabs, DItem, DAvatar, DButton, DSkeleton and DEmpty components. The UI kit itself is unchanged.

The dialog preserves server-side search and response filtering, authorization, stale-request handling, loading/error states, the 200-person result limit, recurring attendance indication and profile navigation. Search runs after a 250ms pause or immediately on submission; an optional leading `@` is removed. Real avatars use the existing loader with initials as the fallback. The footer reports returned rows rather than an inferred event total. A stable, scrollable results area keeps search and response controls in place when results change. Revoked access clears the roster and disables search/filter controls.

Regular controls retain the kit's desktop sizing, touch targets, scaling and keyboard behavior. Equal-width response tabs fill the dialog at ordinary text sizes and scroll horizontally when labels require more space. Rows wrap using the kit's responsive Item layout.

The HTML samples use neutral surfaces and the same soft blue accent as the event mockups. Production colors must come from DTokens and the forum theme.

## Verification — 2026-09-17

JavaScript syntax and whitespace checks pass. Browser interaction checks cover all three designs: username search, combining search and response filters, clearing and empty-state recovery, keyboard Home/End navigation, Done and reopen. Additional checks cover missing-name search, Escape dismissal and local profile feedback. All three dialogs remain within their 360px preview width without horizontal overflow. Visual review covers desktop Compact/Directory in dark, desktop Status rail in light, and narrow Compact/Status rail in light. No app changes or real participant/profile requests are made.

### Native implementation

- Flutter 3.47.2: formatting and full `flutter analyze --no-pub` pass.
- 50 focused tests pass across `event_participants_compact_test.dart`, `event_participants_test.dart`, `event_card_test.dart`, `event_card_semantics_test.dart`, `event_controller_test.dart` and `control_style_adoption_test.dart`. The participant-specific lifecycle regression in `event_card_lifecycle_test.dart` also passes. Coverage includes debounced/combined search, stale responses, retry, revoked access, profile links, recurring/invited responses, the 200-person limit, keyboard navigation/dismissal and 320px layouts with 2× text and keyboard insets in both directions.
- Built and launched `tool/event_participants_review_main.dart` on macOS. This mounts the production dialog with the supplied six rows and a local transport. Native review covered dark desktop, light 360px, light 360px with 2× text and RTL, scrolling through the final row, live `@Emily` search, response filtering, both empty-state recovery actions, Close, Done and Escape. Mobile layouts were widget-tested; no iOS/Android device run was performed.
- The isolated review bundle used only sandbox, JIT and local debug network entitlements, verified after signing. Source and launched bundle kernel SHA-256 matched: `e217621a8b928ff3283ce8ebad5056d6d78bbdba343cd3d2dc094e04222fa02f`. No real account data or participant responses were modified.

Run the local native fixture with `flutter run -d macos -t tool/event_participants_review_main.dart --no-pub`.

### Skeleton loading follow-up

Participant requests now show six decorative row placeholders with avatar, name, username and response shapes. A shared `DSkeletonRegion` announces “Loading participants” once and honors the kit's reduced-motion behavior. Search/filter controls stay usable, the dialog keeps its existing bounds, and the placeholders disappear for ready, empty, error or unavailable states. No count is inferred while loading.

Use `--dart-define=PARTICIPANT_DELAY_MS=5000` with the native fixture to inspect loading before its local response resolves. The delay belongs only to the review transport.

Verification: 17 focused tests pass across participant, invitation and control-adoption coverage; full analysis is clean. Loading-to-ready and loading-to-empty transitions preserve dialog bounds, and loading fits the existing 320px/2×/keyboard/RTL widget cases. Native macOS review confirmed the skeleton in dark desktop and light 360px layouts, one accessible loading label, and replacement by the real rows. The delayed-review source and launched kernel matched SHA-256 `60adf07058a03f44915c0681378b2cde3b8d1991dcfd709c82cd5ec738509b21`; the isolated bundle retained only the same permitted debug entitlements.
