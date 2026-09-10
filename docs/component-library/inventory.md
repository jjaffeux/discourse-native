# Existing controls and migration plan

Inventory captured at foundation base `956fd40689256e8e8393129fe023f623810cbf28`.
The machine-readable [inventory](inventory.json) includes matching files and line
numbers for core, plugins and the full profile. Line numbers are snapshot
locations, not permanent links. Every component task must also search the
current tree for appropriate adoption; this inventory is a starting point.

| Existing owner | Catalogue destination | Existing application requirements |
| --- | --- | --- |
| `theme/d_button.dart` (`DButton`, 108 source files) | Button | 11 app variants; icons, inset hit targets, loading, shortcut tooltip, custom radius/background, semantic labels, focus nodes. Preserve permission and busy guards in callers. |
| `theme/d_tooltip.dart` (`DTooltip`, 7 files) | Tooltip | RawTooltip lifecycle, long press, rich shortcut hints, hidden-pane suppression, live theme. |
| `theme/d_tooltip.dart` (`DKbd`, `DShortcutKeycaps`, `DShortcut`) | Kbd | Platform modifier labels, shortcut sequences, keycap progression and semantics. Extract the shared owner before Tooltip. |
| `shell/select.dart` (`DSelect`, `DSelectField`, 8 files) | Select | Controlled dropdowns and form selection in Preferences, Poll, Local Dates, Chat, Assign and Voice. All callers use the public `DSelect` owner. |
| `shell/adaptive_activity_indicator.dart` | Spinner | Apple activity indicators and Material stroke/color options; retain native platform styling. |
| `shell/adaptive_dialog_action.dart`, `shell/shell_sheet.dart`, app-specific sheets and dialogs | Button, Dialog, Alert Dialog, Sheet, Drawer | Focus/route ownership, async results, destructive confirmations, retained drafts and native modal adaptation. |
| `shell/anchored_picker.dart`, `shell/choice_menu.dart`, `shell/command_menu.dart` | Popover, Select, Command, Combobox, menus | Anchoring, keyboard navigation, large/searchable lists, cleanup and site lifecycle ownership; business logic stays in adapters. |
| `shell/avatar_image.dart` | Avatar | Authenticated image loading remains an app adapter; fallback, clipping, sizing and group presentation belong in the generic library. |
| `shell/empty_state.dart` | Empty | Retry / action callbacks and explanatory text; business status stays in callers. |
| `shell/resizable_pane.dart` | Resizable | Desktop pane constraints, pointer resize, persistence adapter; add reference keyboard and multi-panel behavior. |
| `shell/forum_tabs_bar.dart`, topic/group/preferences tabs | Tabs | Navigation and unread/domain state remain app-owned. Generic widget owns layout and focus only. |
| Calendar and date/time controls in Local Dates, bookmarks and events | Calendar, Date Picker | Existing `foundation/calendar_day.dart` owns civil-day logic; plugin timezone and API behavior stay outside UI. |
| Flutter input/form, checkbox/radio/switch, slider controls | Corresponding fields and controls | Form validation, permissions, busy state, selection retention and native text editing. |
| Flutter menus, SnackBars, tables, cards, scroll areas and inline notices | Menus, Toast, Table, Card, Scroll Area, Alert | Audit both `lib/src/shell/` and `lib/src/plugins/`, including inline compositions. |
| Chat attachment, message, stream and input UI | Attachment, Bubble, Marker, Message, Message Scroller, Input Group | Presentation is reusable; optimistic sending, transport, upload ownership and timeline merging remain in Chat. |

The foundation temporarily exports the three baseline controls through
`discourse_ui.dart` to give the styleguide real interactive app widgets before
individual implementation begins. The owning component tasks must move/replace
these implementations, update imports and SDK exports, and remove obsolete
owners. A networking avatar or content composer is not made generic by moving
its existing file; split its reusable presentation from its app adapter.
