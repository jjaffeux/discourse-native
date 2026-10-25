# Category grid fixture

`meta.json` contains the 12 root categories and 33 featured topic summaries from
<https://meta.discourse.org/categories.json?include_subcategories=true&include_topics=true>,
fetched 2026-09-18 UTC. Only fields consumed by the category-card presentation
are retained; no credentials or author records are included. Tests do not access
the network.
