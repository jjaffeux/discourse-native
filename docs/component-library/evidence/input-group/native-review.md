# Input Group browser and native review

Reviewed source commit: `40798af67b0e2eed1cbd97fcc7d29c854065983d`  
Reviewed source tree: `d73ac320a706c7ed22ec5ea7299d1be4d6e6499c`  
Reviewed bundle: `/private/tmp/InputGroupReview-40798af6.app`  
Bundle identifier: `org.discourse.native.inputgroup.40798af6`

The copied review bundle's kernel SHA256 matched the source bundle at
`32fbfcb5bf9a4ace77e72775b43497cf8d73a7728f0b1deba988ab2f5de02d3e`.
The explicit ad-hoc entitlements and signature checks are recorded in
`native-preparation.json`.

## Official browser reference

The rendered Base UI reference was inspected in both light and dark themes at
`https://ui.shadcn.com/docs/components/base/input-group`. The live page exposed
the frozen align, icon, text, button, Kbd, dropdown, spinner, textarea, custom
input and RTL examples, along with the documented focus-navigation rule that
the addon follows the editable control in DOM order while logical alignment
controls its visual edge.

The Flutter surface matches the reference's compact rounded exterior, muted
inline addons, one group-level focus/invalid ring, auto-height block layouts,
and separate input/button interaction model. Platform-native typography and
the mobile 48px target wrapper intentionally differ from the web reference's
32px pointer target.

## Native application inspection

The exact isolated bundle was launched through macOS accessibility automation.
No account was used and the fake forum URL made no successful network request.

- Default search: the text field accepted `needle`; its shared blue focus ring
  wrapped the complete surface while the search/filter visuals stayed inside.
- Alignments: inline-start, inline-end, block-start and block-end layouts kept a
  single exterior shape and independent editable controls.
- Button actions: accessibility exposed the editors and Search, Copy URL,
  Show/Finish loading and Clear actions as separate targets. Triggering loading
  changed only the action's value/state.
- Form validation: saving an empty editor produced the destructive exterior
  ring without moving supporting content into the joined surface.
- RTL: Arabic inline/block examples mirrored their logical addons and shared
  seams while preserving separate editor and publish-button targets.
- Narrow/large text: the RTL example was inspected at the built-in 360px
  viewport and 200% text scale together. Content stayed inside the preview;
  text truncated or wrapped without horizontal overflow or broken exterior
  geometry.
- Production adoption: Chat global search exposed the editor, sort control and
  conditional Clear search action independently. Typing `needle` and clearing
  it updated the fake results state without collapsing those semantics.

Keyboard focus, focus-node replacement/disposal, outer mobile touch bands and
Form save/reset ownership are additionally covered by widget tests. A physical
iOS/Android device was not available; the exact native pass was performed on
macOS, with mobile sizing exercised by the responsive widget tests and the
360px/200% styleguide scenario.
