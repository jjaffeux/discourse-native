# Post event design studies — round 2

Open index.html directly or use the existing local preview. No build, libraries, fonts, or remote image requests are required.

The four directions now differ through composition rather than event-specific content:

1. **Framed** — title-first header, small date tile, grouped details, inset description and separate response area.
2. **Date rail** — a vertical date anchor alongside a continuous content column.
3. **Schedule band** — date/time strip above the title and a typographic body.
4. **Compact** — smaller date tile, tighter spacing and a shorter description preview.

All four use the same neutral surfaces and accent palette. There are no illustrations, taglines, occasion labels, special ticket semantics, or hardcoded title line breaks. Dark/light, desktop/mobile and side-by-side comparison remain available.

## Source fidelity

The single eventData object transcribes the supplied screenshot: title, public status, creator, date, time, timezone, location text, Google link label, description, and counts of 2 going / 0 interested. The description retains its original line order and wording, including repeated instructions and the empty Reference Topic label. It is rendered as free-form text, without a travel-specific schema or generated summary.

Removed the invented surrounding post copy, publication timestamp, username, likes, attendee identities, chat conversation, meeting-point search URL, calendar export, and dinner artwork. Aimee's avatar uses the initial of her supplied name. Participant photos are not reconstructed from the screenshot; attendance is represented by the supplied counts without assigning unknown identities or statuses to those photos.

The screenshot exposes Google link, Open event chat, and a more-actions control but not their destinations, contents, or messages. Clicking those controls explains that limitation locally; the prototype invents no destination or content and makes no external request.

## Interactions and missing fields

- Going, Interested, and Not going are mutually exclusive local responses; clicking a selected response clears it. The counts change only in response to that explicit preview interaction.
- Show full description / Show less expands and collapses the original text.
- All supplied fields / No description / No location or description removes optional content without creating replacement content. This demonstrates how the same structures contract when optional fields are absent.
- Theme, width and content switches preserve local RSVP and description expansion state.
- URL hash parameters preserve direction, width, theme, content configuration and comparison mode. Old direction links resolve to their replacements.

No assumptions are made that an event is social, in person, paid, ticketed, or needs artwork. The supplied event remains a dinner because that is its actual title. These studies do not create fictitious webinars or other sample events to demonstrate variety.

## Native implementation

Compact is implemented in `lib/src/plugins/discourse_events/event_card.dart` through `package:discourse_native/discourse_ui.dart`: DCard content/footer, DButton actions, wrapping DToggle responses, DDropdownMenu, DAvatar and DCollapsible. Controls retain the kit's regular 28px height and 8px radius as the desktop baseline. Selection is shown on the response controls, without a duplicate “Your response” line. The server remains the source of truth for attendance; the recurring Going menu retains this-occurrence/every-occurrence choices.

The implementation preserves recurrence, privacy, permission, pending/error, expiry, capacity and arbitrary rich-description behavior. A production date rail represents the start date; the full date/time field must still support multi-day and all-day events through the existing event formatter. Optional location, description, creator and participant data must remain conditional. The mockups test removing location and description only. Ordinary surfaces and accents must derive from DTokens. Follow AGENTS.md before any missing kit capability is introduced.

## Verification

JavaScript syntax and whitespace checks are run locally. Browser review covers all four compositions, both palettes, narrow previews, content omission, description expansion, local response changes and missing-destination feedback. These are browser mockups; no Flutter application tests are applicable.

## Implementation verification — 2026-09-17

- Flutter 3.47.2: formatting and full `flutter analyze --no-pub` pass.
- 46 focused checks pass across event card, compact description/response
  behavior, native-menu semantics, date/time conversion, event controller and
  Native control adoption. New cases cover rich-content expansion, preserving
  expansion during RSVP updates, resetting for another event, short/absent
  descriptions, 320px layouts at 2× text in both directions, and selected RSVP.
- `flutter build macos --debug --no-pub -t tool/event_card_review_main.dart`
  passes. The real EventCard was inspected in an isolated macOS app in dark/wide,
  light/320px and light/320px/2× text layouts; description expansion/collapse
  and local RSVP selection were exercised. No forum account writes were made.
- Native review used the fixture's UTC reader timezone; the saved fixture now
  sets the reader timezone to Europe/Madrid to reproduce the supplied clock
  values. Production timezone formatting remains unchanged and has focused
  regression coverage. The screenshot has no link destinations or channel ID,
  so this local fixture omits those actions rather than fabricating targets.
- Review bundle: `org.discourse.native.compactevents2baf`, isolated under `/tmp`.
  Strict signature verification and entitlement readback passed with only
  sandbox, JIT and network client/server entitlements. Source/copied kernel
  SHA-256: `419494890e2d8e5c51a43def1cf5da237751ac62d3f5f8e2f2ceebfb39fdbda7`.
  The app launched successfully through CUA. Mobile/RTL verification is widget
  coverage, not a physical-device run.
