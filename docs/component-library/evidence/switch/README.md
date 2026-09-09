# Switch browser-comparison preparation

The flutter-* PNGs are 34 font-loaded Flutter widget exports. The reference-*
PNGs are actual official-page Chrome screenshots; no native app was launched. They mount the production DSwitch/DSwitchTile and actual styleguide
examples. Neutral light/dark themes use the documented shadcn scaffold, including
distinct dark input and border alpha. Forest/Plum cards show 0px and 18px radii,
RTL and 200% text. The browser-only comparison is complete; details and limitations are in ../../switch.md.

The reproducible harness is `export-harness.dart.txt`; copy it temporarily to
`test/_switch_export_test.dart`, run `flutter test --no-pub` on that file from
this checkout, then remove the temporary test. It loads SFNS, SFArabic and
MaterialIcons from the local macOS/Flutter installations. Captures use 2 image
pixels per logical pixel. `flutter-metrics.json` records actual track dimensions
and decorations; reference-renderer.json preserves computed tokens and hashes of
all four observed immutable stylesheet URLs fetched through read-only HTTP; `export-trace.json` records component/example/harness/image hashes.

No cross-renderer parity or native interaction claim is made from these exports.

The exterior-ring correction reuses all primary reference captures. The 34 exports include 20 component states/compositions and 14 real local-data app fixtures. Focused cards retain both exterior strokes; pixel regressions verify unchanged translucent interiors. Desktop rows are intrinsic; only Poll/Group app adapters add observed necessary spacing. No new CUA or native launch was used.
