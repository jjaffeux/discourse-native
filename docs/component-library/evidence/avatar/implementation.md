# Avatar reference and adoption

Frozen scope: https://ui.shadcn.com/docs/components/base/avatar, Markdown
SHA256 `921178487423ff56f4de4aa29b09541733b59359ae746fe63a8b765ae8b153d9`.
Supporting registry: https://ui.shadcn.com/r/styles/base-nova/avatar.json,
SHA256 `bbcabf0121fb2ff93a8522f8f80b74631e732a31399b1b7991c0b8c3167e2172`.
Supporting API: https://base-ui.com/react/components/avatar.md,
SHA256 `5e80eb32fc360bedbdf57fef0965f124bb1442c373ec97d730a839e0d7c06f99`.
Decoded registry avatar.tsx SHA256: `bff76087ea9af25c6aa5a5306088dc66e62204a126752c38561736acff00717f`.
Sources retrieved 2026-09-08. Registry/API support the frozen scope; they do not
add catalogue entries.

| Reference | Flutter mapping at 100% |
| --- | --- |
| Avatar size-6 / size-8 / size-10 | DAvatarSize.sm / standard / lg = 24 / 32 / 40 logical px |
| rounded-full | circular clipping; explicit borderRadius supports existing forum brand and user-directory site-radius requirements |
| after:border-border, darken/lighten | 1px inset foreground-painted border using live DTokens.border and corresponding Canvas blend mode |
| fallback bg-muted / text-muted-foreground | DTokens.muted / mutedForeground; configured font family |
| fallback text-xs / text-sm | unscaled DiscourseTypography 12px/16px line height for sm, 14px/20px otherwise; regular weight, zero tracking |
| badge size-2 / 2.5 / 3 | 8 / 10 / 12px; bottom trailing edge; 2px background ring, primary/onPrimary colors |
| badge svg | 8px plus artwork; sm hides Icon; custom dimension allows app counts |
| group -space-x-2 | 8px overlap, later children above earlier children, mirrored in RTL; 2px background rings |
| group count | 32px default, 24/40 with small/large siblings; 14px text at every size, icons 12/16/20px |
| Base UI Image/Fallback | caller-supplied ImageProvider, first decoded frame replaces fallback, errors restore fallback, optional fallback delay, loading/ready/error callback |
| className / render | ordinary child widgets, size/dimension, colors, radius, badge and semantic label; action owner wraps the avatar |

Native adaptations are deliberately bounded:

- Above 100% text scale, enum-sized avatars/counts reserve proportionally larger
  boxes. Two 12px initials do not fit a 24px circle at 200%. Reserving that space
  before image decoding avoids a loading/error identity becoming clipped or a
  ready image changing the layout when its fallback appears. Image boxes grow
  too for this reason. Explicit dimensions and DAvatar.frame preserve existing
  application gutter/row contracts. The font itself uses only Flutter's scaler.
- Narrow groups wrap complete identities rather than shrinking or overflowing.
  Default groups preserve direct avatar sizes and explicit dimensions. A supplied
  group size overrides descendant size metrics, while explicit dimensions remain
  authoritative. Wrapped action children reserve the group's inferred extent;
  callers should supply a group size matching that action's visual avatar.
- Badge placement is trailing rather than physical right so Arabic examples
  and existing chat flair follow reading direction.
- ImageProvider resolves once through Flutter's normal stream. There is no DOM,
  SSR, lazy HTML img, or second preloading request; keepMounted is therefore not
  a Flutter prop. The generic library never imports networking or app services.
- Reference plus icons use Lucide's exact 24-unit paths, 2-unit round stroke,
  scaled to 8px in badges and 12/16/20px in counts. The explicit badge icon slot
  hides arbitrary SVG/widget artwork in small badges; child is reserved for
  counts. Official source: https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/plus.svg,
  SHA256 `7f6af73bf1ff6c4bca3f18351c8d1bdec6749c0c2530c4de5da85d520c21df17`.
  Full ISC/Feather MIT attribution is retained in lucide-LICENSE.txt.
  The final composition uses the accepted DButton and DDropdownMenu owners:
  a 32px circular ghost button around the 32px avatar, a 128px grouped menu,
  a separator and destructive Log out item. These are not Avatar variants.

Installation and Usage are covered by the public barrel import and snippets.
Composition, Basic, Badge, Badge with Icon, Group, Group Count, Group with Icon,
Sizes, Dropdown and RTL all have runnable examples. Embedded local PNG bytes
avoid package-asset path differences entirely; no assets or manifests were added.
Stateful examples retain state when inherited preview configuration changes.

## Core online ring follow-up — 2026-09-10

The public `DAvatar.ring` option now owns the online presentation previously
duplicated by Chat. The source comparison and acceptance evidence are recorded
in [ring-follow-up.md](ring-follow-up.md). It preserves the outer avatar size,
insets image/fallback content by 2px, and paints the same 1px success edge plus
1px page-color gap as Discourse core. The host maps its live site success color
into `DTokens`; callers can name the state with `ringSemanticLabel`.

## Application audit

Searched every Dart file in core and all bundled plugins for AvatarImage,
CircleAvatar, ClipOval, ClipRRect, circle decoration, groups and flair. No ClipOval remains in shell/plugins, and there are no CircleAvatar callers.

Migrated circular presentation owners in topic rows/header/list/posters/view,
participants, group membership, user activity/card/menu/summary, composer
suggestions/reply context, quotes, small actions, likes/reactions, forum search,
forum tabs/sidebar, Discourse user oneboxes, badges and grants. Chat authors,
transcripts and direct-message picker; Voice rooms/participants/incoming calls;
Assign groups/picker; Events attendees all use DAvatar presentation now.
The overlapping topic poster stack is DAvatarGroup; it now mirrors in RTL.
Rounded ForumIcon, rail/callout/sidebar logos, user-directory avatars and GitHub
attribution use DAvatar.frame with their existing deliberate radius.

AvatarImage remains the application data adapter. Its MediaPipeline and
AvatarLoader cache behavior, stale URL/pipeline guards, SVG/raster decoding and
decode rejection/reporting remain in place. Its new SizedBox reserves requested
bounds even when an icon fallback itself is smaller. Existing parent
UserCardTarget, buttons, permission guards, online listeners and async owners
are preserved. Four stock CircleAvatar fallbacks became DAvatarFallback.
Other application fallback contents/colors remain supplied by their domain
adapters (including user-directory ID palette and forum monograms).

Retained alternatives and reasons:

- Chat retains live presence subscription/state ownership and passes the
  resulting boolean to `DAvatar.ring`. GroupFlair/GroupFlairBadge retains
  server artwork/colors, 45% flair size and 10% overhang. A generic ring or dot
  badge cannot replace arbitrary transparent flair artwork without changing
  meaning.
- UserStatus emoji bubble and unread/count/recording indicators in rail, tabs,
  topic indicators, Chat headers/composer/thread/pinned rows: these are status
  or action indicators with domain-specific counts, not user identity pictures.
- Inline-video/YouTube/lightbox/image-grid/local camera previews, event cards,
  composer/shell panel surfaces, category color swatches and general onebox
  thumbnails retain rectangular clips: their content is not an avatar.
- Inbox poster rows intentionally remain adjacent individual identities at 20px;
  they are not overlapping groups. Each identity uses DAvatar.frame.
- Existing DiscourseAvatarTheme remains a site setting adapter for configured
  user-directory radii; generic UI receives the resolved radius as a value.

## Review fixture

`tool/avatar_review_main.dart` mounts the actual production AvatarImage and
ForumIcon with an in-memory MockClient, plus the public online-ring example.
Pending, HTTP error and valid PNG responses are local. The forum action uses the
real DButton owner and increments only local state. The same executable opens
the actual component styleguide. No account, store or external mutation is
involved.
