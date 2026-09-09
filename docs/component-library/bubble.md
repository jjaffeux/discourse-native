# Bubble reference mapping

Reference date: 2026-09-08  
Documentation: <https://ui.shadcn.com/docs/components/base/bubble>  
Frozen Markdown: <https://ui.shadcn.com/docs/components/base/bubble.md>  
Frozen Markdown SHA256: `6863ccd2854a6d590991fc58cb8b5ddcb82fe88d25185100b7bf111021267a82`  
Base-nova registry: <https://ui.shadcn.com/r/styles/base-nova/bubble.json>  
Registry SHA256 inspected 2026-09-09: `be11ab3fa78ec7bd4736f4ab98c16a2d5a230536206d5a4fd06259422b55cb14`

## Frozen scope and acceptance

Bubble is the presentational message surface, not the full conversation row.
The generic owner comprises `DBubble`, `DBubbleContent`, `DBubbleReactions` and
`DBubbleGroup`. It must cover all seven Bubble variants, logical start/end
alignment, content-relative width, grouping, static and interactive reactions,
button/link content, and the documented Collapsible, Tooltip and Popover
compositions. Avatar, author, timestamp, delivery metadata, attachments,
Markdown parsing, scrolling, virtualization, selection coordination and network
mutation belong to Message, Message Scroller, Attachment or application owners.

The catalogue's `ghost` and `link` values are not both Bubble variants. `ghost`
is a Bubble variant; `link` belongs to composed Button/content interaction.
Likewise `icon-xs` and `xs` are Button sizes, `top` is a reaction side and
`type=button` is the rendered content role. The Flutter Bubble API does not
blindly duplicate those child-control props.

Acceptance requires:

- live host palette, font and radius, including light/dark/custom changes;
- hover, pressed, focus, disabled, selected, busy and invalid/error information
  for interactive content or composed controls, with meaning beyond color;
- Enter activation for links, Enter/Space for buttons, visible exterior focus,
  pointer and touch input, and borrowed FocusNode lifecycle;
- descriptive single-node semantics for static emoji reactions and independent
  names/states for interactive reaction controls;
- 48px touch hit bounds without enlarging desktop artwork, inherited text
  scaling, narrow wrapping, RTL logical positioning and reduced motion;
- direct use in exhaustive styleguide examples plus focused component,
  composition and styleguide tests;
- an explicit app-usage audit that preserves later Message/Attachment ownership.

## CSS-to-Flutter mapping

| Base-nova source | Flutter mapping |
| --- | --- |
| `relative flex w-fit max-w-[80%] min-w-0 flex-col gap-1` | `DBubble` uses parent `LayoutBuilder` constraints, content-sized children, an 80% maximum and 4px internal part gap. |
| `data-[align=end]:self-end` | `AlignmentDirectional.centerStart/centerEnd`; RTL mirrors logical alignment. |
| ghost `max-w-full` | Ghost removes the 80% cap but does not force sparse content wider than it needs. |
| content `rounded-xl border border-transparent px-3 py-2` | Host radius ×1.4, a 1px transparent/border stroke, 12px horizontal and 8px vertical padding. Ghost removes radius, border and padding. |
| `text-sm leading-relaxed wrap-break-word` | Host font family, `DiscourseTypography.sm` (14px), 1.625 leading (22.75px) and Flutter wrapping within logical constraints. The inherited `TextScaler` is the sole scaling owner. |
| primary/secondary/muted/outline/destructive | `DTokens` semantic primary, muted, background, border and destructive roles; opacity multiplies the token's existing alpha. |
| tinted OKLCH primary derivation | Flutter derives a live soft tint by blending the host background and primary. The blend is 12%/18% hover in light and 24%/30% hover in dark. This preserves arbitrary site palettes without hardcoded light/dark swatches; exact CSS OKLCH channel rewriting has no stable Flutter theme primitive. |
| interactive hover plus `focus-visible:border-ring ring-3 ring-ring/50` | Pointer state updates the variant fill. An outside-only 1px focus border and 3px 50%-alpha ring avoid tinting translucent content. |
| group `gap-2` | `DBubbleGroup` uses 8px spacing. |
| reactions `absolute ... gap-1 rounded-full bg-muted px-1.5 py-0.5 text-sm ring-3 ring-card` | Edge-positioned row, 4px gap, pill radius, muted fill, 6×2px static inset, 14/20px text and an exterior 3px live-background ring. |
| reactions `top/bottom`, `start/end`, 75% translate | Static rows use the exact 75% edge translation. Interactive Flutter rows use 45% so the center remains within Flutter's bounded hit-test area while visibly overlapping the edge; their composed button retains its full native target. |
| `has-[button]:p-0` | `DBubbleReactions(interactive: true)` removes the static emoji inset so Button owns its compact surface and state. |
| polymorphic `render` as button/link | `DBubbleContentAction.button/link`, caller callback, controlled busy/disabled/selected/invalid state and an owned-or-borrowed FocusNode. |

## Composition and accessibility decisions

Static `DBubbleContent` remains presentational and participates in any enclosing
selection owner. Interactive content uses actual Flutter focus, shortcuts,
semantics and gestures, and disables selection only for its own action surface.
Busy state blocks activation and adds a spinner plus live semantic value;
selected state adds a check; invalid state adds an error icon, exterior border
and caller-provided error value. Error/destructive examples also retain explicit
error text, so meaning never relies on color or an icon alone.

`DBubbleReactions.semanticLabel` creates one image semantic and excludes its
ambiguous emoji/count descendants, matching the frozen ARIA guidance. For
interactive rows the label is omitted and each DButton supplies its own label,
count, selected marker, disabled/busy/error state and callback. Tooltip and
Popover wrap those separately actionable controls rather than turning the full
bubble into a competing action.

The documented Show More example composes accepted `DCollapsible` state and
focus restoration. Tooltip uses accepted `DTooltip`. Popover source preparation
uses review pin `d99562f0f6973c9dc3f566eea02d9b00c6de4f7b` from
`codex/review-popover`, reviewer `01a08558-ae1e-7843-8cff-7221a399ea5c`.
That pin includes implementation `b410f9da`, lifecycle fix `8281dda2`, and its
recorded 100-test source evidence, but is not claimed accepted. Bubble's reviewer
must wait for Popover's accepted local-main merge, integrate current main and
verify overlap before Bubble can merge.

The frozen link/button and reaction demos use Sonner only to report an action.
The source-ready examples expose a local live result rather than inventing a
second notifier. Toast reviewer `01a08592-b1eb-7ad2-bebb-3ddea00f2702` owns the
actual DToast surface; Bubble review must reconcile and complete the final Toast
composition after that accepted owner lands.

## Application audit

`ChatMessageTile` is the main ordinary chat surface, but it currently owns
Discourse's speaker/chained row, avatar, CookedHtml/preview rendering, selection
keys, uploads, edit/pin/bookmark/delivery state, thread summary, long-press and
hover actions, virtualization assumptions and async permissions. Replacing that
entire row in Bubble would pre-empt the later Message and Message Scroller tasks
and risk Markdown, selection and streaming behavior, so it is retained.

Chat `ReactionPill` is likewise specialized: it owns site emoji lookup, async
toggle guards, reactor loading, touch sheets, hover panels and permissions.
It remains until the later Message composition can adopt Bubble around it; the
generic reaction boundary accepts arbitrary independent controls without
importing those models. Topic-post reaction presentation is retained for the
same site-emoji, permission and reactor-surface reasons. Voice room chat remains
a compact `ListTile` backed by its own room controller and will be revisited by
Message rather than partially restyled here. Quoted replies and post bodies are
not bubble surfaces. No safe existing production migration is therefore made
in this task.

Attachment task `01a085d4-9afd-7082-8081-f8b1f8f66287` keeps media/upload/action
ownership separate. Bubble accepts any child composition but does not render or
mutate Attachment models.
