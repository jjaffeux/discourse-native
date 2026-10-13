# Chat reaction artwork parity

Reference: `discourse-native-mockups` at `7c86328`, `ChatBubble` in
`src/App.tsx` and the semantic palette ramp in `src/app.css`. Channels and
threads both use this bubble. The browser reference measured 24px height,
12px text with 18px line height, 6px gap, 2px vertical / 9px horizontal padding,
a 1px border, and a pill radius.

`DToggleDensity.chatReaction` retains those bounds and now uses regular-weight
counts and the raw palette surface for the 10% fill, 22% border, and 62% text
mixes. It paints a flat chip in Standard and Liquid Glass, without raised
material refraction, sheen, rim, or shadow. The app retains site emoji images,
selected semantics, and its existing stronger 15% fill / 32% border for selected,
hovered, and pressed controls. The reference's reaction span is static and does
not specify those interaction states.

Validation: 18 toggle tests, 83 production chat-tile tests, and 4 post-reaction
regression tests. Checks include pointer and keyboard activation, target bounds,
disabled / selected state, RTL, 200% text, and reduced motion. Eight inspected
production-widget renders cover channel / thread, light / dark, and both
materials. These are Flutter test renders using bundled Lato and site emoji,
not a live-account or physical-device capture.

Reproduce captures with:

```sh
CHAT_REACTION_RENDER_DIR=/private/tmp/chat-reaction-parity \
CHAT_REACTION_EMOJI_DIR=/Users/joffreyjaffeux/Code/discourse/public/images/emoji/twitter \
flutter test test/chat_message_tile_thread_preview_test.dart
```
