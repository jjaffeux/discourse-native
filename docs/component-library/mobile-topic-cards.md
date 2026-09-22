# Mobile topic card layout

The topic list uses the full-width Native `DItem` row. This layout applies when
the row's available width is below 600 logical pixels. A resized window follows
the same rule as a phone; device type does not determine the layout.

## Order and spacing

1. Use 28 logical pixels of horizontal inset and 20 pixels above and below the
   content. Keep 12 pixels between the title, excerpt, and footer. A missing
   excerpt does not reserve space.
2. Place the title at the leading edge and the relative activity time at the
   trailing edge of the same top row, with at least 8 pixels between them.
   The time stays at the top when the title wraps. The title may use two lines
   before truncating; at large accessibility text sizes it may grow freely.
3. Show at most two lines of excerpt, then an ellipsis. At large accessibility
   text sizes, allow the full excerpt. Preserve the configured category, tag,
   last-poster, and plugin controls below it.
4. Put category, tags, and last-poster activity in a wrapping footer, in that
   order. Allow 12 pixels between entries and 8 pixels between footer lines.
   Each entry moves as a whole to the next line when it does not fit. A long
   category label keeps the Native breadcrumb's one-line truncation. Tags keep
   their Native badge sizing and may move individually.

## Narrow footer behavior

- Treat avatar, last-poster text, and reply count as one activity entry when
  their rendered text fits the card's content width. This lets them share a
  footer line with category and tags if there is room, or move together to the
  next line if there is not.
- If that activity entry cannot fit even on its own line, place the avatar and
  last-poster name above the reply count. Truncate the name as needed; keep the
  reply count visible. If there is no last poster or the preference hides it,
  show the reply count alone.
- The relative time remains in the title row at every width. Optional view
  counts and plugin metadata follow the footer and may wrap onto additional
  lines. Directional layout handles right-to-left text.

The desktop row keeps its current 16 by 12 pixel inset and inline metadata.
