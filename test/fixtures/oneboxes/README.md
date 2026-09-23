# Core card fixtures

`core_cards.json` contains 22 Mustache templates rendered with deterministic
sample values from Discourse core `7b6f30d3341ccf6f531667334e13cb8b8fc0b01a`. Each uses core's `_layout.mustache`
and the named template. The matching sources are pinned in the core markup
contract (GitHub-owned templates remain in their plugin contract).

Fixtures were rendered with Chevron 0.14.0 as a development-only generator;
no runtime or project dependency was added. Values deliberately exercise nested
wrappers, descriptions, code, full-size images, metadata, and avatar links.
These are rendering fixtures, not assertions about live provider availability.
