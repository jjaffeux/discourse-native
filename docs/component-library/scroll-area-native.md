# Scroll Area native queue — awaiting_slot

No native desktop slot has been granted. The Mac remains locked; no native app
was launched or inspected. Browser-only review was completed and released; see
scroll-area-render-review.md. This record establishes native build readiness only.

## Final build provenance

Source commit: `1514d822c89c30e32cc5d46419682c6541d7e3ad`. After temporary runner files were restored, the worktree was exactly clean.
Production Dart, fixture, assets, macOS runner and dependency inputs equal that
commit. This later provenance update changes only documentation.

Command: `flutter build macos --debug --no-pub -t lib/scroll_area_review_main.dart`.
Build succeeded; log `/tmp/scroll-area-macos-build.log`.

Bundle: `/Users/joffreyjaffeux/.codex/worktrees/d422/discourse-native/build/macos/Build/Products/Debug/Scroll Area Review d422.app`.
Name: `Scroll Area Review d422`.
Final identifier: `org.discourse.scrollareareviewd422`.
URL scheme: `discourse-scroll-area-review-d422`.

Runner AppInfo.xcconfig and Info.plist identity were temporarily customized and
restored byte-for-byte. Xcode Debug settings overrode the xcconfig identifier
with org.discourse.native.dev; the final built Info.plist identifier was corrected
to the unique review ID before signing. The main checkout build was untouched.

Build App.framework and copied bundle App.framework kernel_blob.bin bytes are
equal. SHA256 for both: `42b26b4ed21e2f0a366893cbc3822dc84a8a1e590396b476a20c9a7c554e8192`.

`codesign --force --deep --sign - --timestamp=none` completed locally, followed by
`codesign --verify --deep --strict --verbose=2`: valid on disk and satisfies its
Designated Requirement. Log: `/tmp/scroll-area-sign-verify.log`.
This is local ad-hoc review signing, not release or App Store signing.

## Inspection plan after explicit coordinator desktop slot

Open the official base-nova Scroll Area reference and compare Tags at 192×288,
RTL tags and horizontal photographs against matching native examples. Inspect
light/dark, Forest palette, 200% text and reduced motion; use 360/768/1024 preview
widths and confirm retained example text/offset through controls.

The offline fixture mounts the actual styleguide, DSidebarContent, CodeBlock,
AlertTables, EventCalendar, AssignedGroupPresentationView, DiagnosticsPanel and
VoiceDiagnosticsView. Tabs select owners. Theme toggles the local host palette;
applicable panes offer empty/ready content. No account services are constructed;
diagnostics use MemoryDiagnosticsPersistence. Calendar is an offline empty month
whose bounded grid can still overflow when the window height shrinks. Production
permission/async behavior is covered by downstream tests, not claimed from this
fixture's local callbacks.

Check wheel and trackpad on both axes, mouse thumb and track input, touch where
available, keyboard entry/ring/arrows/Page/Home/End, hover/fading mode, corner
appearance/removal on resize, nested input focus, list removal and fixture
navigation. Validate the migrated real owners as well as the generic examples.
Record screenshots, actual native outcomes and fixes before review_ready.

No pixel parity, VoiceOver, iOS/Linux device behavior, native trackpad behavior
or production-screen visual acceptance has yet been established.

## Keyboard follow-up

Root Tab entry now depends on enabled-axis overflow, matching the captured Base
UI tabindex condition. Content and viewport-size changes preserve descendant
editing/focus and do not forcibly blur a previously focused root. Space pages
down, Shift+Space up; unrelated modified keys bubble to ancestor handlers.
35 component/Sidebar/styleguide tests pass, including actual traversal and child
key handling. Root/full-profile analysis are clean. The signed fixture above
was rebuilt after these executable changes; native review remains awaiting_slot.

## Browser/render follow-up build

The source above includes exterior-only ring painting, multiplied ring alpha,
reference-sized photos and proportional md radii, preserving corrected keyboard
behavior.106 focused regressions passed (seed1519015133); root/full-profile
analysis are clean. The renderer export runner also completes and records the
known pre-existing Diagnostics large-text row errors; coordinator owns their
separate fix. The native bundle was rebuilt, its effective unique identifier
verified after correction, copied kernel compared, and deep strict signature
verification repeated successfully. Browser slot is RELEASED; native awaiting_slot.
