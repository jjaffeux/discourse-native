# Profile menu mockup parity

Reference: `discourse-native-mockups/src/App.tsx`, `AvatarMenu` and
`ToggleMenuRow`, and `src/app.css` menu and material rules.

The header avatar opens the existing Native dropdown on desktop and the Native
adaptive bottom sheet on iOS and Android. The desktop menu aligns with the
avatar's trailing edge, sits 8px below it, and uses the reference 216px width
and 10px popup corners. Large text gains a local
scroll viewport; placement respects the physical phone safe area even when
the header's SafeArea has consumed local padding. The mobile sheet has a grab
handle, floats above the home indicator, and supports downward swipe dismissal.
Tall content can expand and scroll using the existing adaptive sheet behavior.

The account header uses a 32px avatar, a 13.5px semibold display name and a
12px muted handle. The three separators follow the account, presence and
navigation groups. Rows retain 33.5px visible heights at normal text size,
7px corners, 13px glyphs in 16px slots and 9px label gaps. Draft counts,
11px toggle checks, solid status/preferences icons and destructive text
follow the reference. Online retains its setting label when switched off.

The existing dropdown supports visible header padding, larger leading content,
indicator sizes, separator spacing and the shared mockup palette. Pointer
opening retains keyboard focus without painting a spurious active header;
keyboard navigation still highlights and reveals its focused action. Presence
and resume toggles stay open; status, pause, account card, navigation, About and
Disconnect retain their real app actions and account ownership.

The popup uses the 3% panel fill, 22% border, 12% rules, 50% muted text and
50% success/danger ink mixes. Liquid Glass menus use the reference 68% fill,
26px blur and existing saturation, refraction and rim rendering.

Validation: `test/user_profile_menu_mockup_parity_test.dart` covers desktop,
iOS and Android, light/dark, Standard/Liquid Glass, LTR/RTL, 100%/200% text,
safe areas, toggles, dialog handoffs, backdrop and swipe dismissal, system back,
account retirement, keyboard, hover and reduced motion. Set
`NATIVE_PROFILE_CAPTURE_DIR` to save rendered preview PNGs using
the bundled Lato font and a deterministic avatar fallback. These are widget
renders, not physical-device or Impeller captures. Existing dropdown,
material, account, layout and styleguide tests are also run by file path.
