# shadcn visual specification

The user's 2026-09-08 clarification is explicit: “I basically want a copy of
shadcn library for our app if it was not clear.” This project ports shadcn to
Flutter. Similar functionality with stock Flutter styling is insufficient.

## Reference and measurements

The frozen 64-entry catalogue and captured Markdown still define scope. Its
default reference family is Base UI. Use the official `base-nova` registry
styles shown by those component pages, rather than mixing styles from unrelated
presets. Typography uses the original captured Typography examples; its later
redirect to Typeset does not change this component's scope.

Inspect the reference example and its registry source. Record the source URL
and content hash. Translate CSS pixels into Flutter logical pixels at 100% text
scale and the reference's 16px root rem size. Match geometry, typography, gaps,
padding, borders, shadows, icon artwork, state treatment and motion. Preserve
the reference's compact visual bounds; enlarge an invisible interaction target
when native touch accessibility requires it.

For each component, document a short reference-to-Flutter mapping with actual
measurements. Do not infer visual parity from a component name, a theme role,
passing tests, or the absence of overflow. Reproduce the documented example
compositions before adding app-specific demonstrations. Components that are
still baseline must remain labeled as unfinished.

## Theme and native behavior

The app's configured palette, font family and radius supply the corresponding
shadcn theme variables. Preserve their semantic roles and the reference's
relative radius scale. Use existing unscaled `DiscourseTypography` size tokens
and explicit component leading/weights/tracking. A generic Material text role
must not silently change the specified metrics. The inherited native text
scaler remains the sole owner of accessibility/app zoom.

The official [theme radius scale](https://ui.shadcn.com/docs/theming#radius-scale)
is proportional to the host's base radius: `sm` ×0.6, `md` ×0.8, `lg` ×1,
`xl` ×1.4, `2xl` ×1.8, `3xl` ×2.2 and `4xl` ×2.6. Match the registry's
actual rounded class. A fixed Tailwind fallback or additive offset can agree
at the reference's 10px base and still be wrong for an app palette. The Badge
browser review confirmed these factors in the live stylesheet on 2026-09-09.

Map source `input` colors to `DTokens.colors.outlineVariant` and source `border`
to `DTokens.border`. They are separate semantic roles even when an app palette
currently gives them equal colors. CSS opacity modifiers multiply existing
alpha: use `color.withValues(alpha: color.a * factor)`. Replacing alpha can make
a translucent input background substantially brighter than the reference.

Use proven Flutter focus, semantics, keyboard, scrolling, selection and overlay
owners. Style their visuals to match shadcn. Platform-specific spinner artwork,
Material field outlines, or native switch shapes are not automatic substitutes
for a completed shadcn component. Native API composition can remain temporary
while the owning catalogue component is pending, with that limitation visible.

A deviation needs an observed conflict, a narrow adaptation and its reason.
For example, an unusable custom palette may need a contrast adjustment, and
larger accessibility text may need a compact widget to grow. First verify that
the correct color or geometry token was used. Do not use a broad “native
adaptation” statement to excuse arbitrary differences.

## Review gate

Compare actual Flutter renders with the reference at matching viewport width,
text scale and state. Inspect default light and dark appearances, then confirm
custom palette integration, large text and RTL. Include the real migrated app
surfaces in the already required native inspection. Record which visual
comparisons and interactions were performed, along with remaining limitations.
Fix unintended differences before `review_ready` and coordinator merge.

The coordinator reopened the visual review of already merged components after
the clarification. Direction has no intrinsic visual treatment. Separator's
1px square-ended token-colored rule matches the official registry source.
Typography's correction restores heading weights/tracking, paragraph and small
leading, code padding, list indent, table text and article spacing. Native
comparison also verified border-box insets and accessible heading wrapping. In-flight
Kbd, Spinner, Skeleton and Label tasks received this same standard before merge.

Supporting sources:

- [Official Separator source](https://ui.shadcn.com/r/styles/base-nova/separator.json)
- [Official Kbd source](https://ui.shadcn.com/r/styles/base-nova/kbd.json)
- [Official Skeleton source](https://ui.shadcn.com/r/styles/base-nova/skeleton.json)
- [Official Spinner source](https://ui.shadcn.com/r/styles/base-nova/spinner.json)
- [Official Label source](https://ui.shadcn.com/r/styles/base-nova/label.json)
- Typography: the original 2026-09-08 Markdown with SHA256
  `3ff202e83d6c90b2521ec471af07cab3c59314028c51ef8d040b3218ec9a9541`.
