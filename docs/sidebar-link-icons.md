# Sidebar link icons

Custom sidebar links and Community More links resolve bundled core/plugin icons
first. Other names load from the connected forum's public
`/svg-sprite/:hostname/icon/:name.svg` endpoint. This uses the server's solid,
regular (`far-`), brand (`fab-`), additional, plugin and default-theme artwork
without shipping a fixed subset of those choices in the native application.

`SidebarIconLoader` requests only valid links accepted by the sidebar model,
deduplicates their icon names and loads at most four at once. A failed artwork
request leaves the link usable with its existing fallback. Successful symbols
are cached per full forum URL for one day, bounded to 256 entries and two
million characters. SVG references to sibling symbols are included as local
definitions; missing dependencies and cyclic references use the fallback.

`DIcon` and `DIconData` are exported by `discourse_ui.dart`. Bundled icons retain
the existing monochrome behavior. Server artwork opts into
`DIconData(..., preserveColors: true)`: explicit SVG colors are preserved,
`currentColor` uses the icon foreground, and Discourse's primary, secondary,
tertiary, quaternary, danger and success color variables follow Native theme
tokens. The secondary background keeps composite badge details visible.
Icon-theme opacity is applied while compiling the SVG, without a runtime color
filter. The Sidebar styleguide's **Server icon colors** example demonstrates
foreground tinting, composite badges and custom colors.

Regression coverage includes public/authenticated sidebar responses, subfolder
forums, cache isolation, failure recovery, composite dependencies, painted
foreground/background/custom colors, theme changes and opacity. The Native
sidebar rendering tests exercise light/dark themes at 220px and 320px widths.

On 2026-09-14 an isolated macOS debug fixture was also built and inspected with
native screenshots and accessibility. It mounted the real sidebar menu rows
with loader-produced solid, regular, brand, composite and custom SVGs, plus the
registered styleguide example. Light/dark themes, 240px/320px rows, selected
states and pointer activation were checked. The fixture used local responses
and no user account; iOS and Linux were not run as native applications.
