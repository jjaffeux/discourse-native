# Mockup control size parity

Measured on 2026-09-24 against `discourse-native-mockups` commit
`20dc23c3e7c97455225d0753b547a6ece0a173ae`, `src/App.tsx` and `src/index.css`.
The user approved extending the Native sizing presets and requested integration
into main. This supersedes earlier guidance that normalized filters and fields
to the general regular control size.

## Measurements and implementation

Dimensions below are CSS pixels / Flutter logical pixels at 100% text scaling.
Source measurements include borders. Chrome at 1280px and 390px widths confirmed
the natural filter and menu heights; preferences and directory fields were also
checked in the rendered source. Widths follow content, the chosen forum font,
icon aspect ratio and these insets rather than fixed text-button widths.

| Reference family | Native preset | Artwork height | Text / leading | Horizontal inset, including border |
| --- | --- | ---: | --- | ---: |
| FilterPill / list selectors | `filter` | 30.75 | 12.5 / 18.75 | 10 |
| Directory / group search | `field` | 35.5 | 13 / 19.5 | 11 |
| Preference select | `preference` | 40.25 | 13.5 / 20.25 | 12 |
| Topic and calendar chips | `chip` | 24 | 12.5 / 18.75 | 10 |
| Composer tools / header actions | `toolbar` | 34 | 13 / 19.5 | 10 |
| Segmented control inner action | `segment` | 28 | 13 / 19.5 | 10 |
| Desktop back / forward / refresh | `chrome` | 25 | 13 / 19.5 | 7 |
| Primary footer actions | `action` | 34 desktop, 44 touch | 13 / 19.5 | 14 |
| Popup menu row | shared menu geometry | 33.5 | 13 / 19.5 | 8 |
| Preference switch | `DSwitchSize.preference` | 22 (38 wide) | — | 2 (18px thumb) |

Previously, filters commonly requested `large` (40px desktop / 48px touch),
preferences used generic 34/44px selects, compact actions could become 40/44px
on mobile, and preference switches were 30×20px. Application presets now own
these dimensions across Button, Toggle, Select, Input and Combobox compositions.
The existing general small/regular/large scale remains available for surfaces
without a corresponding application mockup.

Reference controls use full-height SVG artwork and rounded natural SVG widths.
For example, the bookmark glyph is 9×12px and its chip 29×24px; filter chevrons
are 9×10px. Generic controls retain their existing optical inset and square icon
boxes. The shared menu implementation balances Flutter's paragraph-height
rounding across vertical padding so its artwork remains 33.5px.

Ramp sliders were also checked: the existing Native ramp already has the
reference 26px capsule and 18px ring, so no sizing change was needed.

## Application coverage

- Topic, message, bookmark, badge, group and user-directory filters; directory
  and group search fields; column chooser and searchable group selector.
- Topic taxonomy, bookmark, notification, assignment and tools triggers, plus
  matching header tag badge measurements.
- Account, appearance and chat preference selects and switches. The appearance
  font preview list remains a list; this change does not replace it with a select.
- Composer header, formatting toolbar, taxonomy row and submit controls;
  placement segments; calendar filters and Today/navigation chips.
- Desktop content navigation and New topic, message and Reply footer actions.

Touch targets remain at least 48×48px independently of smaller artwork. Joined
controls retain the kit's shared-edge touch treatment. Text scaling grows control
surfaces without reducing the user's text size; rows remain keyboard-operable.
Site category artwork and custom fonts can legitimately change content width.

## Verification

`test/mockup_control_sizes_test.dart` checks fractional surface dimensions,
bookmark width, chevron bounds, preference switch track/thumb, menu artwork versus
hit bounds, activation near touch-target edges, and narrow RTL layout through
300% text scaling. `control_size_scale_test.dart` exercises the new field/filter/
preference sizes across the shared control families at 100% and 200%.

The Button styleguide includes **Application control sizes**. The original
Control consistency example continues to show the three general sizes. Its
light/dark/forest/plum open-menu goldens were visually reviewed before updating
for the half-pixel row correction; rest, hover and mobile baselines are unchanged.
Golden renderer: Flutter widget tests, bundled JetBrains Mono, 720×480 desktop
and 390×900 mobile fixtures.

Native review used `tool/control_size_parity_review_main.dart`, built using the
repository's Flutter 3.47.4 SDK as an isolated macOS debug bundle. Its identifier
was `org.discourse.control-size-parity6095`; ad-hoc signing retained debug JIT and
local networking capabilities, with no push/team/application identity
entitlements. Strict signature verification and actual launch both succeeded.
The fixture displayed the production topic filter bar and shared controls in
light, dark, forest and plum palettes. Preference and filter choices, switch
activation, scrolling, 390px mobile-theme preview, 200% text and RTL were checked.
This was a native macOS review with simulated mobile theme metrics, not a
physical iOS/Android device run. Widget tests cover both mobile platforms.

Unrelated existing test failures were reproduced in an untouched worktree at
`9ab827420`: three content-navigation history cases, two static badge geometry
cases, four mobile-shell cases expecting a settings sheet, one stale Input Group height
assertion, 25 topic-reading cases, and four category/composer cases. The broader
regression batches reported 575 passes / 26 baseline failures and 123 passes /
four baseline failures; the failing test names matched the baseline exactly.
The final focused acceptance run passed all 161 tests (geometry, scaling,
goldens, header tags, selects, menus, New topic accessibility and settings).
Static analysis passed with no issues. These failures are recorded
separately from the sizing regression checks.
