# Switch native acceptance

Inspected actual isolated app source `3243a88cf2a9a1cfee96af7877386379089ab6c5`,
preparation HEAD `b851adbb`, kernel SHA256
`9af57c435d269a4f97355921a29131f3f232007988984017e3db2f2413655917`.
Bundle `/private/tmp/discourse-switch-review-3243a88c/Discourse Switch Review 3243a88c.app`.
The fresh CUA access succeeded. No browser navigation or real account app used.

All nine registered examples were opened. Verified associated Airplane label
activation; Small pointer-on/Space-off and Default Tab/Space-on; disabled off/on
and read-only resisted pointer/Space edits. Native default/small and RTL thumb
movement agrees visually with previously measured geometry; exact 14/10px
logical distances remain established by source/browser/widget measurements,
not a new calibrated native pixel measurement.

Form unchecked Submit shows error/ring; accept then Submit shows Saved:true;
Reset returns off/Not saved. Controlled updates external button changes off to
on. Rejected/deferred controlled Form resets remain covered by existing widget
tests, not separately exposed by this native fixture.

Inspected description, light and dark fills, dark invalid ring without interior
tint, dark card dual exterior focus rings, and Plum at360px/200%/RTL. Narrow
cards wrap and their preview scroll reveals the second card completely.
Arabic RTL off/on screenshots show reversed thumb direction. Live theme changes
preserve the component rendering. Existing host-primary focus-ring mapping and
native/browser font-shaping differences remain documented limitations.

Actual production fixtures: Settings label activation updates GIF switch;
Preferences changes on to off; Chat mute changes off to on and dependent controls;
Local Date end switch reveals end date/time; Group membership changes off to on.
Voice requested capture confirmation, which was dismissed; capture stayed off.
No real recording or external persistence occurred.

Poll automatic-close switch reveals its date field. At first the newly grown
content placed actions partly below viewport. Normal content scroll revealed
Cancel/Apply fully. Entered Tea/Coffee and2027-09-09T18:00:00Z; Apply closed the
dialog and showed Local poll:apply. No layout correction was needed.

AX snapshots occasionally lagged screenshot text and index clicks sometimes
selected an unexpected target; fresh screenshots and pointer coordinates were
used to verify actions. Command-Q did not exit with this keyboard mapping;
the native app menu Quit action did. Follow-up running-app inventory excluded
the unique review identifier (quit-verification.json). Slot explicitly RELEASED
immediately afterward. No other app or browser tab was closed.

No functional defect found. Post-inspection example status/notes promotion is
behavior-neutral; the inspected bundle intentionally retains its earlier
baseline badge. No functional source changed and no rebuild/reinspection is
needed for that status-only metadata change. iOS/Linux device and spoken
VoiceOver checks remain unperformed. Native acceptance passes for this scope.
