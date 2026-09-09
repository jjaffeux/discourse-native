# Button Group browser reference inspection

Inspection date: 2026-09-09

Reference: `https://ui.shadcn.com/docs/components/base/button-group`

The serialized desktop lease was held by reviewer task
`01a085f4-2a6b-7c82-9dc3-c9b14d76b355` for the complete inspection.

Verified in the official Base UI renderer:

- light and dark palettes;
- compact equal-height joined buttons with only outside radii;
- separate Archive, Report, Snooze and More Options semantics;
- Dropdown Menu opening, independent menu surface geometry, destructive item,
  Escape dismissal and trigger focus restoration;
- the currency Select as a direct joined control, its US Dollar/Euro/British
  Pound popup outside group geometry, and Escape dismissal;
- the documented Composition, Accessibility, ButtonGroup versus ToggleGroup,
  Orientation, Size, Nested, Separator, Split, Input, Input Group, Dropdown
  Menu, Select, Popover and RTL sections.

The visual comparison is qualitative because browser Geist rasterization and
native host-font rasterization differ. Frozen Markdown and registry byte hashes
are recorded in `docs/component-library/button-group-reference.md`.
