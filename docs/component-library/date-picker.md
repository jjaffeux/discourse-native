# Date Picker reference and implementation map

## Frozen source

- Catalogue reference date: 2026-09-08.
- Documentation: `https://ui.shadcn.com/docs/components/base/date-picker.md`.
- Frozen Markdown SHA256: `cedb8c5a45c2cc2cede23b564b55c7a7a3c506e5d14f6b413d7758c03a0550c6`
  (reproduced on 2026-09-09).
- Primary repository snapshot inspected at shadcn-ui/ui
  `3ba91b1cc83e1bbe4ab35a422ff2a694849c5048`:

| Base UI example | SHA256 |
| --- | --- |
| `apps/v4/examples/base/date-picker-demo.tsx` | `6e2e2191ee17d699aa3821c6fef0ef14401ef0c7a9c59241d3c50b67d71591df` |
| `apps/v4/examples/base/date-picker-basic.tsx` | `3a362e0d7d7458fe3a1a6b1267841d83145fa7028d48c14062ccab5c9a168aa2` |
| `apps/v4/examples/base/date-picker-range.tsx` | `d3a623938f4dc9f66cc89295af62947e00ba8813fd845b0fb45f395770bbe140` |
| `apps/v4/examples/base/date-picker-dob.tsx` | `55148d52178286a57bca51a6911a76fe2dd568d155e43ddc256f778f14ae6723` |
| `apps/v4/examples/base/date-picker-input.tsx` | `3f9601a170b0dc21996e761f097462bed504e3195fa801d6bcd549b3011a04a6` |
| `apps/v4/examples/base/date-picker-time.tsx` | `4a65399ebf3ddebad365e04d7a876236311fd099dcf67fd64712fc2f704b72a2` |
| `apps/v4/examples/base/date-picker-natural-language.tsx` | `cab7dd423fa2fe787417204d839edbea27935637e171ea0a72c11abbc0c3de22` |
| `apps/v4/examples/base/date-picker-rtl.tsx` | `68343f94eaa5e7cf69d7cac4a9388eefebb54a5da7cda0be4621ace06bfe772d` |

The page defines Date Picker as composition rather than a React root:
Popover trigger plus Popover content containing Calendar. The Flutter port may
offer typed convenience widgets, but the composed owners remain public and no
second calendar or overlay engine is introduced.

## Reference-to-Flutter map

| Reference composition | Exact reference behavior and geometry | Flutter mapping / acceptance |
| --- | --- | --- |
| Demo | 212px outline trigger, space-between label and inline-end chevron; auto-width zero-padding popover aligned start. | `DDatePicker` composes `DButton`, `DPopover` and the accepted Kalender-backed `DCalendar`. Empty text uses muted foreground. Directional icon order mirrors in RTL. |
| Basic | 176px vertical Field, 8px Field label/control gap, start-justified normal-weight outline trigger. Selection does not implicitly close the popover. | Actual `DField`, `DFieldLabel` and `DFieldControl`; controlled/uncontrolled date and open state, borrowed focus/controller lifecycle and explicit close policy. |
| Range | 240px Field and two-month Calendar; 10px horizontal trigger padding, 16px inline-start calendar icon; `MMM dd, y - MMM dd, y`. An incomplete range displays only its start. | Typed Calendar range value and callback; bounds/disabled days delegated to the single Calendar owner. The trigger grows/wraps without clipping at narrow/200% text. |
| Date of birth | 176px Field; month/year dropdown caption; selecting a date closes and returns focus. | Calendar caption selector API, caller-supplied year bounds and close-on-select. No default future-date policy is invented by the generic widget. |
| Input | 192px Input Group; editable full-month/two-digit-day text; icon-xs ghost action aligned inline-end. Arrow Down opens. Popover alignment end, align offset -8px, side offset 10px. Invalid text is retained while the last valid selection/month remains. | Final `DInputGroupInput`, addon and button owners. Strict locale codec, independent editor/button semantics, Form save/reset/validation and IME-safe controller updates. Calendar selection rewrites the text and closes. |
| Time | Horizontal Field Group up to 320px; 128px date and time fields; seconds-enabled 24-hour time input; date selection closes. | Date and `DTimeValue` remain separate civil values. The component never silently resolves them to an instant; application timezone adapters own DST gaps/ambiguities. Narrow/large-text layout stacks while retaining editor state. |
| Natural language | Input Group up to 320px; calendar icon action and 8px popup offset; input starts with `In 2 days`; valid parsing updates Calendar and the publish sentence, invalid parsing retains the last valid date. | Pluggable `DNaturalDateParser`; the bundled deterministic English adapter supports documented and common relative phrases against an explicit clock, plus strict explicit-date fallback. Other locales require an explicit adapter instead of pretending to translate English grammar. |
| RTL | 212px trigger and Calendar inherit Arabic/Hebrew direction and locale; inline-end chevron and logical start alignment mirror. | `Directionality`, host locale formatting and Calendar locale flow through the open overlay. Keyboard day navigation follows Calendar's accepted RTL contract. |

All wrappers read live `DTokens`, inherited font family, radius and text scaler at
build time. Popover owns collision, outside/Escape dismissal and focus
restoration. Calendar owns date grid focus, selection, locale and Kalender
integration. Date Picker owns only composition, editable synchronization and
date/time parsing.

## Value and lifecycle contract

- A selected `DateTime` is a local civil-day carrier with time fields cleared,
  not a UTC instant. Calendar day comparison does not use elapsed 24-hour
  durations across daylight-saving transitions.
- Picker values support controlled, initial/Form-owned and controller-owned
  modes without disposing borrowed focus/controller resources. Form reset must
  restore the mount baseline and synchronize visible text, Calendar month and
  validation state.
- Empty input may represent no selection. Non-empty invalid input stays visible,
  exposes invalid semantics, and does not move or clear the last valid Calendar
  selection. Bounds and disabled-date violations are invalid selections.
- `DTimeValue` validates `HH:mm[:ss]` without timezone ownership. Bookmark and
  Events adapters keep their existing timezone database and DST resolution.
- A selected date closes only where the source does: Date of Birth, Input, Time
  and Natural Language. Basic and Range remain open for continued selection.

## Application audit

Current code has four Material date-dialog call sites:

1. `plugins/local_dates/local_date_composer_sheet.dart`: editable ISO start/end
   date and time rows. Migrate to Date Picker input/time composition while
   preserving the existing `LocalDateComposerDraft`, timezone, recurrence,
   preview and final validation owners.
2. `plugins/discourse_events/event_composer.dart`: start/end/recurrence-until
   editors with all-day, timezone, end-after-start and custom-field validation.
   Migrate the calendar affordance/composition; keep event parsing, async
   controller currency and timezone resolution in the Events adapter.
3. `shell/bookmark_ui.dart`: custom account-timezone reminder with explicit DST
   nonexistent-time handling, persistence and session currency. Adopt the typed
   picker surface only if the final composition can preserve this complete
   adapter contract; never move timezone or storage policy into generic UI.
4. `shell/user_status_editor.dart`: custom future expiry behind an async/busy
   guard. Adopt the picker surface only with the same status lifetime and
   future-time validation; fixed relative expiry choices remain application
   actions, not Date Picker presets.

The Kalender-based Events directory/topic month views are full event calendars,
not date-entry controls, and remain with their existing application owners.
Chat/topic day separators and calendar-day helpers are display/domain logic, not
picker migrations.

## Review acceptance

- The accepted Kalender 0.29.1-backed Calendar merge
  `0bbb6c3673b395f75f4e03f80c15fcb0a0f16361` and accepted Input Group merge
  `d1de717b1e2d1eeaf06d86dafe1452662d05e368` are both ancestors of the final
  Date Picker candidate.
- Independent review covered value, Form, controller ownership, IME editing,
  keyboard and overlay lifecycle, range, disabled/bounds, leap-day handling,
  wall-clock separation and the migrated Local Date composer. The final
  randomized affected matrix contains 107 passing tests; root and
  `profiles/full` locked analysis are clean.
- Official Base UI browser comparison covered all eight documented examples in
  light and dark. Source-exact macOS inspection covered those examples plus the
  production Local Date composer in light, dark, custom palettes, narrow and
  200% text, LTR/RTL and reduced-motion configurations.
- No physical iOS/Linux device or spoken VoiceOver pass was performed. Widget
  tests cover the iOS minimum action target and the semantic/keyboard contracts;
  native acceptance establishes mapped geometry and behavior rather than pixel
  equality across browser and Flutter font rasterizers.
- The native geometry/interaction pass found the Time and Natural Language
  example-data mismatches. Their data-only correction is locked by a rendered
  widget regression and included in the final signed build; the geometry and
  picker implementation inspected natively did not change afterward.
