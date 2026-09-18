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

## Topic activity area

The reader header now includes up to four participant avatars above replies,
views, likes, links, estimated reading time and available last-activity metadata.
Reading time uses the site's words-per-minute setting and the existing
four-seconds-per-post estimate. Statistics wrap on narrow layouts. This area
retracts together with the title and taxonomy, including when opening mid-topic.
The viewport separator is always painted and follows the reading lane's text
insets, instead of appearing only after scrolling across the full pane.

Verified the production local-data macOS preview in light split and dark narrow
layouts, including scrolling down/up and hidden/revealed header accessibility.
Regression coverage checks stats, avatar stacking, separator geometry, retained
scrolling behavior, loading metadata and title editing. Existing unrelated inbox
failures documented above remain outside this change.

## Full-width topic panels

The topic header, activity area and post viewport follow the resizable panel's
width without the former 825-pixel cap or desktop alignment margins. Measurements
from the rendered local mockup at `http://localhost:5183/` show 16-pixel horizontal
header/post padding and a further 39-pixel leading inset for the post body.
The topic separator shares the 16-pixel insets. These fixed layout insets do not
scale into a wider centered reading column when app text zoom changes.

Geometry and interaction checks pass at 1200/2000-pixel desktop widths, 100/150%
text settings, and narrow/enlarged-text layouts. Static analysis is clean. Broad
inbox/rebuild checks retain existing unrelated failures, including the post-action
spacing expectation reproduced on main.
A clean native macOS fixture build was visually checked in a maximized light
window (topic content wider than 825 pixels) and the dark 650-pixel layout.
