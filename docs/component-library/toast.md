# Toast reference mapping

Frozen reference: 2026-09-08, `toast.md` SHA256
`e1dd1c08ccb082e6ca90fe352e09242cbf81132e37e05db889c67c8e601e1174`.
The hash was reverified on 2026-09-09. The inspected base-nova registry item is
`toast.json`, SHA256
`161ed77c409fe7345ee6308f7cf66f7bcf2717d8d5e1a8b36a7f8e8fa0df745e`.
The catalogue row includes the Sonner-backed status treatment; the supporting
`sonner.json` inspected on the same date has SHA256
`831967f80f645ac3908b356a44748698a9ceed1c6a51b232dd5e87c52a54d7c3`.

## Visual mapping

| base-nova source | Flutter mapping |
| --- | --- |
| fixed viewport, 16px screen inset, max-width 384px, bottom-end by default | local `DToaster` stack, safe-area-aware 16 logical-pixel inset, 384 logical-pixel maximum, directional six-position API |
| popover background/foreground, border, `rounded-2xl`, large shadow | live `DTokens.surface`/foreground/border, host radius ×1.8, 0/4/15 shadow |
| 16px content padding, 12px major gap, 4px title/description gap | identical logical geometry |
| 14/20 medium title, 14/20 muted description | explicit `DiscourseTypography.sm`/20 logical-pixel leading with host font family |
| 16px success/info/warning/error/loading artwork | 16 logical-pixel status icons; error uses the destructive token and loading composes `DSpinner` |
| outline small action, ghost icon-small close with enlarged pseudo-element | final shared `DButton` outline/ghost compositions and accessible native hit targets |
| focus border plus three-pixel half-alpha ring | border plus exterior foreground ring without tinting the translucent surface |
| stacked limit, pause on interaction, swipe dismissal and 500ms easing | controller limit and close reasons, hover/focus/app-lifecycle timeout pause, direction-aware horizontal native drag, shared reduced-motion duration |

The native adaptation uses Flutter focus/actions, drag recognition, safe areas,
screen-reader live regions, and `F6`/Escape shortcuts rather than DOM landmarks,
ARIA attributes, or CSS custom properties. Text wraps and the card grows at
large accessibility scales instead of clipping to the browser's measured
height. Start/end positions mirror in RTL. Custom child composition deliberately
keeps callback and resource ownership with the caller.

## Behavioral contract

`DToastController` supports add/upsert by stable id, update, close, close-all,
limits, timers, pause/resume, typed data/custom builders, action callbacks,
close reasons and promise-driven loading/success/error updates. Every update
increments a revision. A promise completion updates only the exact revision it
created, preventing dismissal, repeated ids, replacement, or disposal from
receiving stale terminal results.

`DToaster` borrows a passed controller and owns an implicit one. Removing an
owned scope cancels timers and makes late async work inert. The root app has one
scope; every styleguide preview has its own nested scope so notices cannot leak
between samples or into the documentation shell. Hover, keyboard focus and app
backgrounding pause remaining durations. Close buttons, actions, swipe,
timeout, replacement, limit eviction and programmatic dismissal remain distinct
observable close reasons.

## Adoption boundary

Transient success/error/action feedback belongs to Toast. Permanent inline
validation, availability and status remain with Alert, Field or Empty. The
implementation migrates the specifically audited topic-list, topic-share,
user-menu, diagnostics, topic-move-posts, composer-discard, topic-tag-picker,
reaction-presentation and Button-example owners. The independent reviewer must
finish the exhaustive remaining core/plugin transient-notification pass while
reconciling any overlapping Alert changes from its reviewer; specialized
progress, recording and modal errors must retain their application meaning.
