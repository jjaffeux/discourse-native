# Compact control sizing — 2026-09-13

Normal buttons now have a 28px painted surface and 12px labels at 100% zoom.
The user requested a smaller overall scale and removal of extra-small buttons.
`DControlStyle` owns this intentional adaptation from the frozen shadcn sizing.

| Size | Height | Font | Line height | Icon box | Icon/label gap |
| --- | --- | --- | --- | --- | --- |
| Small | 24px | 12px | 16px | 12px | 4px |
| Regular (default) | 28px | 12px | 16px | 14px | 4px |
| Large | 32px | 14px | 20px | 16px | 6px |

Small retains a readable 12px font and uses tighter padding. Regular and large
retain their themed radius; small uses the existing proportional radius with a
10px cap. Loading spinners retain their 16px size. Labels and icon surfaces grow
with text scaling, and iOS/Android buttons retain invisible 48px hit targets.

The shared enum now contains only `small`, `regular`, and `large`. All former
extra-small controls in the app, kit, examples, tests, and review fixtures use
small. Selects, toggles, dropdown triggers, input-group buttons, comboboxes,
sidebar actions, menubars, and navigation controls inherit the same scale.
Tabs retain their padded-list composition. Footer and hover-action dimensions
continue to derive from the shared control height.

Standard application button icons inherit the kit's icon size instead of fixed
local dimensions. Rich artwork such as avatars, badges, and composite labels
retains its own geometry. Attachment card sizes are a separate content scale;
their extra-small card preset remains, while attachment action buttons use small.

The Button, Select, Toggle, and Alert examples describe the new sizes. The frozen
reference files and historical review records retain their original measurements.

## Verification

- `flutter analyze --no-pub`: no issues.
- The focused control/styleguide run passed 352 tests, including Button,
  Button Group, Toggle, Select, Combobox, Tabs, Input Group, Menubar, Navigation
  Menu, Sidebar, Attachment, control adoption, palettes, keyboard interaction,
  semantics, text scaling, RTL, and all 12 control-family golden images.
- Reviewed all 12 new golden renders in light, dark, forest and plum before
  accepting the updated baselines. These widget-test images use bundled
  JetBrains Mono and Material Icons at 720 × 480 logical pixels.
- The focused app run passed 244 checks for topic headers/actions, search clearing, chat,
  navigation, message actions, and profile controls. Its 21 remaining failures
  also fail at starting main `cf4d0983` in an isolated baseline worktree. They
  concern obsolete topic-header finders, loaded-draft focus, and direct-message
  reply lookup; none is new to this sizing change. Two stale New Topic size
  assertions were corrected to the existing regular preset.
- Built `tool/contextual_controls_review_main.dart` with Flutter 3.47.2 and
  inspected its isolated macOS app through CUA. Reviewed the actual topic
  filters, search field, category/tag buttons and footer, plus the styleguide's
  Control consistency example. Inspected light, dark and plum palettes,
  740px and 320px content widths, 100% and 200% text, and RTL. Opened the
  category picker, dismissed it with Escape, and changed the comparison select
  with Down/Enter, retaining its value across palette changes. The legacy
  category fixture opens with no matching categories, so category saving was
  not claimed as verified. The narrow footer remains usable when scrolled
  into view; no overflow indicators appeared.
- The inspected native kernel SHA-256 is
  `2ec3f8c511f1b4623146ca1c911d5a6187dcb5f62a20fe211205bd2c50aecbe6`.
  Debug signing and entitlements were verified for the isolated review bundle.
  iOS/Android checks were widget platform overrides, not device runs.
