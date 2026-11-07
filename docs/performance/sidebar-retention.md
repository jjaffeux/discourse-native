# Sidebar rendering work

Opening and closing retain the sidebar's destination rows on desktop and mobile.
Scrolling repaints the moving body without repainting fixed controls or neighboring
reading content.

On desktop, the wide shell retains its `InstanceSidebar` widget across rail
toggles. The window-button inset stays configured while the sidebar is hidden.

On mobile, `DHistoryTransition` keeps `DHistoryNavigation.preview` in one location
for both the preview and open navigation. The previous handoff reparented the
entire sidebar, invalidating inherited dependencies throughout its rows. The
reading page remains mounted separately. Shared motion code preserves the reveal,
return, and tab animations, while frame snapshots include the live navigation.

Visibility changes update focus and reset a different selected panel to the
foreground destination. They leave an already selected panel's body alone.
Inactive surfaces exclude input, focus, and semantics.

The sidebar panel and its fixed header and footer have separate repaint
boundaries. Desktop scrolling no longer invalidates the mobile sheet painter.
Mobile sheet edges still update as their pinned headings move.

The expanding tab strip observes text scaling so its natural widths are measured
again when retained icons grow. Rebuilding the sidebar previously masked that
missing dependency.

## Regression evidence

The comparison uses baseline `8e4df6bdb`, Flutter 3.47.7, and Dart 3.13.5 on macOS.
The widget tests exercise macOS, iOS, and Android layouts. All six performance
regressions fail on that baseline and pass with this change.

| Counted Dart work | Baseline | Updated |
| --- | ---: | ---: |
| Fixed-control and neighboring-page paints during eight scroll frames, each platform | 312 | 0 |
| Destination-row builds during a desktop close/reopen cycle | 66 | 0 |
| Destination-row builds during a mobile close/reopen cycle, each mobile platform | 52 | 0 |

The scroll fixture has two lazy sections with 100 destinations each. The toggle
fixture uses the production shell with 60 categories. It checks the same scroll
controller and a retained offset of 200 logical pixels after reopening.

These are deterministic widget-work counts, not latency or GPU frame-time
measurements. No physical-device smoothness claim follows from these checks.

The five forum, chat, scrolled, and voice-section drawer captures are byte-identical
to baseline. Existing tests cover sidebar widths, panel reselection, keyboard
dismissal, swipe cancellation, history restoration, and reduced motion. A separate
navigation regression checks focus, semantics, hit testing, and return-page
compositing.

Run the work-count regressions with:

```sh
flutter test test/sidebar_performance_test.dart
```

Capture the drawers with:

```sh
flutter test test/mobile_drawer_structure_test.dart \
  --dart-define=drawerCaptureOutput=/private/tmp/sidebar-captures
```
