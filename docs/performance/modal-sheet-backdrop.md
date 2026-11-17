# Modal sheet backdrop

This profile describes the earlier motion shared by all phone sheets.
Today navigation sheets apply depth to the previous page. Modal bottom sheets
slide over a stationary page with a scrim.

In the profiled version, a modal sheet receded the page beneath it. The page
scaled to 94%, took the scrim tint and rounded its corners, following the
sheet's route animation and any pull on the sheet. This covered `DSheet`,
`showDSheet` and the phone sheets of `DDropdownMenu` and `DPopover`, such
as the topic and post action menus.

## What was slow

The sheet route delivered that motion as a Flutter delegated transition. Flutter
applies one by giving the covered route's page a new parent while the covering
route's animation is away from dismissed, and by taking that parent away again
once it is dismissed. Each change moves the page's keyed subtree, and every
element that reads an inherited value rebuilds when it is re-activated. On the
phone shell the page is the whole shell. A topic actions sheet rebuilt about
4,600 widgets in the frame it started to open and about 4,500 in the frame it
finished closing.

Re-activation also detaches and re-attaches every render object in the page. The
press of the button that opened the sheet was reset there instead of easing back
from its pressed scale.

## What changed

`DDialogBackgroundHost` keeps the background mounted at the root of a route's
page. A dialog route whose previous route has a host with the same background
builder animates that host instead of delegating its transition. Routes without
a host keep the delegated transition. The app gives its home route a host with
`DSheet.routeBackground`, the builder sheets already used.

The host builds the same background, so the receding page has the same geometry
and pixels as before. While nothing covers the route, the background is built
with a dismissed animation and leaves the page as it was. A repaint boundary
keeps the page's own painting while only the background changes. The fill around
the receding page no longer takes hits, so a host left in place between sheets
passes on every tap its page leaves.

The trigger's press now eases back behind the sheet. While it does, the trigger
repaints in a page that is moving, and a popover in sheet mode used to rebuild
its sheet on every such frame to follow its anchor. A sheet rises from the foot
of the screen wherever its trigger is, so a popover in sheet mode no longer
reacts to its anchor moving.

## Measurements

Rebuilt elements were counted with `debugOnRebuildDirtyWidget` while the topic
actions sheet opened and closed over a topic in the phone shell fixture, on
Android and iOS.

| Frame | Before | After |
| --- | --- | --- |
| First frame of opening | 4,629 | 1,297 |
| Each later opening frame | 23 | 12 |
| Last frame of closing | 4,472 | 16 |

Timings come from `integration_test/topic_sheet_open_profile_test.dart` on the
Android 16 ARM64 emulator (1080 by 2400 pixels, 2.625 density, 60 Hz, Impeller
on OpenGL ES) with profile builds of baseline `7177446ed` and the change, four
alternating runs of each. The table gives the median of the 16 repeated opens
and closes of each version. UI time is a frame's build, layout and paint
duration.

| Topic actions sheet | Baseline | Change |
| --- | --- | --- |
| Opening, longest UI frame | 15.5 ms | 6.7 ms |
| Opening, UI time | 19.8 ms | 11.9 ms |
| Closing, longest UI frame | 15.8 ms | 5.2 ms |
| Closing, UI time | 21.9 ms | 8.8 ms |

The first sheet of a session goes from 24.0 to 5.5 ms for its longest opening
frame and from 16.7 to 5.1 ms for its longest closing frame.

Raster time per frame over the first 360 ms of each action moved by no more
than it does between runs. It went from 104.0 to 77.1 ms for opening and from
98.4 to 105.2 ms for closing, against 69.4 to 71.3 ms for opening a topic and
71.0 to 75.8 ms for swiping one away, which this change does not touch. The
emulator takes 70 to 105 ms to rasterize a frame here, so these figures say
nothing about a phone's GPU. An opening now draws two more frames at its end,
while the trigger's press eases back.

Opening, going back from and swiping away a topic are unchanged.

## Measured but not changed

`RouteAwareSelectionArea` swaps its `SelectionArea` for a disabled container
while its route is covered. The swap moves each visible post's content, about
150 of the remaining rebuilds when a sheet opens and again when it starts to
close. Keeping the area mounted would avoid them, but it changes when a
selection and the area's focus history are dropped. Most of the other
remaining rebuilds came from the reader and the page frame depending on their
route's status, and from navigation; see
[Phone navigation rebuilds](phone-navigation-rebuilds.md).

The first topic opened in a session costs more than later ones. In the harness
its first frame lands about 90 ms after the tap instead of about 26 ms, and it
takes about 8 ms more UI work in its first 400 ms. CPU samples put that in first-time
allocation and in the first frames rather than in repeated work. The phone bar
also takes its one peek of the session about a second after that open
(`DMobileDock.peekFor`), which keeps frames coming for about 3.4 seconds.

## Reproduce

From `profiles/full`, build the harness once per version and replay it:

```sh
flutter build apk --profile --no-pub \
  -t integration_test/topic_sheet_open_profile_test.dart
flutter drive --profile -d emulator-5554 --no-pub --no-dds \
  --use-application-binary build/app/outputs/flutter-apk/app-profile.apk \
  --driver ../../integration_test/performance_driver.dart \
  --target integration_test/topic_sheet_open_profile_test.dart
```

From the repository root, compare saved reports:

```sh
python3 tool/profile_topic_sheet.py \
  --baseline baseline-1.json baseline-2.json \
  --candidate change-1.json change-2.json
```

For CPU samples, add `--dart-flags=--sample-buffer-duration=180` to the drive
command and set `PROFILE_COMPOSER_EXTERNAL_CPU=1`. The larger buffer keeps the
whole run, so the samples are read once at the end and not while the harness is
measuring.

## Verification

`test/ui/d_dialog_background_host_test.dart` renders a page beneath a sheet with
and without a host and compares their frames while the sheet opens, rests, is
pulled and closes, and the page's bounds when the sheet's route is removed. It
checks that a hosted page is not rebuilt, that its uncovered margin shows the
tinted well, that an uncovered host passes taps on, and that a sheet menu is not
rebuilt while its trigger settles.
