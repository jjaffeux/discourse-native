# Palette parity

Reference: `discourse-native-mockups` `a4c4875` (`src/contrast.ts`,
`src/derive.ts`, the `--mix-*` levels in `src/app.css` and `PUBLISHED_SCHEMES`
in `src/App.tsx`).
Scope: the presets, the user's own themes, and the colours resolved from
them. A forum's own published palette is still shown exactly as published.

`lib/src/foundation/palette_contrast.dart` is the one copy of the reference's
contrast arithmetic. `ForumTheme.resolve` keeps each derived colour's former
share of the palette wherever that already passes WCAG AA, and moves it only
where it does not.

- Body text (`primaryVeryHigh`) aims for 7:1 where the palette reaches it.
  Metadata, medium text and code comments need 4.5:1 on every surface text is
  set on (ground, panel, header, hover, floating, raised, selected, code).
- Hover, floating, raised, selected, inline code and the accent, highlight,
  danger and mention fills thin out until the palette's text reads on them.
- The accent, and the code colours drawn from success and highlight, move
  toward the text only as far as it takes to read. Fills keep the raw accent.
- Tint leans the ground toward the accent only while the text still reads on
  it, and the text only while it still reads on the ground.

Every preset has a light half and a dark one. Discourse's own Light and Dark
are one preset, `discourse`, which takes the legacy `dark` id, so Neutral no
longer borrows Discourse Dark. Dracula carries Alucard. A palette published
for one mode gets its other half from `ForumTheme.forBrightness`. Ground and
text keep the palette's hue at the far ends of OKLCH lightness, and each other
colour keeps its hue and chroma, moved in lightness until it reads on the new
ground. This replaces swapping text and background.

The theme editor moves a picked text or background toward black or white, as
far as it takes to read against the other. Quiet chips, reaction chips and the
Start launcher step toward the palette's text (5% fill, 8% hover, the raised
surface when selected) rather than a fixed white or black alpha.

Not ported: borders keep their fixed shares, as the reference keeps them. The
reference's fill ink (`--mix-accent-ink`) has no Native counterpart because
`AppTheme.fromPalette` already picks a readable foreground for each container.

`test/palette_contrast_test.dart` checks every preset in both modes at three
tints, plus a generated corpus of palettes.
