# Mobile navigation concept

Open `index.html` directly, or serve this directory with a local HTTP server.
HTML and CSS define the mockup; dependency-free JavaScript demonstrates the
navigation. All content and state are local sample data.

## Proposed behavior

- No desktop top-level tabs. One visible destination at a time.
- Bottom navigation: Home, Chat, Voice, Settings in an inset, rounded
  icon bar, with a short top marker for the active mode, matching the reference.
  Accessible names remain available for every icon.
- Home exposes the instance rail beside the default forum sidebar.
- Chat and Voice expose their corresponding sidebar without the rail. Home
  contains the forum sidebar; there is no separate Forum tab.
- Every content destination (topic lists, topics, channels, Users, and voice
  rooms) fills the available screen between the system safe areas. The forum
  header and bottom bar are hidden. Back and swipe navigation restore them
  when returning to a sidebar. Back remains visible while scrolling content.
- Users opens a full-page member directory. Filter is removed from the sidebar.
- Upcoming events represents the calendar; the entry is disabled because the
  calendar is outside this mockup’s scope. It does not open a topic list.
- Chat uses Channels and DMs tabs at the top of its container, with separate
  unread counts and flat lists. The selected tab is retained when returning
  from a conversation. Arrow keys, Home, and End navigate these tabs.
- The logo opens the desktop forum actions: Open forum in browser, Settings,
  and Remove forum. The rail switches instances and returns to Home.
- The header includes a notification bell beside Search and Profile.
- Search is an icon button that opens a bottom sheet. Sample topic results
  filter by title, category, or author, and open in the reader.
- Settings opens a bottom sheet with Appearance; light/dark choices update
  the preview immediately.
- Horizontal swipes traverse navigation history: right goes back, left goes
  forward. Vertical scrolling remains available. The study's Back/Forward
  controls and Alt+Left/Right provide equivalent desktop interactions.

The current application exposes Forum, Chat, and Voice sidebar panels; real
implementation should preserve their existing availability checks. Home is a
proposed mobile entry point. Settings is a sheet action, not a content mode.

## Scope

This is a design artifact, not Flutter application code. Supporting destinations
reuse sample content to illustrate navigation. Chat sends, drafts, added
communities, likes, and voice-room states exist only in memory. There is no
network integration, microphone access, or persistence across reloads.

Production implementation must use `package:discourse_native/discourse_ui.dart`
and the project's Native components. Candidate existing owners are DSidebar,
DTabs, DButton, DSheet, DDropdownMenu, DInput, and DAvatar. Their suitability
for the proposed mobile composition, touch behavior, safe areas, and gestures
must be assessed before implementation; this mockup does not extend the kit.

## Verification

Checked JavaScript syntax and the rendered local preview in the Codex browser:
Home at 320 px, dark/light appearance, Home → topics → topic → back → forward, horizontal
drag gestures in both directions, search filtering, rail instance switching,
Chat channel navigation, and Voice room listing. No JavaScript errors were
reported during those interactions. This is browser verification, not device
or Flutter testing.

After the full-screen revision, checked that Users, topic lists, topic readers,
chat channels, and voice rooms hide the forum header and bottom bar. Returning
to Home or the Chat sidebar restores navigation, including the Channels/DMs
tabs. The Upcoming events entry is disabled and Filter and Forum are absent.

The September 20 revision adds the notification bell and changes the logo to
the desktop forum actions. Production Flutter implementation and current
verification are described in `../../mobile-navigation-architecture.md`.
