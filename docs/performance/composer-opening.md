# Mobile composer opening

The mobile composer sheet owns keyboard avoidance. While that sheet covers the
shell, the shell Scaffold keeps its full available height. This avoids resizing
the covered reader, sidebar, and navigation for every keyboard inset update.
The sheet continues to receive the real keyboard insets and screen size.
Closing or minimizing the sheet restores the shell's normal keyboard avoidance.
Desktop behavior is unchanged.

An iPhone CPU capture identified covered reader chrome, header measurement,
sidebar, and navigation work during keyboard reveal. Category and tag searches
already start when their menus open. A trial that clipped the footer blur at the
keyboard edge showed no clear raster improvement and was discarded.

The change uses the presentation host's existing mobile-sheet state and the
Scaffold's existing resize option. It introduces no control or UI-kit API.

## Verification

`test/composer_opening_test.dart` drives intermediate keyboard insets, screen and
safe-area changes, close, and keyboard dismissal. It checks that the covered
reader retains full screen constraints, the editor and reader retain identity,
the toolbar stays above the keyboard, and normal reader resizing resumes on
close. The docking and mobile viewport suites cover picker focus, swipes,
minimizing, restoring, long drafts, and large text.
The new viewport regression fails with the previous resize behavior. The native
iPhone 17e simulator also completed six openings with category and tag controls,
the toolbar, and Liquid Glass enabled.

The final physical-device timing comparison was unavailable because the iPhone
VM-service connection failed after successful baseline and diagnostic captures.
No physical-device latency or percentage speedup is claimed.

## Native opening fixture

Run the production app with a fake API, 250 categories, enabled tags, actual
device dimensions, and six composer openings:

```sh
flutter drive --no-pub --no-start-paused --profile -d <physical-iphone-id> \
  --driver integration_test/performance_driver.dart \
  --target integration_test/composer_mobile_opening_performance_test.dart \
  --dart-define=PROFILE_LABEL=current
```

The driver saves full frame data to `build/integration_response_data.json`.
Keep the first opening separate from the five repeated openings. Alternate
baseline and candidate runs when comparing them. Frame batches are filtered by
the measured action's timestamps. Assertions check that the composer, category,
tags, and toolbar mount and that the composer builds once.

The fixture mocks text input and applies keyboard insets of 80, 160, 240, and 320
logical pixels. It measures Flutter frame work for those layout updates. It does
not measure OS keyboard animation, network latency, or input-to-display latency.
`openingMs` includes test pumps and settling, so it is not an input latency.
Simulator and debug runs verify rendering and behavior, not device performance.

For a diagnostic capture, enable `PROFILE_COMPOSER_WIDGETS=true` and collect a
VM timeline or CPU profile. That setting adds per-widget build and layout events.
Keep those instrumented timings out of baseline/candidate performance comparisons.
