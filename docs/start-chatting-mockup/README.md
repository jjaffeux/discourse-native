# Start chatting — desktop mockup

Open `index.html` directly, or serve this directory with any static HTTP server.
No build, dependencies, remote fonts, network requests, or account data.

The initial view shows recent direct conversations and a group-chat action.
Type a name or “design” to explore grouped results. Arrow keys select, Return
opens a simulated conversation or adds a recipient, and Escape dismisses.
Cmd/Ctrl+K toggles the palette. The preview toolbar switches light/dark appearance.
Group creation supports removable recipients, an optional name, and a sample
10-person limit. Search and creation use local fixtures only.

## Native implementation mapping

This is an HTML/CSS design artifact, not an application implementation. It
models existing public components without changing or extending the UI kit:

| Mockup | Native component |
| --- | --- |
| Palette shell (520px) | `DCommandDialog(maxWidth: 520)` |
| Search, grouped results, active row | `DCommand`, `DCommandInput`, `DCommandList`, `DCommandGroup`, `DCommandItem` |
| Empty result and group/action divider | `DCommandEmpty`, `DCommandSeparator` |
| Initial avatars and group icons | `DAvatar(size: DAvatarSize.sm)`, `DIcon` |
| Close, back, removable recipients, start group | `DButton` / `DButton.iconOnly`, regular or small presets |
| Optional group name | `DInput` |
| Keyboard hints | `DKbd` |

The design uses the existing 288px list cap, 8px row highlights, outlined inputs,
28px buttons, and palette-derived button treatments. Identity rows are 36px to
accommodate 24px avatars with breathing room; `DCommandItem` already supports
intrinsic child height above its 32px minimum. A 6px vertical inset around its
avatar plus the existing list spacing can supply the native composition.

The app adapter should retain existing remote search ranking with
`shouldFilter: false`, debounce/generation guards, permissions, server group
limits, and conversation-opening behavior in `chat_new_direct_message.dart`.
Recents here are representative fixtures; no new public-channel search is implied.
Native loading, errors, stale conversations, and permission failures remain
implementation work. The desktop preview toolbar is outside the product design;
the prototype dialog is nonmodal so appearance controls remain available.

## Implemented version

The Native implementation and its validation are recorded in
[Start chatting command palette](../start-chatting-command.md).
