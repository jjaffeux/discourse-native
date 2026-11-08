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

## On an iPhone

Measured on an iPhone 15 Pro Max running iOS 27.0.1, launched by `devicectl`,
restoring a saved topic list. Median cold start, 24 launches:

| Milestone | ms since exec |
| --- | --- |
| Dart `main` runs | 148 |
| Shell ready | 180 |
| First feed page ready | 261 |
| `sceneDidBecomeActive` | 460 |
| First frame on screen | 482 |

The first frame belongs to iOS. An app that only draws one `ColoredBox`, on
the same native path, gets its first frame at 483 ms against the full app's
481.5 ms, with `sceneDidBecomeActive` at 463 ms against 460 ms (16 launches
each). Dart builds its first frames well before that, and none reach the screen
until the scene is active, which is why the profile reports the same time for the
first, shell and feed rasters here. Nothing the app does in Dart can move that
frame. With this harness's 60 ms response the feed is ready before iOS shows
anything, so on a phone the work below only shows when the response takes
longer than that.

## Reading server credentials beside the first frame

`InstanceStore.load` awaits `HttpBasicAuthStore` before it reads preferences,
and that load began only after the first frame was built. The read goes through
the Keychain on the plugin's background queue, so `AppBootstrap` now starts it
before `runApp`, where it overlaps the first build at no cost to the main
thread. Release builds read this usually absent key through
`MigratingPrivateStorage`, which makes five sequential Keychain round trips
where a profile build makes one (counted from the code, not timed), so these
numbers understate a shipped launch.

| Alternating cold starts | before | after | p |
| --- | --- | --- | --- |
| iPhone, 20 each: local-state load | 11.6 ms [8-27] | 7.3 ms [3-11] | <0.0001 |
| iPhone, 20 each: feed request leaves | 182.5 ms | 176.9 ms | 0.001 |
| macOS, 45 each: local-state load | 13.2 ms [10-49] | 11.8 ms [4-27] | 0.007 |
| macOS, 45 each: first feed on screen | 412.6 ms | 408.8 ms | 0.98 |

macOS gains little and shows no end-to-end change. Why its gain is smaller than
the phone's was not established.

## Deferring WebRTC on iOS

`NativeVoiceSystemCall` called `LiveKitClient.initialize` from its constructor,
which builds the voice engine, audio device module and codec factories on every
launch. That took 58 to 72 ms and landed beside the first feed response.
Preparing now waits five seconds. Anything needing the audio session sooner
starts it, so a call placed in the first five seconds pays that cost as it
starts. It does not wait for a first call, because device pickers reach WebRTC
without passing through the system call. The work still runs after five
seconds, so the 1.5 MiB below is deferred rather than saved.

## Both changes together

On the merged tree, against the same tree with only these two changes reversed,
24 alternating launches per side on the iPhone:

| | before | after | p |
| --- | --- | --- | --- |
| Local-state load | 11.9 ms [8-15] | 5.9 ms [3-12] | <0.0001 |
| Feed request leaves | 180.5 ms | 174.1 ms | <0.0001 |
| First feed page ready | 261.4 ms [246-299] | 249.6 ms [238-275] | 0.0005 |
| Resident memory at the feed | 217.9 MiB | 216.4 MiB | <0.0001 |
| First frame on screen | 481.7 ms | 480.5 ms | 0.92 |
| Process CPU to the end of the run | 2,130 ms | 2,123 ms | 0.92 |

## Checked and left alone

Holding the first frame until local state is ready would skip the placeholder
frame, but that frame costs about 9 ms of UI-thread work here, a fraction of a
launch's run-to-run spread. The two remaining `/site.json` requests differ by
`Accept` header and response limit; sharing them would loosen the appearance
loader's 2 MB bound, for one request.

An iPhone launch draws continuously at 120 Hz from about 1.1 s until the run
ends. Between two tree walks 100 ms apart the only element rebuilt was the
`ShaderMask` of `DSwipeHint`, the phone bar's deliberate 3.7 s shine. It starts
after the first frame and ends by itself. It probably accounts for most of the
1.6 s of CPU after the feed; that was inferred, not measured by removing it.

The full app reaches Dart `main` about 29 ms later than the one-box app on the
phone (154.6 vs 125.6 ms), which is most likely the 54 MB AOT snapshot against
5 MB. It does not move the first frame, which iOS holds until later.

On macOS, 232 ms of a launch passes before Dart. Timers and Time Profiler put
it in AppKit, dyld and engine startup. `awakeFromNib` is the largest
application-owned step at about 22 ms of CPU, and about half of that is
`FlutterViewController`.

## What was not measured

Every timing above restores an anonymous session on a local server. A signed-in
launch also reads its API key from the Keychain, and that was not timed, to
avoid Keychain prompts on ad-hoc signed builds.
Release builds, launches from a tap rather than `devicectl`, and real network
latency were not measured either.

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

Add `--fresh` for first launches and `--dump` for the VM timeline and Dart CPU
samples, which slow the launch and must not be reported as timings.

For an iPhone, give the iOS Profile configuration a bundle id that is already
provisioned and is not your daily install's, build each side with
`flutter build ios --profile -t tool/startup_profile_main.dart`, and pass
`--device <udid> --block 4`. Sides share that bundle id and alternate in blocks:
each block installs a side, discards one launch and records four. Prefer the
`span:` rows when the Mac is busy, because they exclude what slowed the process
before Dart ran. With two sides, each row ends with a rank-sum p-value.
