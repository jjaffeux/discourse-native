# Keyboard dismissal audit

Audit date: 2026-11-03.

Three focus lifecycle defects reproduced in widget tests. All involve content
that remains mounted after it closes or becomes hidden.

## Confirmed defects

### Closing anchored popovers retained input focus

`_DPopoverState._setOpen(false)` started the exit animation without disabling
the content's focus scope. An input remained focused and connected to the text
input service during that animation. A deferred focus request could also focus
the closing input again.

The regression test opened a popover containing an autofocused `DInput`, closed
it, and checked focus before the reverse animation completed. Before the fix,
`focus.hasFocus` was still `true` when the expected value was `false`.

The popover now disables its content scope as soon as its logical open state
changes. The scope remains disabled throughout the exit animation. Reopening
enables it again. Existing focus restoration to the trigger or another visible
input remains available.

This fix also covers anchored `DDropdownMenu`, `DContextMenu`, `DCombobox`, and
`DSelect` content, which use `DPopover`. Editable combobox anchors have their own
focus ownership and may intentionally keep the keyboard open.

Popover synchronization now also requests a frame. A post-frame callback alone
can remain pending when the application is idle. The existing controlled
popover lifecycle test protects resynchronization after resume.

### Full-screen composers left hidden reader inputs focused

`_ComposerDockState` retained the reader in an `Offstage` widget when the
composer entered full screen. `Offstage` preserves focus. A focused reader
input therefore stayed focused while invisible and could accept another focus
request.

The regression test focused a reader `DInput`, entered full screen, and checked
that the input lost focus. Before the fix, `readerFocus.hasFocus` remained
`true`. The test also checks that a late request fails while hidden and succeeds
after the reader becomes visible again.

The retained reader now contains an `ExcludeFocus` whose state moves with the
reader's existing global key. That placement matters: inserting a new disabled
ancestor around an already-focused subtree did not clear existing focus in the
regression test.

### Compact navigation left its hidden sidebar focusable

`DesktopNavigation` used `Offstage` alone when the full sidebar was hidden.
The regression test focused a sidebar `DInput` and switched to compact
navigation. The input remained focused. A stable `ExcludeFocus` now clears
focus when the sidebar hides and prevents later requests until it is revealed.

## Paths checked

| Owner | Dismissal and focus behavior | Evidence |
| --- | --- | --- |
| `ForumSearch.page` and `_MobileContentHost` | Cancel, Back, rapid Back during opening, sidebar, site change, replacement, topic navigation, Home, and panel change | `test/keyboard_dismissal_lifecycle_test.dart`, on iOS and Android |
| `ForumSearch` full-screen Navigator fallback | Cancel releases the input connection before the exit completes | `test/keyboard_dismissal_lifecycle_test.dart` |
| `DDialog` and `DSheet` | Closing route blocks retained input focus, including a late request during the reverse transition | `test/keyboard_dismissal_lifecycle_test.dart`; route focus policy in Flutter |
| `DDrawer` | Closing route blocks retained input focus | `test/keyboard_dismissal_lifecycle_test.dart` |
| Anchored `DPopover` | Closing content loses focus and rejects a late focus request | Regression above; existing popover and imperative host suites |
| Full-screen composer reader | Hidden input loses focus, rejects another request, and works after reveal | Regression in `test/composer_docking_test.dart` |
| Compact desktop navigation | Hidden sidebar input loses focus, rejects another request, and works after reveal | Regression in `test/keyboard_dismissal_lifecycle_test.dart` |
| Minimized and parked composers | Retained editor content uses `ExcludeFocus`; controller disposal releases body and title nodes | Source trace in `composer/presentation.dart`, `composer/controller.dart`, and `composer_registry.dart` |
| Retained mobile pages, panels, headers, and topic underlays | Hidden content uses `ExcludeFocus`; history previews exclude focus or contain raster images | Source trace in `mobile_content_host.dart`, `mobile_shell.dart`, `d_sheet.dart`, and `d_history_transition.dart` |
| Tabs and collapsible input containers | Removed tab panels detach their scope; collapsed content excludes focus during its exit | Source trace in `d_tabs.dart` and `d_collapsible.dart` |
| Plugin forms and pickers | Search, assignment, chat, emoji, GIF, poll, math, local-date, event, and other autofocus callers use the shared route, popover, or retained-page owners above | Focus-request inventory and source trace; each plugin flow was not exercised individually |

## Verification boundary

The tests check focus ownership, text input visibility, and client disconnection
through Flutter's test text input service. They do not measure native iOS or
Android keyboard animation or reproduce a physical device's intermittent
failure.

The mobile search paths tested here release the keyboard correctly. The three
confirmed defects do not establish the cause of every reported search failure.
Picker dismissal can intentionally restore focus to a visible composer, which
keeps its keyboard open.

The directly related test command is:

```sh
flutter test --no-pub test/keyboard_dismissal_lifecycle_test.dart test/d_popover_test.dart test/d_popover_host_test.dart test/composer_docking_test.dart
```

Four existing assertions in `composer_docking_test.dart` also fail without these
changes: mobile placement spacing, the mobile close button shape, and the two
picker geometry cases. Their baseline failures are an 8-point gap where more
than 21 was expected, a rounded button where a pill was expected, and a picker
coordinate of 619 where 608 was expected.

The final checkout run of the search and overlay suites passed all 67 tests.
The four-suite run in an identical source copy passed 136 tests, including the
new composer regression, with the four baseline failures above. Static analysis
of the changed Dart files reported no issues.

An intermediate combined checkout run also hit Flutter semantics geometry
assertions. The isolated run and the final checkout search and overlay run did
not reproduce those assertions. Their cause was not established.
