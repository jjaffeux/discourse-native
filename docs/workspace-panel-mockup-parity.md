> Historical design and capture notes. The app now uses the [flat appearance](material-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

# Workspace panel material parity

Reference: native-mockups `7c86328` and the supplied October 13 screenshots.
The current mockup sets `data-glass` on the page in both appearance styles.

Desktop Start, list, directory, and reader pages inside `WorkspacePanel` now
use their existing unframed page composition. The outer panel paints once,
including behind the tabs; content no longer compounds its opacity or starts
another rounded edge below the tabs. Standalone and touch page framing remains
owned by its existing shell.

The panel fill mixes 3% foreground into the palette background. Its 1px white
rim uses 14% opacity in dark mode and 75% in light mode. The top highlight fades
to transparent white within 140 logical pixels, at 6.6% in dark mode and 50% in
light mode. Using transparent white avoids Flutter interpolating toward black
and darkening the highlight. These panel treatments apply to both materials.
The existing clipped workspace bounds retain clear rounded corner gutters.

Both panel materials use the mockup's 40% maximum transparency. The ground
mixes 14% black into the palette background and paints the existing palette
pools under both materials. Standard keeps that ground opaque; native glass
can reduce its opacity to 35%. High contrast and OS Reduce Transparency retain
opaque surfaces and the existing accessibility edge treatment.
This supersedes the panel/ground ceilings in `material-mockup-parity.md`.

Validation includes rendered pixel checks at two panel heights, light/dark,
both materials, opacity endpoints and high contrast; desktop Start/list/reader
single-surface checks; window-corner and topic-inbox checks; targeted analysis.
`workspace_panel_review_main.dart` is an account-free macOS capture fixture:

```sh
flutter run -d macos -t lib/workspace_panel_review_main.dart \
  --dart-define=WORKSPACE_REVIEW_CAPTURE=true
```

It saves eight native captures to the platform temporary folder: light/dark,
Standard/Liquid glass, and opaque/split-translucent. These validate panel
rendering; their sample content does not represent whole-screen UI parity.

Three existing assertions fail identically on unchanged main: the desktop
resize handle expects 12px instead of its current 4px visible grip, a Start
navigation assertion still expects the retired cached-topic list, and the
forum-theme persistence test expects a supported appearance version to throw.
