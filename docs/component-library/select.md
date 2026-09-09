# Select reference mapping

Task: `01a085bb-1d11-7f52-a7bd-667348469087`  
Branch: `codex/ui-select`

## Source evidence

- Frozen shadcn/Base UI Select Markdown SHA256: `fc566bd829748e1caec337728e3198a951599be1c4c96f132e20d62266e2d0a9`
- Base Nova registry SHA256: `425e9b0a28b72617f18fabd75384050113295b88e7ba01c35bede2c72bd5d476`
- Prepared against tested Popover pin: `d99562f0f6973c9dc3f566eea02d9b00c6de4f7b`

The Popover pin is not accepted main. The Select reviewer must integrate accepted Popover main before final merge.

## Geometry and visual mapping

- Trigger height is 32px by default and 28px for small controls, with 14px text and 20px line height.
- Trigger padding follows the reference directional shape: compact leading content, trailing 16px chevron, input border and proportional token radii.
- Focus and invalid rings render outside the trigger so grouped or adjacent composition can preserve joined exterior geometry.
- Disabled state uses reduced opacity without replacing the trigger or item semantics.
- Popup minimum width is at least 144px. Popup uses Popover offset/collision behavior, an 8px-style rounded surface, border/ring/shadow, and foreground/background tokens.
- Popup rows are 28px pointer rows with check indicator space, item text, hover/highlight state and disabled-option skipping.

## Ownership mapping

- `DSelect<T>` is the public rich Select rendering owner and a `FormField<T>`.
- `DSelect.controlled` is the explicit controlled-null API.
- `DMultiSelect<T>` maps the Base UI multiple-selection mode.
- `DSelectItem`, `DSelectOption`, `DSelectGroup` and `DSelectSeparator` expose item/group/separator composition.
- `DSelectField<T>` remains only a source-compatible adapter for existing `DropdownMenuItem` and `InputDecoration` callers.
- `DPopover` remains the overlay lifecycle, dismissal and collision owner. Select uses its public placement hook for selected-row alignment and does not duplicate Popover.
- Borrowed `FocusNode`, `DPopoverController` and `ScrollController` are not disposed by Select.

## Behavior mapping

- Pointer, touch and keyboard can open the popup.
- Keyboard supports arrow navigation, Home/End, Enter/Space selection, Escape dismissal, Tab containment while open and typeahead.
- Selected-row alignment is used for keyboard/mouse opening when there is enough viewport room. Touch or insufficient-space openings fall back to edge-safe Popover placement.
- Focus restores to the trigger when the popup closes from option focus.
- RTL, text scaling, narrow layout and live theme changes are covered by focused widget tests.

## Button Group dependency handoff

The Button Group frozen rich Select fixture must be replaced with public `DSelect`, not `DNativeSelect`, and must not duplicate Popover. The Select handoff example preserves adjacent button actions, grouped exterior geometry, Select trigger/editing semantics, popup rendering outside the group, RTL and scaled layout behavior.
