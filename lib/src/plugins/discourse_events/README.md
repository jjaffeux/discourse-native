# Post events

This module owns the native client for `plugins/discourse-events`. Its owner
is `discourse-events`; the server intentionally retains the older
`/discourse-post-event/` URL and message-bus namespace.

Native surfaces include post cards and authorized event oneboxes, current
occurrence and recurring RSVP, public withdrawal, participant search, organizer
invitations, event authoring, topic dates, reminders and invitations, Upcoming
and My Events, calendar export, event images, and links to event Chat and
livestreams. The module installs without Poll, Local Dates, Chat, or video
plugins. Unknown/missing event data leaves a readable cooked fallback.

The event menu links to the web for bulk invitations and reports. Upcoming-event
calendar grids and provider-specific livestream/Zoom interfaces also retain web
entry points. Category calendars and group timezones are separate server
features and are outside this module's scope.

## Topic calendars

The first post's dynamic `[calendar]` block renders with
[Kalender](https://pub.dev/packages/kalender), pinned to `0.29.1`:

```markdown
[calendar weekends=true tzPicker="true" showAddToCalendar="false" fullDay="true"]
[/calendar]
```

Add entries by replying with a local date or date range, using the existing
date/time composer action or raw syntax such as:

```markdown
Away
[date-range from=2026-09-07 to=2026-09-10 timezone="Europe/Paris"]
```

Discourse extracts the reply's dates and returns the complete `calendar_details`
list on the first post. The native renderer uses that list, so entries do not
depend on which replies have been loaded. Calendar processing is asynchronous;
the server's `calendar_change` message refreshes the topic through core's
existing invalidation hook. Deletion/recovery messages also refresh it. No
calendar write endpoint or client-side reply scanner is introduced.

Kalender owns the month, week, day, and agenda layouts, navigation, range
clipping, and overlap placement. The plugin supplies the toolbar, colored
event tiles, direct reply navigation, and a day list for crowded cells. It
honors `fullDay`, `defaultTimezone`, and the site's
`calendar_first_day_of_week`. Full-day end dates are inclusive and retain the
author's timezone date; the adapter supplies exclusive local-midnight endpoints
to Kalender, including across 23/25-hour days. Timed events use the selected
reader zone. Weekly `1.weeks` entries expand only for the displayed window and
neighboring pages, retaining wall times across DST. Calendar timezone selection
does not change account preferences. Creation, dragging, and resizing are
disabled: replies remain the source of calendar entries.
Grouped holiday rows remain readable with their participant names, and a
configured holiday topic uses usernames for its standalone entries.

The current upstream cooker no longer serializes `tzPicker`; native calendars
always offer a timezone selector. Kalender's month view has seven fixed weekday
columns; `weekends=false` and nonempty `hiddenDays` retain an explicit web
fallback. **Open web calendar** also covers year views, static blocks, calendar
subscriptions, and add-to-calendar exports. There is no native export button,
including when `showAddToCalendar="false"`. Quoted calendars and cooked fragments
without the first post's data retain a readable fallback. Review Kalender's
pre-1.0 API changes and rerun the adapter/widget tests before upgrading it.

`TopicCalendarPlugin` owns a separate post record and settings codec under the
existing events module. Calendar rendering works without the post-event RSVP
setting and without installing Local Dates, Poll, or Chat. Date authoring still
uses the existing Local Dates composer when that module is installed.

The source contract was checked against Discourse `2e9dc47bd88`: the post
serializer in `plugins/discourse-events/plugin.rb`,
`app/models/discourse_events/calendar/event.rb`, the calendar Markdown rule,
and `post-calendar.gjs`. The calendar cooker, decorator and component are
included in the module's markup drift snapshots.

## Ownership and data flow

- Core stores opaque `PluginData` on posts, topics, settings, and users. Every
  event key, wire field, endpoint, notification decoder, and permission rule
  lives here. Post and topic codecs are separate capabilities with the same
  owner.
- Core supplies generic request leases, a post write lane, topic reload,
  timezone reads, navigation, text downloads, and a guarded post-editor entry
  point. The composer supplies whether it creates a topic and the edited post
  number. Syntax actions receive their registered owner's service scope.
- `EventController` shares a record/subscription by `(site, event ID)`. The event
  ID is the owning **post** ID, distinct from the topic ID. A linked card never
  writes against its containing post. Post payloads seed presentation; the
  event endpoint hydrates current account authority. Later post snapshots
  invalidate the hydrated record instead of replacing it.
- Writes are serialized through core's post lane and guarded by a site lease.
  Request generations discard stale reads; live echoes coalesce into a reread.
  Responses, including ambiguous write failures, are reconciled from the event
  endpoint. Topic reload lets the server's Watching/Tracking and Chat effects
  reach their owners. Private attendance never supplies a synthetic default.
- Subscription ownership is reference counted. Backgrounding, tracker
  replacement, unmount, site forget, and session close have explicit cleanup.

## Authoring and time

`EventBlock` retains original source spans and changes only edited attributes
or description text. Future attributes, custom fields, images, quotation style
on untouched attributes, and the original recurrence anchor survive an edit.
Code examples and quoted blocks remain raw. The editor is available for a new
topic (including a private message) or its first post, with freshly loaded
creation permission. Close/reopen and removal edit the block; saving uses the
ordinary post composer. No event create/update endpoint is invented, and direct
event deletion does not leave stale raw markup behind.

All-day dates retain their calendar day. Offset timestamps are instants;
offset-free wall times require the declared event timezone. The host supplies
the reader's account/device timezone without allowing the plugin to mutate the
shared environment. Closed/expired/capacity state comes from the server.

The directory expands the server's occurrence list and caps the view at 200
occurrences. Future cards do not borrow current attendance or offer occurrence
specific RSVP. Calendar export downloads the authenticated server ICS snapshot
and shares/saves a file; it never exports an API-key-bearing URL. Server feed
windows and occurrence limits still apply.

## Verification

The `event_*` tests cover decoding and privacy, raw editing, timezone and DST
behavior, endpoint payloads, concurrency and account lifecycle, narrow/wide UI,
and calendar downloads. `discourse_events_plugin_test.dart` exercises standalone
installation, core-only decoding, notifications, host routing, quoted markup,
and linked-card write identity. Generic text transport tests verify same-origin
authentication, subfolder paths, UTF-8, and response bounds.

`test/src/plugins/discourse_events/topic_calendar*_test.dart` covers the topic
calendar's data contract, inclusive ranges, timezone/DST behavior, recurrence,
Kalender view changes and range clipping, overflow day lists, narrow layouts
with large text, live invalidation, cooked-wrapper rendering, and navigation to
unloaded replies.

`tool/markup_contract.json` owns upstream Markdown/decorator snapshots from
Discourse `2e9dc47bd88`. The generic markup drift runner discovers this catalog.
The companion investigation in `docs/post-events-investigation.md` records the
server contracts, permission behavior, and current server inconsistencies.
