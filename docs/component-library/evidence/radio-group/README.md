# Radio Group browser comparison evidence

Captured 2026-09-09. The original22 PNGs are font-loaded Flutter widget-test renders. A later native review adds18 native-*.png application screenshots; see native-review.md and native-sha256.json. The harness is preserved as export-harness.dart.txt; copy into test/ and adjust its output/font paths before running flutter test. SF system fonts and SF Arabic are loaded explicitly; browser reference uses Geist and Noto Arabic. Neutral tokens follow the existing Button export approach; forest/plum are live app palettes. PNG pixel ratio is 2.

Official browser reference: https://ui.shadcn.com/docs/components/base/radio-group. Light/dark, focused cards, invalid, disabled and RTL were visually inspected in the serialized browser slot, with DOM geometry and keyboard checks. Reference screenshots were viewed in-tool and are not included as local artifacts. Browser tab closed and original dark theme restored before releasing the slot.

The 22 exports cover seven reference examples in light/dark, two focused cards, two custom palette RTL 200% cards, and four real production fixture views (flags/Poll light and dark 200%, change owner and move posts). Native macOS review subsequently completed; VoiceOver remains unverified. The fixture uses only local fakes.

Known adaptations: touch platforms retain 48px targets; desktop rows use intrinsic content geometry; SF shaping differs from Geist; DTokens.focusRing maps to host primary rather than the reference gray ring; disabled rows uniformly dim their content whereas the live reference dims its label but its span radio stays opacity 1. No pixel-parity claim.

Measured Flutter desktop groups: Default 112.0094×64 (browser109.8594×64), Description272.2539×142 (browser264.0859×142.75), Fieldset320×73 (browser320×73.75), cards384×65. All row gaps are8. The 0.75px group difference comes from the three fractional 19.25px label lines rendering at19px with the loaded host font. Width differences follow SF versus Geist shaping. measurements.json records the actual export bounds.
