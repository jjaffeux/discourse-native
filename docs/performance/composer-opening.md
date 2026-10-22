# Mobile composer opening

The mobile composer sheet owns its keyboard. While that sheet covers the shell,
the shell sees no keyboard: its bottom view inset is zero and its bottom safe
area is the device's. The covered reader, sidebar, and navigation keep the
layout they have without a keyboard and are not rebuilt for keyboard inset
updates. The sheet continues to receive the real keyboard insets and screen
size. Desktop behavior is unchanged.

The sheet's keyboard outlives the sheet. A swipe slides the sheet off-screen
before the composer minimizes and unfocuses, and a close removes the sheet in
the same frame, so the keyboard starts retracting with the shell already
uncovered. The shell keeps ignoring that keyboard until it is gone. Resizing
for it would lift the dock onto the keyboard's top edge, mid-screen, for the
whole retraction. Chrome that changes for a keyboard of its own, such as the
chat composer, which drops to the screen edge and hides the dock, would make
that change under the sheet and undo it after the retraction. A keyboard that
rises again, for a field in the shell, restores normal keyboard avoidance at
once.

An iPhone CPU capture identified covered reader chrome, header measurement,
sidebar, and navigation work during keyboard reveal. Category and tag searches
already start when their menus open. A trial that clipped the footer blur at the
keyboard edge showed no clear raster improvement and was discarded.

The change uses the presentation host's existing mobile-sheet state and a
`MediaQuery` override around the shell Scaffold. It introduces no control or
UI-kit API.

## Verification

`test/composer_opening_test.dart` drives intermediate keyboard insets, screen and
safe-area changes, close, and keyboard dismissal. It checks that the covered
reader keeps its resting bounds, the editor and reader retain identity,
the toolbar stays above the keyboard, and normal reader resizing resumes once
the keyboard is gone. Swipe and close cases check that the reader and dock stay
put while the keyboard retracts, and that a keyboard rising again resizes the
reader. `test/chat_shell_integration_test.dart` opens the sheet over a phone
chat channel and checks that the chat composer and dock keep their resting
bounds under the sheet, after a swipe, and through the retraction. The docking
and mobile viewport suites cover picker focus, swipes, minimizing, restoring,
long drafts, and large text.
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
