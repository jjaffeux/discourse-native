# Command reference and source-preparation evidence

## Frozen scope and reference mapping

- Frozen documentation: `https://ui.shadcn.com/docs/components/base/command.md`, fetched 2026-09-09 and verified byte-for-byte against catalogue SHA256 `1a810090b9cc629efe885d8795365280c2653fdf3e0f5d20f4ac2354b876a4b6`.
- Official rendered page: `https://ui.shadcn.com/docs/components/base/command`.
- Official base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/command.json`. It composes cmdk, Dialog and Input Group. Flutter uses the already accepted Input (`DInput`) and Scroll Area (`DScrollBar`) owners, the prepared Dialog API pinned below, and ordinary leading/trailing child composition in place of the still-planned Input Group.
- Behavior API: `https://github.com/dip/cmdk`. The mapped root behaviors are query and highlighted-value state, scored default/custom filtering, keyword aliases, filtering opt-out, disabled items, optional looping, pointer-highlight opt-out, Ctrl-N/J/P/K bindings, dynamic collections, activation, and scroll-to-highlight.

The base-nova source maps to Flutter as follows:

| Reference | Flutter mapping |
| --- | --- |
| root `p-1`, rounded-xl popover | `DCommand`, 4px padding, live `DTokens.surface`, proportional token radius and optional outline |
| 32px inset search group | `DCommandInput` composed from `DInput`, 16px search suffix and native TextEditingController/FocusNode/IME ownership |
| list `max-h-72`, scroll padding | `DCommandList`, 288px cap and borrowed/owned `ScrollController` through `DScrollBar` |
| group `p-1`; heading `px-2 py-1.5 text-xs` | `DCommandGroup`, 4px group inset, 8x6 heading inset and 12px medium muted text |
| item `gap-2 rounded-sm px-2 py-1.5 text-sm` | 32px desktop row, 8px horizontal gap/inset, 14/20 text and token radius; iOS/Android receives a 48px hit row without changing the 32px artwork |
| selected muted surface; disabled 50% | persistent keyboard/pointer highlight, visible focus border, disabled semantics and activation suppression |
| trailing shortcut/check | logical trailing `DCommandShortcut`; checked indicator is hidden when a shortcut is supplied |
| edge-to-edge CommandDialog, top-third | `DCommandDialog` composes `DDialog`/`DDialogContent` with zero content padding; native safe-area centering is retained rather than introducing a second modal owner |

## Acceptance criteria

1. Export `DCommand<T>`, `DCommandController<T>`, input/list/group/item/separator/shortcut/empty/loading parts, and `DCommandDialog<T>` from `discourse_ui.dart`; keep all generic source independent of networking, stores and application state.
2. Support controlled or internally owned query/highlight values, explicit borrowed controller lifetimes, values and keyword aliases, stable scored filtering and custom filters, `shouldFilter: false`, disabled/checked/forced rows, dynamic result updates and caller-owned loading state.
3. Preserve native text editing, selection and composing ranges while Arrow Up/Down and Ctrl-N/J/P/K move the visual highlight; Return activates, looping is optional, disabled rows are skipped and every movement scrolls into view. Escape is handled only when supplied so an enclosing Dialog retains dismissal ownership.
4. Match the frozen base-nova geometry and semantic token roles while responding live to host font, palette, radius, direction, scale and reduced-motion changes. Provide mouse hover/press/focus, touch activation and 48px touch targets.
5. Provide one ordinary embedded composition and runnable Basic dialog, Shortcuts, Groups, Scrollable, custom filter/loading/dynamic and RTL examples using only the public widgets.
6. Audit the core and bundled plugins. Migrate the existing reusable anchored `CommandMenuAnchor` row renderer to `DCommand` while retaining anchoring, route result, callbacks, permissions and business ownership. Retain choice/select/combobox/editor owners only for distinct semantics noted below.
7. Pass formatting, focused component/styleguide/adoption tests, affected regression tests and root plus full-profile static analysis. Prepare exact source/build evidence and hand remaining rendered/native acceptance to a new independent reviewer.

## State, focus and lifecycle decisions

- `DCommandController<T>` owns query and highlight only. A borrowed controller is attached to one root and never disposed. `DCommandInput` separately owns or borrows its editing controller and focus node; `DCommandList` separately owns or borrows its scroll controller.
- `query`/`value` are parent-controlled inputs. `initialQuery`/`initialValue` seed local state. Change callbacks receive every user/imperative request. `onSelected` owns domain action dispatch; the generic component does not close an overlay or start asynchronous work.
- Flutter cannot introspect visible text from an arbitrary child widget. `DCommandItem.searchValue` therefore defaults to `value.toString()` and must be supplied when those differ; this is the only intentional API adaptation from cmdk's DOM text inference.
- Filtering is synchronous like cmdk. External/server filtering uses `shouldFilter: false`, updates the rendered items, and may set `loading`; request cancellation and stale-result protection remain with the caller.
- Arrow navigation stays on the native editor (cmdk's active-descendant pattern) rather than focusing rows. Tab may focus an individual accessible row, whose Return/Space activation remains available. The root focus node is not an extra traversal stop.
- Theme/direction/media values are read during every build. No query, editing, highlight or scroll state is keyed to those values, so a live theme/radius/font/RTL/reduced-motion rebuild does not reset interaction state.

## App and plugin audit

- Migrated `lib/src/shell/command_menu.dart`: the existing `CommandMenuAnchor<T>` and `showCommandMenu<T>` keep their route, transparent barrier, anchor geometry, result and application callback ownership. Its private Material `MenuItemButton` row renderer is replaced by public `DCommand<T>`, `DCommandList<T>`, groups/items/separators and generic destructive styling. Existing core topic/group actions and Chat add actions inherit the component without moving permissions, stale-result guards or async/domain callbacks.
- Retained `anchored_picker.dart`: this is a picker/combobox owner with selected-value and anchor semantics, not a command palette. The later Combobox task will compose the accepted Command API.
- Retained `choice_menu.dart` and `DSelect`: these expose finite choice/form selection and checked-value semantics rather than query/action-command behavior.
- Retained composer autocomplete, emoji/GIF pickers, global topic/Chat searches and slash-command parsing: these own domain networking, token replacement, content editing, async pagination or search navigation. Their adapters are candidates only when the later Popover/Combobox owners can preserve those semantics.
- No obsolete generic command implementation remains: the former reusable shell renderer is now an application overlay adapter over the public component.

## Dependency and review gate

Source preparation started from local main `6fbecbce` and integrated exact prepared Dialog review commit `8a80078316381a60f70b4e11adbc919814ca9fbc` from `codex/review-dialog` in merge commit `778539e2`. Parent evidence supplied by its reviewer: 23 focused Dialog/styleguide tests passed with seed 2145466268; root/full-profile analysis and Chat/Voice migrations passed; rendered light/dark/RTL/scrollable comparison completed; source hash `f438edbbc8b0484044389d3df603bf09212ee40ad680628af930557563b80b5e`; kernel `e489581e461a53c05d287eb7a51f706b6c458cc769f84626210b7fc7391f8350`; native interaction was still queued. This records prepared source, not parent acceptance.

Command adds optional `contentPadding`, `verticalPadding` and `spacing` to `DDialogContent`, preserving all existing defaults, solely to support the official edge-to-edge composition. The Command reviewer must wait for Dialog's accepted local-main merge, integrate current main, reconcile this overlap with the accepted parent and rerun affected Dialog/Command behavior. An unaccepted Dialog revision must never enter main through Command.

## Source verification and remaining native acceptance

The implementation task verified the frozen hash and inspected official HTML, Markdown, registry source and cmdk API. Focused tests cover keyword/empty filtering, scored ordering/filter opt-out, controlled callbacks, IME-preserving keyboard activation, disabled suppression, loading, borrowed lifetimes, RTL, narrow 200% examples, Dialog Escape/restoration, and the migrated group-member command adapter. The affected topic action hover/placement test was updated for the public row renderer and passes independently. Exact commands and final commit/build hashes are recorded in `progress.json` after source verification.

No browser screenshot comparison, macOS native launch, spoken VoiceOver run, iOS device run or Linux device run is claimed by this implementation task. The new reviewer owns the first official rendered comparison and native Command/Dialog checks (query/IME, keyboard selection, Escape layering/restoration, pointer/touch actions, live themes while open, narrow/scaled/RTL and reduced motion) after the accepted Dialog parent is on main.
