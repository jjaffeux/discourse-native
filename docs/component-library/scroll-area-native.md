# Scroll Area native queue — awaiting_slot

No desktop slot has been granted. The Mac remains locked; no browser/native app
was launched or inspected. This record establishes build readiness only.

## Final build provenance

Source commit: `f3ad79ca78f2552771803e8722fd72e5774644ec`. The worktree was exactly clean after the
temporary runner files were restored. Subsequent commits update documentation
only; production Dart, fixture, assets and dependency inputs equal that commit.

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
equal. SHA256 for both: `30b1bbf47c38d205a897ae8c36d25ba2a0203a39bd57d451f1a0157f9b00c00f`.

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
