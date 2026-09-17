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

These are design prototypes only. No application or UI kit code is changed.

Use the existing Native dialog, DInput, DTabs or DToggleGroup, DItem/DItemGroup, DAvatar, DButton and empty-state components when implementing a selected direction. Preserve the actual participant endpoint's authorization, response filtering, search, stale-request handling, loading/error states, 200-person result limit, recurring attendance indication and profile navigation. Regular controls remain 28px at desktop scale; layout should retain the kit's touch targets, scaling and keyboard behavior.

The HTML samples use neutral surfaces and the same soft blue accent as the event mockups. Production colors must come from DTokens and the forum theme.

## Verification — 2026-09-17

JavaScript syntax and whitespace checks pass. Browser interaction checks cover all three designs: username search, combining search and response filters, clearing and empty-state recovery, keyboard Home/End navigation, Done and reopen. Additional checks cover missing-name search, Escape dismissal and local profile feedback. All three dialogs remain within their 360px preview width without horizontal overflow. Visual review covers desktop Compact/Directory in dark, desktop Status rail in light, and narrow Compact/Status rail in light. No app changes or real participant/profile requests are made.
