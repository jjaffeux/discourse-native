# Notification dot

User-approved Native extension (2026-09-13), registered in the application
styleguide catalogue without modifying the frozen upstream catalogue.

Import `package:discourse_native/discourse_ui.dart`.

```dart
const DNotificationDot(semanticLabel: 'Unread messages');

DNotificationDot.overlay(
  ringColor: headerSurface,
  // The enclosing button already announces unread activity.
);
```

The inline form has an 8px colored center. The overlay form adds a 2px ring
within a 12px footprint, leaving the same 8px center. Both keep a fixed size
at large text scales. `color` defaults to the live primary token; overlay
`ringColor` defaults to the live background token. Supply the surrounding
header or rail surface when it differs from the background.

Visibility and positioning belong to callers. The dot has no focus or action
and ignores pointer events so it cannot block an underlying button. Supply
`semanticLabel` for a standalone state; omit it when an enclosing control
already announces unread activity. Use directional positioning for overlays.

## Adoption

- Chat header: replaces the custom 18px unread indicator with a 12px ringed
  dot, preserving its visual center and mirroring the corner in RTL.
- Chat drawer: unread channel indicators; urgent numeric badges stay numeric.
- Chat My Threads and channel thread lists: shared 8px unread dots.
- Chat pinned messages: shared 8px indicator with the ordinary chat activity
  accent and an accessible unseen-pins label.
- Forum sidebar and tabs: shared 8px dots, retaining ordinary unread and
  urgent mention colors and existing labels.
- Topic lists/inbox: `TopicStateDot` retains its tooltip and state label while
  delegating rendering to the kit.
- Update rail button: shared ringed notification dot with the rail surface.

Retained alternatives: notification counts (`DBadge` and header capsules), avatar presence/flair (`DAvatarBadge`), category identity markers,
diagnostics/voice recording status, calendar event markers, carousel/page
positions, and rail drag-insertion markers. These indicate identity, an ongoing
state, position, or a count rather than unread/new activity.

## Review

The Notification dot styleguide page includes inline states, an interactive
header that clears/restores unread activity, and custom surface rings. Use the
standard theme, viewport, text scale, and direction controls.

`tool/notification_dot_review_main.dart` mounts the production shell with a
local unread channel plus the real styleguide. Its controls select light/dark,
a site palette, wide/narrow layout, and LTR/RTL. Stores and transport are fakes;
it does not read or mutate the user's forum accounts.

Verification and independent review/merge evidence are recorded in the
`notification-dot` row of `progress.json`.

## Counts and core colors

The user selected combined capsules on 2026-09-13. Both numeric header controls
now compose the existing `DButton` and `DSeparator`: icon, divider and capped
count share one pill. Ordinary unread chat keeps its small dot. See
[the source audit](notification-colors.md) for exact color roles and count policy.

`tool/notification_capsule_review_main.dart` mounts the real shell with 128 urgent
chat items and 128 ordinary notifications, with light/dark, site palette,
390px width, 200% text and RTL controls. It uses only local fixtures.
