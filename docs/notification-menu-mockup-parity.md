# Notification menu parity

Reference: `discourse-native-mockups/src/App.tsx`, `NotificationsMenu`,
`BarMenu`, `MenuTab`, `BarMenuRow`, and `BarMenuMark`; `src/app.css`,
the `glass-inset` rules. The 2026-10-14 screenshot shows the same composition.

Desktop and mobile share a fixed title/action and horizontal filter strip
above an independently scrolling feed. Desktop uses an anchored dropdown:
400px, or 320px in narrow windows. The popup respects the viewport with a
640px height cap, 12px side margin, 6px bottom margin, 12px corners, and 8px
trigger offset. Physical safe areas and keyboard insets constrain the viewport.
On mobile platforms, the header bell opens the Native adaptive bottom sheet.
Long feeds open at 55% of the screen height and expand with an upward pull;
the title and filters stay fixed while the feed scrolls. The sheet owns safe
areas, keyboard placement, backdrop dismissal, and downward swipe dismissal.
The unexpanded sheet keeps its opening width when filters change, including
short and empty feeds. It disables the Native sheet's `floatOnContentEnd`
option; explicit expansion and keyboard placement still add floating margins.

The Native kit owns the new `DToggleDensity.menuFilter`,
`DButtonDensity.menuAction`, and `DMenuFeedRow` artwork and interaction.
Inactive filters retain a black 16% dark / 4.5% light recessed fill in both
materials, a transparent outer border, the shared inset shadow and rim, and
the palette's 62% text mix. Hover uses white 5% dark / black 7% light. Filters
have 26px base artwork, grow with text, scroll under a directional 28px fade,
and retain the kit's keyboard focus and exact visible hit bounds.

Selected filters in both appearance modes reuse the existing Native writing
capsule's accent tint (76% opacity), radial highlight, 1px rim and inset edge lighting.
This keeps the reference's glass appearance inside the overflow mask without
putting a live refraction shader into that mask's offscreen pass.
The strip's 12px side and 8px/10px vertical padding belongs inside the scroll
viewport, so the soft shadow can extend beyond each pill without being cut
at its corners. The buttons retain their 26px base activation bounds.
The panel mixes raw foreground 3% into the canvas; row actions/read subjects
use 50%, unread subjects 90%, and times 40%, including Solarized palettes.
Collapsed server reply labels and `consolidated_count` use the reply glyph.

Rows have 8px/9px insets, a 30px avatar or glyph, 10px content gaps, a 13px
headline, and a 12.5px subject separated by 1px. Time and the unread dot share
the trailing column. Actors stay bold, read subjects recede, and accessible
text reflows. Actor names and avatar templates come from the server envelope;
type owners supply structured action/subject copy without losing the complete
notification description or their navigation routes.

The All count uses grouped unread counts when available, so marking the bell
seen does not clear it. Messages filters its typed notification feed in the
menu, using the existing session-owned cache and reconciliation machinery.
Bookmarks shows reminder notifications in this menu; the bookmarks page and
standalone bookmark section retain their own content. Bulk-read failure leaves
the menu and unread state available for retry. Contributed notification types
keep their decoder, dismissal, and active-tab navigation contracts.

`test/notification_menu_mockup_parity_test.dart` measures popup, filter, avatar,
row, and time/dot geometry, checks the recessed fill/rim/text recipe across
desktop/mobile, light/dark and Standard/Liquid Glass, verifies a message filter
and bulk-read retry, and checks fixed headers in short viewports. Set
`NOTIFICATION_PARITY_CAPTURES` to export rendered PNGs. Mobile tests also check
iOS/Android, RTL, 200% text, horizontal navigation, live counts, sheet
expansion, swipe/backdrop dismissal, and reopening.
Focused notification navigation, account-session, bookmark, profile-menu, and
Native control suites cover the affected integration contracts.

`integration_test/notification_filter_rendering_test.dart` runs the filter
paint regression on iOS: both ends of a selected pill must retain accent fill
before and after scrolling, and its blurred shadow must extend below the
button without accepting taps. Captures enable real shadow blur; Flutter's
default test setting otherwise produces hard offset blocks at the corners.
The previous live shader fails the pill-fill check under
Impeller. The shared capsule passes in light/dark Standard and Liquid Glass.
Use `--dart-define=NOTIFICATION_FILTER_CAPTURE_DIR=/path` to save PNGs.

Initial menu validation: 362 tests pass across 17 focused files. The remaining button suite
passes 73 tests and has one existing dock assertion expecting 44px instead of
50px; that failure reproduces on unchanged `main` at `f4569a004`. The patch does
not change dock artwork. Focused static analysis is clean.

The glass/color follow-up passes 83 focused checks, including the four native
iOS rendering cases and the desktop/mobile color matrix. Static analysis is
clean for the changed files.

The corner/shadow follow-up passes 59 focused checks, including native iOS
pixel checks for a smooth corner transition, an outer shadow below the pill,
and no button activation when tapping that shadow. Static analysis is clean.
