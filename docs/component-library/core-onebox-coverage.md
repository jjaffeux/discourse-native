# Core onebox coverage

The native renderer was compared with all **69 concrete core engines** at
[`discourse/discourse@7b6f30d334`](https://github.com/discourse/discourse/tree/7b6f30d3341ccf6f531667334e13cb8b8fc0b01a/lib/onebox/engine).
`tool/markup_contracts/core/onebox_inventory.json` records every engine and its
output formats. Every engine is pinned in the markup contracts; existing GitHub
plugin-owned templates retain their owner. The 22 card fixtures in
`test/fixtures/oneboxes/core_cards.json` are rendered from that upstream revision.

## Rendering

- Existing Discourse, GitHub, Twitter, Reddit and YouTube renderers remain in use.
- All cooked HTTPS iframe previews use `EmbeddedOnebox` and Native `DEmbed`.
  This covers core's dedicated providers and forum-configured generic oEmbed
  providers without a second provider allowlist becoming stale. The forum is
  responsible for sanitizing cooked iframe markup before it reaches the app.
  Only the URL, title and finite dimensions are consumed. Post-provided
  `srcdoc`, event handlers, script bodies and permissions are never forwarded.
  Credentials and non-HTTP(S) URLs are rejected; embeds require HTTPS.
- Embeds load on demand and retire their web view when replaced or removed.
  `DEmbed` retains its original navigation/origin restrictions, loading, retry
  and browser fallback behavior. Twitch's parent parameter matches the actual
  native host document. Vimeo's original link and private query are preserved.
- Asciinema's exact script URL is translated to the provider iframe used by
  its official bootstrap. No arbitrary post script is evaluated. See the
  [Asciinema embedding reference](https://docs.asciinema.org/manual/server/embedding/).
- The bundled lazy-video plugin handles Vimeo and TikTok placeholders as well
  as its existing YouTube support.
- Direct audio uses `DAudioPlayer`, composing Native Card, Button, Slider and
  Spinner. The shell owns lazy startup, seeking, pause, retry, source replacement
  and disposal. iOS/macOS use the existing AVFoundation media transport; Linux
  uses a hidden audio element with Native controls and time-state messages.
  Secure-upload URL resolution is shared with uploaded video. Background or
  hidden content pauses and does not automatically resume.
- Generic cards remove only extracted title/thumbnail nodes from a cloned DOM.
  Nested sibling descriptions, links, code and metadata survive extraction.
  Full-size images, galleries and video fallback images remain in their content
  positions instead of being consumed as thumbnails.

The Onebox gallery now has 47 entries, including all 29 iframe engines,
Asciinema and audio. Some provider IDs are illustrative; live previews can show
provider-side unavailable, authentication or rights errors. The separate
Audio player page exercises controlled playback, loading and retry states
without network requests. The frozen upstream component catalogue is unchanged.

## Engine mapping

| Output | Core engines |
| --- | --- |
| audio | `audio` |
| card | `amazon`, `github_actions`, `github_commit`, `github_folder`, `github_gist`, `github_issue`, `github_pull_request`, `github_repo`, `gitlab_blob`, `google_docs`, `google_drive`, `google_meet`, `google_play_app`, `hackernews`, `pastebin`, `pdf`, `pubmed`, `stack_exchange`, `threads_status`, `wikimedia`, `wikipedia`, `xkcd` |
| card, embed | `github_blob` |
| card, image, video, embed | `allowlisted_generic` |
| card, video | `gfycat` |
| discourse | `discourse_topic` |
| embed | `audio_com`, `audioboom`, `band_camp`, `coub`, `google_calendar`, `google_maps`, `instagram`, `kaltura`, `loom`, `mixcloud`, `motoko`, `replit`, `restream`, `simplecast`, `sketch_fab`, `slides`, `sound_cloud`, `spotify`, `steam_store`, `tiktok`, `trello`, `twitch_clips`, `twitch_stream`, `twitch_video`, `typeform`, `vimeo`, `wistia`, `youku` |
| embed, card | `facebook_media` |
| image | `animated_image`, `five_hundred_px`, `image` |
| image, album | `flickr`, `flickr_shortened` |
| image, album, card | `google_photos` |
| image, album, video | `imgur` |
| image, video, link | `cloud_app` |
| reddit | `reddit_media` |
| script | `asciinema` |
| twitter | `twitter_status` |
| video | `video` |
| youtube | `youtube` |

## Verification (2026-09-23, Flutter 3.47.4)

- Root `flutter analyze --no-pub`: no issues.
- 225 focused tests passed: all oneboxes, gallery, control adoption, cooked
  markup totality, markup contracts, native/WebView video transport, inline
  video, Embed, and secure video-source resolution.
- Card fixtures preserve article text across all 22 templates and render at
  320px / 200% text. Gallery tests cover light and dark palettes, large text,
  real production builders and provider switching. Audio tests cover native
  and Linux transport state, seeking, teardown, source replacement and errors.
- The broader run including `cooked_html_test.dart` and
  `styleguide/styleguide_page_test.dart` produced 322 passes and 15 failures.
  All 15 failures reproduce on an untouched checkout of baseline `c2cd46e70`:
  two typography expectations and thirteen general styleguide expectations.
  No failures were suppressed and unrelated source was not changed.
- The macOS styleguide built successfully. An isolated ad-hoc signed review
  bundle retained the permitted debug entitlements; production provisioning
  and entitlements were untouched.
- Native macOS inspection confirmed MP3 playback advancing to 0:32 / 6:12,
  pause and seek to 2:59, live dark/light switching and a 360px viewport.
  Asciinema loaded and played, visibly advancing its terminal recording.
  Vimeo loaded its provider player and controls; pressing Play produced the
  provider's “Rights issue” message. It is not counted as successful video
  playback. Final Native Card padding was inspected in the rebuilt Audio
  player page.
- Physical iOS and Linux devices and every external provider's live service
  were not exercised. Media codec support, authentication, availability and
  embed restrictions remain provider/platform dependent.

Passing focused command:

```sh
flutter test --no-pub test/oneboxes test/styleguide/onebox_examples_test.dart \
  test/control_style_adoption_test.dart test/cooked_markup_totality_test.dart \
  test/markup_contract_test.dart test/native_inline_video_playback_test.dart \
  test/webview_inline_video_playback_test.dart test/inline_video_test.dart \
  test/ui/d_embed_test.dart test/site_video_source_test.dart
```
