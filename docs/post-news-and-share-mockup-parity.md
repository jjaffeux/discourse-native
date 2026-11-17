# Post news, small actions and sharing parity

Source: `discourse-native-mockups` commit `540cbac` on `test-mobile-layout`,
the phrases "posts' news unboxed under a fading tint and ruled off from the
post, said quietly; whispers said as news; small actions standing apart;
dates at the row's end opening a share sheet". Line numbers cite the saved
diff of that commit on `src/App.tsx` (`c1-app.diff`) and `src/app.css`
(`c1-css.diff`). The assignment banner, the topic's foot tools, toasts and
scrollbars in the same commit have other owners.

## Checklist

| Mockup change | Evidence | Native | Verified by | State |
| --- | --- | --- | --- | --- |
| A post's news lines are bare inside its card: mark, then the line at 13px in the secondary colour, not 14px semibold | app 491–568 (`PostBanner` `bare`, title style) | `DAlert.postNotice` draws every line; `PostNewsCard` sets them 16 in, 14 under the card's top, 12 apart | `post_news_mockup_parity_test.dart`, `d_alert_test.dart` | Done |
| The mark is the icon alone, 15px in a 30px room, `color-mix(tone 70%, text-secondary)`, no disc | app 1036–1055 (`PostBannerMark`) | `DAlert.postNotice(icon:, tone:)`; the greeting's emoji stands in the same room with no disc | `d_alert_test.dart`, `post_greeting_mockup_parity_test.dart` | Done |
| Any post with news is held in a card whose lines are bare (`inCard`) | app 747–752 | Every news line is bare in the card; the boxed variant had no remaining use | parity tests | Done |
| The card's tint runs only under the news, fading out over 40px by the rule (`--news-end`, `.post::before` gradient); the post keeps the page ground; the card's raised/sunken overrides go | css 3148–3170 | `DCardTint` behind the news block; the card fill is transparent | pixel test in `post_news_mockup_parity_test.dart`, `d_card_test.dart` | Done |
| The byline is ruled off from the news, 1px subtle, 12px under it, only when there is news (`.post-by.is-ruled`) | app 828–834, css 3196–3199 | `DSeparator` at the head's foot, inset 16 each side; byline 12 under it | `post_news_mockup_parity_test.dart` | Done |
| Whisper said first as a bare line "Whisper, only staff can see this" with the eye-slash mark | app 699–712 | `post-whisper-<id>` line, first in the news | parity and integration tests | Done |
| The whisper tag at the byline's end is removed | app 900–921 | The eye-slash tooltip icon is gone from the byline | `topic_reading_integration_test.dart` | Done |
| The dashed whisper card takes the head tint in the text colour | css 3217–3221 | Tint `onSurface` at 8%, dashed edge at 30% | `post_news_mockup_parity_test.dart` | Done |
| Locked's mark tone is the secondary colour | app 2012 | `tone: null` | `post_news_mockup_parity_test.dart` | Done |
| Small action: a mark and one 13px line in the secondary colour, anything more after a muted middle dot, no card, a post card's room above and below | app 19–85, css 3180–3192 | `SmallActionLine` over `DAlert.postNotice`; 32 above, 10 below (the posts' 18 card margins give the mockup's 50 and 28); no avatar; rules on either side are dropped | `small_action_test.dart` | Done |
| Time gap as a small action with the clock mark | app 86–98 | `TimeGapNotice` | `time_gap_test.dart`, day separator tests | Done |
| Last visit as a small action: envelope-open in the accent, "New since your last visit · N posts" | app 99–114 | `LastVisitNotice`; N counts the topic's stream from the first unread post | `topic_day_separator_test.dart` | Done |
| The post's date moves to the byline's far end as a pressable that opens the share sheet, "Edited" beside it; the middle dot and time after the name go | app 845–899 | `PostDateShare` (`DButton` inline, 12px muted) after the revision indicator | `post_news_mockup_parity_test.dart` | Done |
| Share sheet: "Share topic" or "Share post #N", the title as its own head, the link in a sunken box, primary "Copy link" and secondary "Share" sharing a row, "Reply as new topic" for a reply | app 951–1059 | `topic_share.dart` | `topic_share_sheet_test.dart`, `share_reply_source_test.dart` | Done |
| Copying closes the sheet and toasts | app 955–960 | Closes, then "Link copied!" | `topic_share_sheet_test.dart` | Done |
| The post menu's Share and the topic menu's "Share topic" open the sheet; the opening post is shared as the topic | app 1060–1130 | Both open the sheet, a dialog on desktop; the anchored desktop menu is removed | `topic_more_actions_sheet_test.dart` | Done |
| Share icon `faShareFromSquare` | app 1006 | The app's icon set has no share-from-square; `upRightFromSquare` stays | none | Not done, cosmetic |
| Staff notice mark is the site logo, the line the site's name, with a "Staff notice" chip | app 1873–1905 (context, not changed by `540cbac`) | Mark `user` icon, line "Staff notice", notice text under it | parity tests | Not done: an earlier mockup state the app never took |

## Kit changes

- `DAlert.postNotice` is now the bare post news line (mark room, tone,
  quiet message, optional `DAlertAction` that drops under a narrow line,
  optional body) and no longer pads itself. Callers: the greeting and staff
  notice, the core news lines, Solved, small actions, the styleguide's
  thread writing example. Test: `test/ui/d_alert_test.dart`.
- `DCardTint` is a new card part: a head tint that fades to nothing over
  `fade` points by its foot. Callers: `PostNewsCard`, the styleguide
  example. Test: `test/ui/d_card_test.dart`.
- `DIcons.envelopeOpen` and `DIcons.clock`, from Discourse's own Font
  Awesome sprite.

## Deliberate departures and calls

- The last-visit marker reverses `bec720ae4`, which matched chat's red "New"
  divider. The mockup now says it as a small action.
- Invite stays on the topic's share sheet: it is the app's only way into the
  invite editor. The mockup's sheet has no invite.
- The topic's own share sheet no longer offers "Reply as new topic"; the
  post menu still does for every post.

## For plugins

A plugin says a banner line under a post's head through
`PostHeaderPlugin.postHeaders`, returning `DAlert.postNotice` widgets: they
are placed between the hidden and locked lines, inside the tinted head and
above the rule. A note box under a post's body (the mockup's `NOTE_BOX`)
belongs to `PostDecorationPlugin.postDecorations`; this slice adds no box
component for it.

## Evidence

```sh
POST_NEWS_RENDER_DIR=$PWD/docs/post-news-and-share-mockup-parity \
  flutter test test/post_news_mockup_parity_test.dart
```

Captures in `post-news-and-share-mockup-parity/` show a locked whisper
between two plain posts on a light and a dark phone and a light desktop.
They are widget-test renders, not device runs.
