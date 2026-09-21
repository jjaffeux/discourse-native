# Mermaid composer editor

The September 21 composer mockup is implemented with `DMermaidEditor` and
`DCodeEditor`, exported through `discourse_ui.dart`. The approved design has
no pane labels, status footer, live indicator or editable badge. Header actions
are icon-only copy and expand/collapse buttons. Below 600 logical pixels the
source and preview stack vertically.

## Ownership and reuse

`DCodeEditor` wraps the existing `flutter_code_editor` dependency, already used
by the fullscreen post-code viewer. That viewer now uses the Native component.
Inline post code retains its lightweight renderer. Both share the existing
syntax engine and code typography, moved into UI foundations with compatibility
exports from their old shell locations. Code colors follow the site theme;
plain Flutter themes have a light/dark fallback.

Callers own and dispose `DCodeEditingController` and any supplied focus node.
The editor needs a finite height, preserves long lines with horizontal scrolling,
and reports text changes from typing, indentation, undo and controller commands.
Read-only mode also guards upstream keyboard commands that otherwise try to
move the caret after rejecting a write. A small Mermaid grammar adds authoring
highlighting without another dependency.

`DMermaidEditor` owns its controller and focus, keeps equal source updates from
resetting selection/composition, commits edits synchronously through `onChanged`,
and debounces only diagram rendering by 350 ms. `DMermaid(showControls: false)`
reuses the existing offline renderer without duplicating reader actions.
Invalid syntax remains editable and uses the renderer's inline error surface.

The bundled Mermaid plugin owns fence discovery and its interactive composer
projection. A late-bound `ComposerSyntaxPolicyContext.readEditor` provides the
existing least-authority host after the controller has been constructed.
Top-level closed backtick/tilde fences are supported. Other code fences,
unclosed fences, quoted and indented fence markers stay literal. Source edits
verify current host admission and the exact old Markdown before committing;
fence delimiters grow when code contains delimiter-like text. Surrounding post
text and original fence whitespace survive edits. Draft saves use canonical
Markdown immediately, independently of preview completion.

## Examples and verification

- Styleguide: Code editor / Editable code and Read-only code; Mermaid / Composer editor.
- Local fixture: `tool/composer_mermaid_review_main.dart`, with the production
  composer, local data, palette/width/direction controls and styleguide access.
- `dart analyze --fatal-infos`.
- Focused widget, parser, reader, syntax, Markdown controller, plugin-boundary,
  registry and UI adoption checks: **218 passed**. These include nested select-all/
  deletion, indentation-to-draft propagation, IME preservation, readonly commands,
  stale callback rejection, empty fences, delimiter escaping and CRLF preservation.
- macOS debug fixture built and launched from an isolated ad-hoc signed copy.
  Visually inspected the production composer in light/dark and narrow layouts,
  changed “New contribution” to “Updated contribution” in the source and confirmed
  the rendered label changed, and inspected invalid syntax feedback. Inspected
  the new Code editor styleguide page in the native app. The copied bundle omits
  restricted push/team/application entitlements; the real app's signing is unchanged.
- The native automation exposed only window/menu accessibility nodes, so full
  native AX ancestry was not verified. No iOS/Android device testing was performed.

No dependency versions or lockfiles changed. The HTML concept remains in
`docs/mermaid-composer-mockup.html` for comparison. This change does not modify
posting format: the server still receives ordinary Mermaid Markdown fences.
