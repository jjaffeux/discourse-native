# Category grid fixture

`meta.json` contains the 12 root categories and 33 featured topic summaries from
<https://meta.discourse.org/categories.json?include_subcategories=true&include_topics=true>,
fetched 2026-09-18 UTC. Only fields consumed by the category-card presentation
are retained; no credentials or author records are included. Tests do not access
the network. The 60-category workload repeats these records five times with
unique category IDs; it is a synthetic expansion, not Meta's actual root count.

`geometry.json` records category left position, width and height on the original
intrinsic-height grid at 390, 700 and 1100 logical pixels. Flutter 3.47.4 widget
test renderer, default test fonts/platform, 1200 × 900 viewport, DPR 1. Production
`CategoriesPage`, `AppTheme.light`, natural title wrapping, no fixed card height.
It includes 118-pixel empty cards and taller cards with real featured titles.
