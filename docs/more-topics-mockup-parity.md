# More topics parity — 2026-10-09

Reference: `discourse-native-mockups` snapshot
`c39ad5079e36ccd40a2604c43b513195d5c125a2`, following the already-shipped
`54ba01c` baseline. This record covers only the More topics reading experience.

## Source audit and supersession

Inspected More topics changes in `9559219`, `25e8307`, `fec87b3`, `c678343`,
`d3d9e66`, `a239e3d`, `b1e5fbf`, `e0b02eb`, and `c59a3ed`, then checked their
result against final `c39ad50` source (`MoreTopics`, `TopicView`, `.topic-foot`,
`.more-after`, `.more-panel`, and covered header/timeline styles).

- `9559219` introduces the topic end, recommendation sources and saved choice.
- `25e8307`–`b1e5fbf` experiment with snapping, pull gates, fades and recession.
- `e0b02eb` adds sticky overlap, a 35%-viewport pause gap, a grip and a page title.
- `c59a3ed` removes overlap, grip, gap, scale and snapping. The inset rounded
  panel scrolls normally; chrome yields after its top passes the viewport's
  midpoint, only after the reader has actually scrolled.
- **Later `137a41f` also removes partial topic dimming.** Its diff deletes
  `MORE_RECEDE`, `MORE_FADE`, the `--recede` writes and `.topic-read` opacity.
  These remain absent in final `c39ad50`. Posts therefore stay at full opacity.
  Implementing the intermediate `c59a3ed` 1→.55 fade would not match the pinned
  final design.

## Existing behavior retained

Real server suggested topics and installed plugin recommendation sources;
ordered sources, empty-source fallback, forum-scoped saved tab choice, emoji
rendering, topic-card navigation, inbox routing, final-window loading, sidebar
preference, reply permissions, and retired-account persistence guards.
No fixture conversations, synthetic related-topic ranking or artificial 450ms
loading delay were introduced.

## Implemented changes

The inline recommendations are a separate sliver after the post stream and
end actions. A Native Card supplies the rounded 14px panel, reading-column
width (including the user's width preference), minimum 8px side inset, 16px
separation and 8px foot inset. It has a page-sized localized title, Native pill
tabs, and ordinary topic rows. Narrow/enlarged layouts stack title and tabs.
A localized end marker, Native More topics action and permission-gated Reply
mark the topic's own end. More topics brings the panel into view; selecting a
source brings its start into view. These explicit actions use an interruptible
400ms Flutter ease-out scroll; reduced motion jumps immediately. Ordinary
scrolling has no snapping, pause timer, sticky overlap, grip, scale or fade.

The approved Native `DPageSurface.headerSuppressed` option retains the full
scroll spacer and viewport while releasing the header and its obstruction over
240ms (immediate with reduced motion). Header controls, focus, semantics and
hit targets yield too. The reader sets it after more than half the view is
occupied by the panel and restores ordinary header behavior on scrolling back.
The timeline and floating day overlay yield over 200ms. A short topic keeps
its header at scroll offset zero.

The timeline completes at the topic end even though recommendations extend the
scrollable document. Recommendation-only visibility never creates post read
receipts or a new post anchor. Returning to posts restores ordinary progress.
The existing post list retains its identity and virtualized post indexing.

## Verification

New tests: `topic_more_topics_test.dart`, `d_page_surface_suppression_test.dart`,
and a coordinator regression for timeline completion without marking unseen
posts read. Related checks cover post rebuilds, recommendation emoji, account
retirement, saved tabs, source keyboard navigation/routing, final-page loading,
inbox navigation and sidebar attachment lifecycle. Targeted analysis is clean.

Production reader fixture renders were inspected at 1000×800 and 1200×800
(reading width limited to 825), plus 390×844 dark at 100% and 200% text. Captures
include entry, panel ownership, short-topic initial state and narrow layouts.
Generate them with:

```sh
MORE_TOPICS_RENDER_DIR=/private/tmp/more-topics-renders \
  flutter test --no-pub test/topic_more_topics_test.dart
```

The existing `d_page_surface_test.dart` has four unchanged-main failures:
its two old all-or-nothing 8px-scroll expectations, and two header hit-test
expectations after scroll reversal. The same four failures reproduce on
unchanged main `84262ec96`. Its other ten tests and the new suppression cases
pass. This is widget/render evidence, not a physical-device performance claim.
