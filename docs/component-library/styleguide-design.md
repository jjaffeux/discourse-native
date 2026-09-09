# Documentation design correction

The user reviewed the original Flutter styleguide on 2026-09-09 and requested
much closer fidelity to shadcn. They then explicitly prioritized implementing
Sidebar before using it in the styleguide. This follow-up covers that component
and the documentation shell; the remaining component queue stays paused.

## Reference

Inspected the rendered [official Card documentation](https://ui.shadcn.com/docs/components/base/card)
and [component catalogue](https://ui.shadcn.com/docs/components) on 2026-09-09.
The reference browser was in dark mode. DOM measurements establish:

| Reference | Documentation implementation |
| --- | --- |
| 30px navigation rows with 2px gaps; 12.8px type | DSidebarMenuButton with 30px minimum visual height; 13/18px host-font text and compact grouping |
| 30/36px page title, 600 weight, −0.75px tracking | Explicit matching title metrics |
| 16/24px muted introduction | One-sentence ComponentExamples.description |
| 640px article | Bounded, centered content with responsive outer padding |
| Neutral background, quiet selection, separate scrolling navigation | Local documentation DTokens theme and actual DSidebar composition |
| 1px preview border and 18px radius | Rounded preview/code panel with centered sample content |
| Small controls and code disclosure | Compact theme/width toolbar, optional advanced settings, reset, code reveal and copy |
| Right-hand page navigation | Example selection plus functional usage/notes links on wide windows |

The app font remains the configured host font, rather than loading the website's
Geist font. On macOS the header reserves space for native traffic lights. Touch
platforms receive accessible interaction targets; large text can grow controls.
These adaptations do not replace component geometry with Material defaults.

## Composition and state

The documentation shell uses DSidebarProvider, DSidebar, DSidebarContent,
DSidebarGroup, DSidebarGroupLabel, DSidebarMenu, DSidebarMenuItem,
DSidebarMenuButton, DSidebarHeader and DSidebarTrigger. The sidebar is 240px on
desktop; below 900px the shared modal navigation owns focus and dismissal.
Cmd/Ctrl+K opens navigation when necessary and focuses its search field. Selection
closes mobile navigation while retaining the search. No custom navigation
renderer remains in the styleguide.

The header's light/dark toggle changes only the documentation canvas. Preview
palettes resolve from the original app ThemeData, with local light/dark/Forest/
Plum overrides. Their nested Navigator preserves overlays and sample state;
preview settings, code disclosure and window resizing do not reset examples.
Reset intentionally remounts the selected example. Palette changes and example
data never persist to app settings.

Implementation status no longer adds a second line to every navigation item.
Unimplemented pages explain their pending state, and Button/Select retain a
visible baseline notice. Detailed implementation notes and frozen reference
coverage are available below each example. The foundation example composes the
actual Card and existing Button with theme swatches. Compact documentation
controls are styleguide-only native adapters; pending catalogue controls are
not marked complete by this correction.

## Verification

Final checks and native comparison are being completed on the integrated
Sidebar and documentation source. Exact commands, native states and remaining
limits will be recorded here before the local-main merge.
