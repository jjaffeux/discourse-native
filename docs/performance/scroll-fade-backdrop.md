# Scroll fade backdrop

Every vertical list fades its content out at the edges where more content
continues, under a floating header and above the phone's bar. The fade masks
the viewport, so the GPU renders the whole viewport into an offscreen layer and
composites it back in every frame that the list or anything around it moves.
On a phone that layer is most of the raster time of opening a topic, swiping it
away and opening a menu sheet.

## What was slow

Raster thread events were recorded with `integration_test/topic_sheet_open_profile_test.dart`
built with `--dart-define=PROFILE_TIMELINE=true` on a Galaxy S24 (SM-S921B,
Exynos 2400, Android 16, 120 Hz). While a topic was swiped away, each frame
encoded about 6.5 save layers, and time inside them was about 7.7 ms of each
frame's 9.6 ms of encoding. Glyph atlas work was about 0.2 ms per frame.

A layer dump in the middle of the swipe found five offscreen layers. Three
covered a whole page: the receding list's tint and the shader masks of the
list's and the reader's edge fades. The other two were small chrome fades.

Two diagnostic builds told the costs apart. They are compared with the
unchanged build, two alternating runs of each, as the median of the repeated
actions.

| Raster per action | Unchanged | Without edge fades | Without the tint |
| --- | --- | --- | --- |
| Opening a topic | 320 ms | 174 ms | 321 ms |
| Opening a menu sheet | 390 ms | 233 ms | 399 ms |
| Closing a menu sheet | 205 ms | 109 ms | 196 ms |
| Swiping a topic away | 567 ms | 363 ms | 526 ms |

The tint costs nothing measurable: the engine applies a color filter without
an offscreen layer. The edge fades cost about 45% of raster.

## What changed

`DScrollFadeScope.backdrop` names the opaque color painted behind the first
viewport below the scope. With it, the fade paints the content and then covers
its edges with that color by the complement of the mask, which is the same
arithmetic as masking the content over that color, and needs no offscreen
layer. A translucent backdrop keeps the mask.

`DPageSurface.scrollBackdrop` passes that color to its viewport's scope. On a
phone the topic reader and the topic list pass the panel color their sheet and
surface paint. A forum whose panels are translucent over its background keeps
the mask.

## Pixels

`test/ui/d_scroll_fade_backdrop_test.dart` renders a scrolled list with both
edge fades and the phone bar's foot fade, masked and covered, and finds no
channel more than 3 apart, from rounding the two orders of blending.

The phone shell was rendered with the old and the new fades, in light and dark,
with the reader scrolled, the list scrolled and at its top, and a topic half
swiped away. Most pixels match within 2. The rest are antialiased edges: a
few pixels where a rounded corner meets the header, where the old mask let the
corner's background show and the cover paints the panel color, and a one-pixel
column at the edge of each text line, where the test renderer antialiases text
differently inside an offscreen layer.

## Measurements

On the Galaxy S24, with profile builds of the unchanged `main` and the change,
two alternating runs of each, as the median of the repeated actions. Raster per
frame leaves out each action's first frame. A late frame missed the 8.3 ms
budget of 120 Hz.

| Action | Raster per frame | Raster per action | Late frames | Frames drawn |
| --- | --- | --- | --- | --- |
| Opening a topic | 14.1 to 3.8 ms | 319 to 173 ms | 22 to 12 | 22 to 36 |
| Opening a menu sheet | 8.8 to 3.2 ms | 387 to 236 ms | 28.5 to 9.5 | 47 to 60 |
| Closing a menu sheet | 11.1 to 4.3 ms | 199 to 111 ms | 17.5 to 5.5 | 20 to 24 |
| Swiping a topic away | 6.9 to 4.3 ms | 562 to 392 ms | 30 to 24 | 56.5 to 82.5 |
| Going back | 2.7 to 2.9 ms | 103 to 81 ms | 1.5 to 1.5 | 27 to 28 |

More frames are drawn in the same time because fewer are dropped. The first
frame of opening a topic still takes about 28 ms of UI time on this phone,
building the reader, and a swipe still drops about a third of its frames.

## Reproduce

The profiling build installs as its own package so it does not replace an
installed app. From the repository root:

```sh
python3 tool/profile_topic_sheet.py \
  --baseline baseline-1.json baseline-2.json \
  --candidate change-1.json change-2.json
```

Build the harness from `profiles/full` with `flutter build apk --profile`,
temporarily giving the profile build type an `applicationIdSuffix` and its
package a client in `google-services.json`, and replay it with
`flutter drive --use-application-binary` as in
[Modal sheet backdrop](modal-sheet-backdrop.md#reproduce). Keep the phone
unlocked and awake; a dozing screen draws at 30 Hz.
