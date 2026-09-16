# Composer draft status studies

Open `index.html` directly, or serve this directory with a local HTTP server.
No build step, network dependencies, real saving, or application changes.

1. **In the action bar:** persistent “Draft saved” at the trailing edge of the existing footer.
2. **In the header (recommended):** persistent “Saved” beside the window actions, freeing the footer for attachments and plugins.
3. **Confirm, then recede:** a 2.4-second confirmation followed by a persistent cloud/check icon. Click the icon for save details.

Use the state controls to compare saved, saving, device-only, and failed saves.
Type into any editor or choose Replay autosave to exercise the save cycle.
Light/dark palettes and a narrow composer preview are available. Surrounding
composer actions are presentation-only; only draft text and status interactions
are active. Warnings persist until Retry (simulated success) or a new state.

The existing `_Footer` in `lib/src/shell/composer_panel.dart` puts draft text
above the controls and adds that line only when a status exists. These concepts
reserve a stable place within existing chrome for routine save feedback.
Exceptional failures retain readable detail; this can use extra space.

Implementation can compose existing Native components from
`package:discourse_native/discourse_ui.dart`: `DIcon`, `DSpinner`,
`DButton.iconOnly`, `DTooltip`, `DPopover`, text/layout and semantics primitives.
No new kit component or API is proposed. Warning retry behavior is a proposal,
not a claim that the application currently exposes that exact action.

Control geometry follows `docs/component-library/conventions.md` (28px regular,
32px large, 8px radius). Colors use the saved dev.discourse.org palette already
in `docs/mockups/button-directions/palette.json`, with contrast-adjusted status
colors. HTML reproduces the intended layout for review; it is not a native
component rendering or device verification.

Verified in isolated headless Chromium: all three layouts, light/dark appearance,
320/390/768/960/1024/1440px widths, saving/saved layout stability, typing and
autosave, persistent warning states, retry, status details with Escape and focus
restoration, and reduced motion. No JavaScript errors or page/header/footer
horizontal overflow. Desktop and narrow screenshots were visually inspected.
