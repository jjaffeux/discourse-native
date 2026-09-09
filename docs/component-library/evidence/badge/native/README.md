# Actual Badge native and browser review

PNG files without a `browser-` or `official-` prefix are screenshots from the
uniquely identified running Badge Review BEBB9 macOS app. `profile-200-plum.png`
is the real profile popup with root text scale 200%, backed by a test checking
both Badge text contexts. `migrations-group-overflow-before.png` is the failure;
`migrations-membership-wrapped.png` and `migrations-owner-wrapped.png` show the
final corrected footer. The final kernel in build-identity.json was launched
and its Groups correction re-inspected; other captures remain valid across
that bounded migration-only correction.

`official-page-variants.png` is the live official Badge page. `browser-ring-*`
are Chrome captures of reference-ring-fixture.html: frozen registry classes
with tailwind-merge-equivalent removal of border-transparent for outline,
reference neutral variables and the complete unmodified compiled stylesheet.
The SHA256 of reference-compiled.css is
`19dd8fe80f1fb07e156ed3ceaaaacb7a600a3444e97c3baf6483c4363a15668d`.
The local fixture uses Arial, so it establishes ring/state behavior rather than
Geist glyph matching. No ring selectors or shadow implementation were overridden.
The public page does not expose invalid Badge controls; these local states are
not misrepresented as public-page screenshots. browser-ring-metrics.json records
settled, keyboard-visible state styles and idle invalid shadow:none.

Serve this directory with an ordinary local HTTP server to reproduce the HTML.
The review server was stopped, task tab closed and isolated app quit before the
native/browser slot was explicitly released. No viewport or reference theme
changes were made in this slot. See ../../../badge-native.md for the narrative.
