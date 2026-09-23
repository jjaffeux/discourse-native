# Embedded content

`DEmbed` is an application component in the Native kit. The Reddit onebox
adapter uses it for Discourse's `iframe.reddit-onebox` markup; generic
`aside.onebox` rendering remains available for older cooked cards.

The provider supplies the iframe content. By default Native supplies the card
and heading, with the platform view meeting the inside of its one-pixel border
without extra spacing. `DEmbedPresentation.provider` lets providers such as
Reddit supply the complete card, including their own heading and outline.
Reddit uses this presentation to avoid duplicate headings and nested borders,
and follows the app's light or dark theme. Native still supplies the loading
indicator and failure card, with retry and external-link actions. Neither
presentation adds a footer to loaded content.

The adapter validates Reddit's
embed origins and post/comment identity, preserves comment query parameters,
and accepts canonical title-slug redirects. The host document validates both
origin and source window before forwarding `resize.embed` messages. Heights
are bounded to 120–2000 logical pixels. Following Reddit's
[official widget host](https://embed.reddit.com/widgets.js), the iframe uses
`scrolling="no"` while its content fits; scrolling is enabled for provider heights
above the maximum so the remaining content stays reachable. Disposing or replacing an embed
detaches its message channel and unloads the old document.

On macOS the platform view is composited in the root overlay, clipped to its
reader. This keeps native links clickable above Flutter card surfaces. The
existing native wheel bridge is shared with YouTube so wheel events scroll
the surrounding reader and continue to respect covering Flutter surfaces.
Trackpad gestures keep the same routing from their start through momentum,
even when an embed moves under or away from the pointer. Gestures started in
Flutter stay with Flutter's pan/zoom handling; gestures started over a native
embed stay with the wheel bridge. Discrete mouse-wheel ticks use the current
pointer location.
Touch platforms retain vertical drag scrolling with the reader.

The Embed styleguide provides self-contained examples of both presentations
and an unavailable example. None requires a Reddit account or network access.

## Verification — 2026-09-22

- Scroll routing follow-up (2026-09-23): 38 embed, Reddit and YouTube widget
  tests and all 11 macOS Runner tests passed, along with a macOS debug build.
  Native regression tests cover crossing embed boundaries in both directions,
  momentum, cancellation, gestures without momentum and discrete wheel ticks.

- Initial integration: 229 tests passed using the command below. Coverage includes cooked post and
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
- Footer follow-up: all 23 embed and Reddit tests passed after removing the
  footer and using the card's trailing slot. Assertions verify that the web
  view meets the card's bottom border after resizing, including
  the macOS overlay. Static analysis passed, and the live macOS fixture was
  inspected at normal width and in a narrow dark layout with no bottom gap.
- Border follow-up: 29 embed, Reddit and Onebox gallery tests passed, together
  with static analysis and a macOS debug build. Native inspection verified the
  outline and rounded bottom corners on offline and live content, including an
  expanded Reddit post in dark mode. Pointer links, expansion and wheel
  scrolling still worked. The provider's reported content height is preserved;
  only the one-pixel card border is reserved outside it.
- Theme and presentation follow-up: 30 embed, Reddit and Onebox gallery tests
  and 28 styleguide tests passed, alongside static analysis and a macOS debug
  build. The live macOS post was inspected in dark mode at regular width and
  light mode at 280 pixels, including switching themes while mounted. Reddit's
  own outline remained visible without a duplicate Native heading, frame,
  footer or normal iframe scrollbar. **Read more** expanded the post and wheel
  scrolling reached its bottom edge. The JavaScript harness also verified that
  heights above 2000 enable iframe scrolling and smaller heights disable it.

```sh
flutter test --no-pub test/ui/d_embed_test.dart test/oneboxes \
  test/cooked_html_test.dart test/cooked_markup_totality_test.dart \
  test/markup_contract_test.dart test/styleguide/styleguide_page_test.dart \
  test/youtube_player_surface_test.dart test/youtube_video_test.dart \
  --reporter expanded
```
