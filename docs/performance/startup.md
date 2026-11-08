# Application startup

Measured on November 8, 2026 on an M5 Pro Mac with `tool/profile_startup.py`.
A launch was timed from the kernel creating the process, on a profile build of
the production bootstrap, against six seeded forums served from a second
isolate with a 60 ms response latency.

## Where the time goes

Median cold start, restoring a saved workspace, before these changes:

| Milestone | ms since exec |
| --- | --- |
| Dart `main` runs | 222 |
| First Flutter frame on screen | 238 |
| Local state restored | 254 |
| Shell on screen | 277 |
| First feed request reaches the server (last run) | 332 |
| First feed page on screen | 400 |

More than half of a launch passes before Dart runs. A Time Profiler trace of
that window (`xctrace --launch`, warm) is AppKit building the window from the
nib, dyld, and the engine creating the isolate from its snapshot. No single
application-owned item stood out, so nothing there was changed.

## Holding a connection slot for the feed

`_activateInstanceWorkspace` warms site metadata before it requests the first
feed. Those reads filled the four per-origin slots, so the feed request queued
for a whole round trip: `/latest.json` reached the server 63 ms after the first
batch, the fake forum's response latency, and interactive priority cannot help
once slots are already held. `OriginRequestGate.interactiveSlotsPerOrigin` now
keeps one slot of the Discourse API lane away from background work.

| Median of 11 alternating cold starts | before | after |
| --- | --- | --- |
| First feed page on screen | 483.6 ms [454-680] | 424.9 ms [380-638] |
| Feed request to feed response | 128.4 ms | 66.0 ms |

The machine was shared with other builds during this run, which is why these
are later than the table above; the sides alternate, so the drift lands on
both. The saving equals one response latency, so it grows with real network
latency. `/latest.json` now arrives in the first batch.

## Not starting the cooking engine at launch

Every launch spawned the cooking isolate and evaluated its 2.4 MB JavaScript
bundle. Only chat's optimistic messages, AI summaries and user notes use it,
and `CookingHostService` starts it on first use.

| Median of 11 alternating cold starts | before | after |
| --- | --- | --- |
| Process CPU before the first feed is shown | 407.6 ms [381-499] | 269.2 ms [246-305] |
| Process CPU, first four seconds after it | 636.0 ms [585-708] | 491.0 ms [442-546] |
| First feed page on screen | 419.7 ms [367-554] | 435.2 ms [363-649] |

The wall-clock column shows no measurable change on this machine, which has
idle cores for the isolate; the saving is CPU and battery. The first chat send
of a session now pays the engine's start on that background isolate.

## One less `/site.json`

`siteConfig` read `/site/settings.json` and then, afterwards, `/site.json` for
homepage options, too late to share the request a first activation had already
issued. Reading them together makes the launch fetch `/site.json` twice rather
than three times. First feed page: 365.1 ms vs 360.6 ms median of 9 alternating
first launches, so no measurable latency change.

## Checked and left alone

Holding the first frame until local state is ready would skip the placeholder
frame, but that frame costs about 9 ms of UI-thread work here, a fraction of a
launch's run-to-run spread. The two remaining `/site.json` requests differ by
`Accept` header and response limit; sharing them would loosen the appearance
loader's 2 MB bound, for one request.

## What was not measured

The numbers above are from macOS. An iPhone 15 Pro Max was not reachable when
these were recorded, so no device timings are recorded. The changes are all
shared Dart. On a phone the first launch screen differs: a freshly seeded
mobile profile opens the Start page and requests no feed, so its first feed
comes from a restored page or a forum the reader selects.

## Reproducing

Build `tool/startup_profile_main.dart` in profile mode once per side, with the
macOS Profile configuration signed to run locally (see
[pane-resizing.md](pane-resizing.md)) under a bundle id of its own so the run
neither reuses your Debug container nor your keychain:

```sh
flutter build macos --profile -t tool/startup_profile_main.dart
cp -R build/macos/Build/Products/Profile/Discourse.app /tmp/side.app
python3 tool/profile_startup.py --app base=/tmp/base.app --app side=/tmp/side.app \
  --runs 11 --output /tmp/startup.json
```

Add `--fresh` for first launches, `--device <udid> --bundle-id <id>` with a
device `.app` for an iPhone (with a local bundle id of its own, so the run
does not replace your daily install), and `--dump` for the VM timeline and Dart
CPU samples, which slow the launch and must not be reported as timings.
