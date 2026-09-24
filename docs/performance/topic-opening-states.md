# Topic opening states — September 24

Opening a topic from its list drew the reader in several different layouts
before it settled. Nothing was slow in any single frame. The reader looked
unstable because its header, body and footer changed shape as data arrived.
This note records what the sequence was, what now happens instead, and how the
work in each frame changed.

## The sequence before

`tool/render_topic_opening_test.dart` opens a topic from a desktop inbox
(1440 × 900, Open Sans, Discourse's default dark scheme) with its request held
by a gate. It writes a PNG for every frame whose pixels change. Before this
change, for a one-post topic in the `sysadmin` category with a
`maintenance` tag and the Assign plugin:

1. **Loading.** The header drew the list row's metadata: a disabled category
   chip, the tag, and statistics computed from the row (“0 views”, because the
   row's views were not passed on). There was no wrench and no footer. The body
   skeleton was `#282828` on a `#222222` page.
2. **First content frame.** The wrench appeared. The category chip gained its
   chevron; “+ Subcategory”, the tag pencil and “Assign topic” were inserted
   between and after the existing chips; Assign's regular-size button grew the
   row by 4 px. The avatar row appeared and pushed the statistics down 39 px.
   The statistics changed. The footer appeared and shortened the body. The
   header was remounted, because the loading and loaded headers were different
   widget trees.
3. **Next frame.** The whole reader rebuilt to turn the scroll cache back on.
4. **Next frames.** For a topic opened at an unread post, the floating date
   and then the “6 / 12” progress control appeared, one frame each.

The skeleton was nearly invisible on dark palettes. Its fill was the UI kit's
`muted`, which a forum palette maps to `--primary-very-low`. The 17 September
fix moved light pages to the border neutral and left dark pages on `muted`.

## What happens now

The loading reader is the loaded reader with placeholders:

- The title and the closed lock come from the route or the cached list row;
  both render identically once loaded. The wrench and the footer's Reply,
  bookmark and notification controls are drawn disabled in their final place.
- The taxonomy and activity rows are placeholders at their loaded heights. The
  desktop taxonomy row is always as tall as a regular control, so Assign
  cannot grow it. The activity placeholder sizes each bar from invisible text
  built with the row's counts, so it wraps where the loaded statistics will.
- The skeleton occupies the post stream's exact frame, under the same scroll
  separator. It stays transparent for 150 ms: a prefetched or fast topic never
  flashes it.
- The header is keyed by site, topic, tab and account session instead of the
  scroll controller, which only exists once the topic arrives. The loading and
  loaded headers are therefore the same element, and the topic fills it in
  place.
- Dark pages mix 18 % of the text colour into the page for the skeleton.
- Warming the scroll cache rebuilds only the scroll view. The footer's
  progress control listens alone, so a reading-position change no longer
  rebuilds Reply, bookmark and notifications.

The floating date and the progress control still appear one frame after the
posts: both are resolved from layout.

## Frame work

The harness logs each pump's component elements mounted and rebuilt. These
are debug-mode counts from the test binding at `1af3d9132` (baseline) and with
this change, for the two fixture topics on Discourse's dark scheme:

| Frame | One post: before | One post: after | Unread at post 6: before | Unread at post 6: after |
| --- | ---: | ---: | ---: | ---: |
| Loading | 2558 mounted | 2686 mounted | 2574 mounted | 2702 mounted |
| Content | 1020 + 627 | 971 + 675 | 1888 + 643 | 1839 + 691 |
| Content + 1 | 676 rebuilt | 60 rebuilt | 870 + 733 | 870 + 98 |
| Content + 2 | 145 rebuilt | 1 rebuilt | 48 + 163 | 48 + 19 |

Cells read mounted + rebuilt. The loading frame mounts about 130 more elements,
because it now draws the footer and placeholder rows. The content frame does
the same total work: the header's rows are rebuilt in place instead of
remounted, and posts dominate either way. The two frames after it lose most of
their work. The reader's full rebuild for the scroll cache is gone, and so is
the footer rebuild when the progress control appears. Across the three frames
from content onward, builds fall from 2468 to 1707 for the single post and from
4345 to 3565 for the unread topic.

No profile-mode capture was taken for this change. The
[surface-opening harness](surface-opening.md) remains the way to measure
native frame times.

## Skeleton contrast

At the pulse's half-opacity trough, the old `muted` fill reached a WCAG
contrast of 1.02–1.05 against the page on every dark palette: the app's own
dark theme, Discourse's default dark scheme, and the dark variant of every
built-in forum preset. The new fill reaches 1.18–1.30 there (1.39–1.77 at
full opacity). Light pages are unchanged at 1.09–1.15. `topic_skeleton_test`
pins a 1.08 floor across all of these palettes; the old dark fill fails it.
That fill now belongs to every loading surface as `skeletonFill`, and the
floor moved with it to `skeleton_fill_test`.

## Reproducing

```sh
TOPIC_OPENING_OUT=/tmp/topic-opening \
  flutter test tool/render_topic_opening_test.dart
```

Each scenario and palette gets a directory of PNGs and an `index.txt` listing
every pump: component elements mounted and rebuilt, the most rebuilt widget
types, wall time, and whether pixels changed. These are debug-mode costs from
the test binding. Compare two builds of the same fixture; do not read them as
frame times.

## Verification

- `topic_inbox_test` “a loading reader reserves its loaded rows …” opens a
  topic behind a gate at 1100 px with and without Assign, and at 600 px. It
  checks the header element is retained and the rects are identical in the
  loading and first content frames: the toolbar, the closed lock, the taxonomy
  and activity rows, the scroll separator and the footer. It also checks no
  permission-dependent control is enabled early.
- “loading placeholders follow navigation and a failed load” covers topic
  switches, an uncached route, and the error state, which draws no
  placeholders.
- `topic_skeleton_test` checks every palette's trough contrast and the grace
  period's opacity, ticker and semantics.
- Two `coherent_initial_render_test` cases now pump once more after the load
  resolves. They had passed only because the old skeleton's endless pulse kept
  a frame scheduled.
- `flutter analyze` is clean for the application, the Voice package and the
  full profile, and every changed file is formatted.
- The full suite ran on an unchanged checkout and with this change. The only
  failures unique to this change's run are a `mobile_shell_test` chat case,
  which fails identically on the unchanged `1af3d9132` this change sits on.
  Two tests hang locally on both trees (a Chat scroll performance fixture and a
  diagnostics panel resize) and were stopped. The topic, panel, tab and mobile
  suites show the same 54 pre-existing failures on `1af3d9132` with and without
  this change.
