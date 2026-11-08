# Desktop tab opening and closing

Existing document tabs keep their Native control trees when a sibling opens or
closes without changing their appearance, actions, or available width. Previously,
the strip rebuilt every existing control tree on either operation. The strip and
its drag wrappers still update, and a new document still mounts normally.

Each mounted tab retains one widget configuration. Selection, presentation,
action availability, constraints, inherited dependencies, rename state, and hot
reload invalidate it. Retained callbacks read the current widget, including the
current reorder index and menu handlers. This does not retain closed pages or
change the existing three-page retention limit per panel.

## Measurement

`test/desktop_tab_lifecycle_performance_test.dart` uses the production shell with
eight main-panel tabs and two secondary-panel tabs at 1440 by 900. The main strip
overflows. A topic list is scrolled 400 logical pixels; the test opens a Start tab
with the plus button and closes it with its close button, three times. It checks
the new page, tab removal, restored selection, retained page identity, retained
scroll position, and absence of framework exceptions.

`debugOnRebuildDirtyWidget` counts all widget builds from the button tap through
settling, including new mounts and both panels. A separate count follows the
already mounted `DDocumentTab` elements. This identifies unnecessary reconstruction
of the existing controls, rather than attributing the saving to page retention
that was already present.

Baseline: `634e5e50f`. Flutter 3.47.7, Dart 3.13.5, macOS host. Five alternating
baseline/candidate runs each exercise macOS, Linux, and Windows platform variants.
The fixture warms the shell before counting each of its three lifecycle cycles.
The new work-budget assertion fails on baseline after the behavioral checks pass.
Raw observations are in [desktop-tab-lifecycle.json](data/desktop-tab-lifecycle.json).

| Widget builds per action, median (range) | Baseline | Updated |
| --- | ---: | ---: |
| Open, entire shell | 4,613 (4,613–4,613) | 3,829 (3,829–3,829) |
| Close, entire shell | 2,461 (2,461–2,461) | 1,677 (1,677–1,677) |
| Existing document controls, open or close | 8 (8–8) | 1 (1–1) |

All three platform variants and all three cycles produced these counts in each
run. That is 17% fewer widget builds on opening and 32% fewer on closing for this
fixture. The remaining existing control rebuild updates selection and available
actions. The benefit depends on the number of tabs and whether their widths
change; a resizing tab still rebuilds for its new constraints.

These are deterministic debug widget-work counts, not native latency, frame time,
FPS, layout cost, or GPU measurements. The host had concurrent work (load average
around 9 on 18 logical processors); no wall-clock speedup is inferred from it.

## Verification

The lifecycle regression runs on all three desktop platform variants. A separate
tab-bar regression inserts a sibling, retains an unchanged control, and invokes
selection semantics, reorder semantics, close, and the Close other tabs menu. It
checks that all callbacks use the updated handlers and reorder index.

The directly related tab-bar, tab-switch, integration, and platform tests cover
renaming, dragging between panels, close/reopen shortcuts, last-tab replacement,
capacity, focus, semantics, themes, scaling, and strip geometry.

```sh
flutter test --no-pub \
  test/desktop_tab_lifecycle_performance_test.dart \
  test/forum_tabs_bar_test.dart \
  test/tab_switch_performance_test.dart \
  test/forum_tabs_integration_test.dart \
  test/forum_tabs_platform_test.dart
```
