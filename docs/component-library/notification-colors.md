# Core notification colors and header capsules

Source audit: `/Users/joffreyjaffeux/Code/pr-discourse`, commit
`438ea4dea8ccc4d5f7bc8460b46fc16d29bff65a`, 2026-09-13.
These are theme roles; purple, green and red are not hardcoded universal values.

| Scenario | Core role | Native treatment |
| --- | --- | --- |
| Ordinary unread header notifications, including topic mentions/replies | `--tertiary-med-or-tertiary` | Soft count capsule |
| Personal-message notification | `--success` | Bell capsule; takes priority over reviewables and ordinary unread |
| Reviewable notification | `--danger` | Bell capsule; takes priority over ordinary unread |
| Ordinary unread public chat / unread thread | `--tertiary-med-or-tertiary` | Header dot |
| Chat DM unread, mentions, watched-thread unread | `--success` | Header count capsule; urgent drawer/thread/tab indicators |
| New topic, new replies, unread post count | `--tertiary-med-or-tertiary` | Topic dot or solid numeric badge |
| Ordinary sidebar unread | `--token-color-background-accent-subtle` | Sidebar dot; plain sidebar numeric counters retain neutral text |
| Unseen pinned chat messages | `--tertiary-med-or-tertiary` | Chat activity dot |
| Mention in message content | `--primary-low`; current user `--tertiary-400` | Existing mention highlight roles, independent of notification counts |

Core sources relative to that checkout:

- `app/assets/stylesheets/common/base/header.scss`: PM, reviewable and ordinary badges.
- `frontend/discourse/app/components/header/user-dropdown/notifications.gjs`: PM > reviewable > ordinary priority. Core renders PM/reviewable icons; Native retains its existing aggregate bell count.
- `plugins/chat/assets/stylesheets/common/chat-unread-indicator.scss`: ordinary/urgent chat roles and `--secondary` text.
- `plugins/chat/assets/javascripts/discourse/components/chat/header/icon/unread-indicator.gjs`: count, cap and preference policy.
- `plugins/chat/assets/javascripts/discourse/components/chat-channel-unread-indicator.gjs`: direct/public urgent totals.
- `plugins/chat/assets/stylesheets/common/chat-pinned-bar.scss`: unseen pinned-message indicator uses the ordinary mixin.
- `app/assets/stylesheets/common/components/badges.scss`: topic state and unread-post badges.
- `app/assets/stylesheets/common/base/sidebar.scss` and `common/base/sidebar-section-link.scss`: ordinary and urgent sidebar suffix roles.
- `app/assets/stylesheets/common/tokens.scss` and `common/foundation/color_transformations.scss`: theme-role resolution.

## Count policy

Chat already supports numeric urgent counts. Public channels contribute mentions
and watched-thread unread counts; direct channels also contribute unread messages.
“All new” shows an urgent count first, otherwise an ordinary unread dot. “DMs and
mentions” shows urgent counts only. “Only mentions” counts mentions only; “Never”
hides indicators. Existing Do Not Disturb behavior suppresses chat indicators.
Counts greater than 99 display `99+`; accessible labels retain the exact total.

The bell retains Native's aggregate of unread notifications, personal messages
and reviewables, with the core color priority above. Chat's count is separate.
This change preserves the existing notification selection and popup behavior.

## Palette and presentation

`DiscourseColors.notificationIndicator` is separate from `unreadIndicator`:

- Header/chat/topic: light `--tertiary-medium`, dark `--tertiary`.
- Sidebar: light `--tertiary-600`, dark `--tertiary`.
- Explicit global overrides of either semantic CSS token take precedence.
- The additional resolved palette value survives serialization and theme
  transitions. Older cached palettes remain readable and use their tertiary
  value until refreshed.

The chosen capsule is an intentional Native presentation: 14% tint, 22% hover
tint, a matching hue adjusted for legible text, one focusable button, and no
floating numeric overlay. It uses existing Native controls without adding a kit
API. Solid numeric badges retain core's `--secondary` foreground.

The parser reads supported global theme/palette declarations. It does not import
arbitrary selector-specific theme CSS; for example `wcag.scss` overrides some
solid core badges to `--tertiary`, which is not a separate Native theme mode.
Capsule text contrast is independently checked on its normal and hover fills.

The interactive HTML study is `docs/mockups/notification-counts.html`. Its
swatches illustrate Native's default palettes; actual site themes supply live
role values in the application.

At narrow macOS widths with large text, account actions use a second header row
below the window controls. Dense search omits its navigation buttons when they
would squeeze the editor; keyboard navigation remains available. Capped numeric
text stays LTR inside an otherwise mirrored RTL capsule.
