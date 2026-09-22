# Embedded content

`DEmbed` is an application component in the Native kit. The Reddit onebox
adapter uses it for Discourse's `iframe.reddit-onebox` markup; generic
`aside.onebox` rendering remains available for older cooked cards.

The provider supplies the iframe content. Native supplies the card, loading
indicator, retry action and external link. The adapter validates Reddit's
embed origins and post/comment identity, preserves comment query parameters,
and accepts canonical title-slug redirects. The host document validates both
origin and source window before forwarding `resize.embed` messages. Heights
are bounded to 120–2000 logical pixels. Disposing or replacing an embed
detaches its message channel and unloads the old document.

On macOS the platform view is composited in the root overlay, clipped to its
reader. This keeps native links clickable above Flutter card surfaces. The
existing native wheel bridge is shared with YouTube so wheel events scroll
the surrounding reader and continue to respect covering Flutter surfaces.
Touch platforms retain vertical drag scrolling with the reader.

The Embed styleguide provides self-contained, offline content and an
unavailable example. Neither requires a Reddit account or network access.

## Verification — 2026-09-22

- 229 tests passed using the command below. Coverage includes cooked post and
  comment rendering, malformed URLs, canonical redirects, bounded resizing,
  external-link keyboard activation, failures/retry, asynchronous disposal,
  narrow layouts at 200% text size, macOS pointer clipping and wheel routing,
  existing oneboxes/YouTube, and the styleguide catalogue.
- `flutter analyze --no-pub` and `git diff --check` passed.
- The generated host JavaScript was executed with a Node VM harness: trusted
  object and JSON-string resize messages worked; unrelated origins, source
  windows and malformed messages were ignored.
- A macOS debug fixture built and launched as an isolated, ad-hoc signed app.
  Live Reddit post `r/FlutterDev/comments/1molws4` loaded and resized. Clicking
  **Read more** expanded it; wheel input over the frame scrolled the reader.
  Narrow and dark layouts, the offline link callback, and the unavailable
  fallback were inspected. The review app was quit and the desktop lease
  released afterward.
- The upstream comment fixture is synthetic; native rendering displayed
  Reddit's unsupported-comment response. Its comment path and context
  parameters are covered by automated tests. Android, iOS and Linux device
  testing was not performed.

```sh
flutter test --no-pub test/ui/d_embed_test.dart test/oneboxes \
  test/cooked_html_test.dart test/cooked_markup_totality_test.dart \
  test/markup_contract_test.dart test/styleguide/styleguide_page_test.dart \
  test/youtube_player_surface_test.dart test/youtube_video_test.dart \
  --reporter expanded
```
