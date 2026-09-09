# Scroll Area native queue — awaiting_slot

No native desktop slot has been granted. The Mac remains locked; no native app
was launched or inspected. Browser-only review was completed and released; see
scroll-area-render-review.md. This record establishes native build readiness only.

## Final build provenance

Source commit: `3e40cb9e1afc3441bc4f8e3d9fb2f6b2adf40f6e`. After temporary runner files were restored, the worktree was exactly clean.
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
equal. SHA256 for both: `1361361d520ac8cb0e836ed7581c2e4713c6777a666fc625977f382feda4acc0`.

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

## Pinned-main final native preparation

Merged main00f82d280a602c4ec86be3a24664f4052e6c1477. Preserved current Button,
Badge, Input, Radio Group, Diagnostics row sizing and Sidebar/styleguide semantics
owners and every other component progress row. Conflicts were imports, exports,
registrations and generated progress. The source commit above is the merge.
109 affected tests pass (seed1438380230), root/full-profile analysis clean.
No unchanged reference/export review repeated. Historical Diagnostics overflow
artifacts remain evidence of the prior version; main's row fix is now included.

Rebuilt the same uniquely named/id/scheme isolated bundle from the exact clean
merge source. Corrected effective built Info.plist identity before ad-hoc signing.
Deep strict signature verification passes. Read-back via
`codesign -d --entitlements :-` exactly equals the review entitlement file:

- com.apple.security.app-sandbox = true
- com.apple.security.cs.allow-jit = true
- com.apple.security.network.client = true
- com.apple.security.network.server = true

No APS, team identifier, application identifier, camera or microphone entitlement
is present. Nested code was deep ad-hoc signed; the top-level app was then signed
with the explicit minimal review entitlements. Evidence logs:
/tmp/scroll-area-sign-verify.log, /tmp/scroll-area-entitlements-readback.plist.
No CUA/browser/native use during this preparation. Ready and parked awaiting_slot.

## Final17-component baseline refresh

Merged pinnede612ad7b47413fa890b35ae3b55a6f6d37b08cf7 without conflicts.
Every non-Scroll-Area progress row matches pinned main; final Checkbox and
Topic Inbox reconciliation are retained.114 targeted integration tests pass
(seed4102292575): Scroll Area, its examples, styleguide page, Checkbox examples,
Topic Inbox and keyboard navigation. Root/full-profile analysis clean.
Unchanged source/browser/rendered comparisons were not repeated.

The source/hash at the top now identifies this final merge build. Runner identity
was restored and the entire worktree was clean before recording provenance.
Pins and lockfiles are unchanged. Unique effective app identifier corrected
before explicit ad-hoc signing; deep strict verification and exact sandbox/JIT/
network-only entitlement read-back pass again. No APS/team/application IDs.
No browser/CUA/native launch or alternate verification route was attempted.
Mac lock/browser-policy blockers remain; ready and parked awaiting_slot.
