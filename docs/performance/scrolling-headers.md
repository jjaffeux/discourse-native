# Scroll-retracting topic headers

Topic reader headers and the topic-list heading/filter controls retract after
12 logical pixels of downward user scrolling and reveal after 6 pixels upward.
Each pane owns its state. The existing Native `DCollapsibleContent` animates
height over 200 ms with `easeInOutCubic`, retains the header's state, and respects
reduced motion. The viewport stays mounted throughout.

Programmatic restoration, nested/horizontal scrolling and elastic rebound do
not trigger retraction. Focused header controls stay visible. Pages with less
than a header's height of overflow keep their controls reachable. Changing the
topic or feed resets the header to visible.

Verification (2026-09-19, installed Flutter 3.47.4; project pin unchanged):

- Static analysis: no issues.
- Nine focused widget tests pass: animated reversal, wheel accumulation, touch
  drag, reduced motion, short content, focus retention, independent production
  topic/list panes, programmatic scroll restoration and active title editing.
- Broader topic inbox, navigation, rebuild and scrolling-performance tests:
  140 passed, 13 failed. All 13 failures reproduced on unchanged base main
  (`73f5696fc`) in a separate checkout; no new failures.
- Native macOS local-data preview (`tool/topic_page_review_main.dart`): checked
  topic hide/reveal, independent list hide/reveal, light split layout, and dark
  650-pixel narrow layout. Hidden controls leave native accessibility output and
  return when revealed. Preview used an isolated ad-hoc bundle with restricted
  identity/push entitlements omitted; the app's signing files were unchanged.
- No physical iOS or Android device testing performed.
