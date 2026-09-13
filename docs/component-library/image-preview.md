# Image preview

`DImagePreview` is a user-approved Native application component, exported by
`discourse_ui.dart` and registered in the application styleguide catalogue.
It does not change the frozen upstream catalogue.

## Behavior and adoption

The reference is the checked-out Discourse implementation at
`/Users/joffreyjaffeux/Code/pr-discourse/app/assets/stylesheets/common/base/lightbox.scss`.
The preview reproduces its 90% metadata overlay, 500ms reveal, 200ms dismissal,
600ms shadow transition, and image/expand affordances. Colors come from the
current theme. Shadows are clipped outside the image, preserving transparent
pixels and letterboxing.

Post lightboxes, including image grids and carousels, and chat-upload images
share this component. Existing loading, sizing, galleries, URLs, and download
behavior stay in their application adapters. Non-lightbox images are unchanged.
GIF controls appear at the top of these previews so they remain clear of the
metadata bar; other SiteImage consumers keep their existing control placement.

Keyboard focus reveals metadata and a focus outline; Enter and Space activate
the existing gallery callback. The focus decoration stays mounted to preserve
focus and child state. Touch platforms have a compact expand indicator and
one-tap opening. Reduced motion removes transitions. Narrow previews truncate
the filename and omit details before falling back to just an expand icon.
The overlay is excluded from semantics and pointer hit testing; the named image
action and GIF playback action remain independent.

## Verification

- Flutter 3.47.2, Dart 3.13.2; touched Dart files formatted.
- Root and full-profile static analysis passed.
- Focused widget checks cover the component, post lightboxes, image grids,
  chat uploads and accessibility, SiteImage, styleguide, and control adoption.
  They include rendered pixels proving shadows leave transparent image
  interiors clear, hover transitions, stable image bounds, keyboard activation,
  touch, independent child actions, narrow RTL layouts, and large text.
- A native macOS debug build of `tool/image_preview_review_main.dart` was
  inspected in an isolated app bundle. It mounts real CookedHtml and ChatUploads
  with a loopback image server and the actual component styleguide. No account
  data or preferences are involved.
- Native inspection covered light/dark palettes, a custom forest palette,
  narrow width, RTL, large text, pointer opening, Enter opening, Escape closing,
  metadata appearance, independent GIF controls, and the styleguide preview
  dialog. The GIF fixture exercises control placement/state using static image
  bytes; animated decoding/playback is covered by the existing SiteImage tests.
- The native review caught and corrected shadows painting inside transparent
  images. The final semantics-only addition identifies disabled previews.
- Reference comparison used local web source. No iOS or Linux device testing,
  VoiceOver session, or live web-site visual comparison is claimed.

Implementation branch: `codex/image-preview-hover`.
