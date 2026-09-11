# Pane resize input loss

Verified on 2026-09-11. Sidebar, topic inbox and diagnostics share
`ResizablePane`, which opted out of `DResizableHandle`'s existing accumulation
of input received before a frame. Each update therefore added its delta to the
last rendered width, overwriting earlier movement in the same frame.

## Reproduction and measurement

The regression in `test/resizable_pane_test.dart` starts a drag, renders a frame,
then delivers eight 2-logical-pixel updates without pumping another frame.
The controller advanced **2 pixels before the fix**, versus **16 pixels after**.
This measures dropped input, not CPU/raster frame time or a general FPS gain.
The fix enables the existing UI-kit option; no component API changes are needed.

A second regression starts with a saved 480-pixel width constrained to 376:
outward bursts preserve the saved preference; an inward 16-pixel burst immediately
reaches 360 and persists once on release. Existing keyboard, RTL, semantics,
focus, disposal and width-restoration tests remain in place.

The sidebar integration tests previously expected a dropped initial 20-pixel
update. They now require all delivered movement. Their rebuild instrumentation
confirms that dragging does not rebuild the shell, instance rail, sidebar or
main content widgets. The inbox integration suite confirms list/reader state
survives resizing and compact/wide transitions.

## Verification

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub test/resizable_pane_test.dart test/d_resizable_test.dart test/topic_inbox_test.dart test/styleguide/resizable_examples_test.dart`: 103 passed.
- `flutter test --no-pub test/sidebar_width_test.dart`: 8 passed.
- Touched Dart files formatted; `git diff --check` clean.
- Native macOS debug build, Skia/Metal: launched this worktree's
  `lib/styleguide_main.dart`; inspected Resizable / Production pane adapter with
  local data in the current dark theme. Dragging grew the accessible width from
  208 to 304 pixels, then shrank it to 222; content followed and the focus
  highlight cleared on release. This was an interaction check, not a profile-mode
  frame-time benchmark. Real account topic/sidebar surfaces were covered by
  widget integration tests, not by a native account session.
