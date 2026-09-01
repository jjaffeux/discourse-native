# Hybrid composer architecture

The composer stores and submits exact Markdown. Recognized authoring syntax may
render as an inline or block component, but no rich document serializer is
allowed to regenerate Markdown that it did not create.

The hybrid editor therefore has two representations with different jobs:

- the **source document** is the canonical Markdown, revision, semantic
  selection, and undo history;
- the **surface document** contains editable text leaves and atomic component
  nodes with their real rendered geometry.

The surface is a projection of one immutable source revision. It is never a
second source of truth.

## Public component primitive

Plugins declare what they recognize and how it looks through
`ComposerComponent<T>`:

```dart
ComposerComponent<LocalDateBlock>.inline(
  kind: localDateComposerSyntaxKind,
  find: findLocalDates,
  builder: buildLocalDate,
  semanticLabel: localDateLabel,
  onEdit: editLocalDate,
  onRemove: removeLocalDate,
)
```

The `.inline` and `.block` constructors are the only layout choices. A finder
returns typed values and source ranges, not replacement Markdown. The private
resolver validates each range and captures its exact source before a component
can render or perform an action.

Components own presentation, labels, and feature-specific edit/remove actions.
They do not own arrow-key behavior, deletion rules, selection snapping, IME
policy, clipboard behavior, or undo. Those are editor invariants.

Presentation callbacks do not receive the captured source directly. Because a
plugin still defines its own typed value and widget, every component also runs
the shared conformance test that rejects visual or semantic output containing
its complete authoring source.

## Projection rules

Every parser runs against the same immutable `(source, revision)` input. The
resolver materializes parser output immediately and produces a lossless
partition of text and component segments.

Candidates are resolved deterministically:

1. Invalid or empty ranges are rejected.
2. Exact-range conflicts choose higher precedence, then the lexical namespaced
   kind identifier.
3. Crossing partial overlaps reject and report every participant.
4. Strict containment keeps the outer atom and reports the contained candidate.
5. Concatenating every resolved segment must reproduce the canonical source
   byte-for-byte at the Dart string boundary.

Malformed or unregistered syntax remains ordinary visible Markdown. Valid,
recognized component source is never placed in an editable text leaf.

## Semantic selection

Source offsets remain useful for persistence and verified edits, but they are
not sufficient to describe selection around an atom. The session uses three
selection variants:

- `ComposerCaretSelection(offset)`
- `ComposerRangeSelection(anchor, focus)`
- `ComposerComponentSelection(token)`

A collapsed caret is never legal strictly inside an accepted component. A
dragged range that intersects a component expands to include the component's
entire source range while preserving selection direction.

Horizontal traversal is symmetric:

```text
caret before  <->  component selected  <->  caret after
```

Backspace after an atom and Delete before it select the atom first. Either key
removes the whole atom when it is selected. Escape changes a selected atom to
the caret-after state before the composer-level close shortcut can run.

Pointer surfaces send a component token for an atom hit. They must not invent
an interior source offset: a one-code-unit component has no such integer
offset, and source boundaries are valid caret locations.

## Verified transactions and history

All source mutations are transactions containing:

- the expected base revision;
- one or more non-overlapping source ranges;
- the exact source expected at each range;
- replacements and the semantic selection after the edit.

The session validates the complete transaction before applying any edit.
Stale revisions, source drift, invalid ranges, and overlapping edits reject the
whole transaction. Successful commits create one new revision and one undo
entry. Undo and redo restore both exact source and semantic selection while
still minting fresh revisions, so a transaction captured before history moved
cannot become current again. Component actions resolve their token against the
current projection and receive a one-mutation editor lease bound to that
revision. A retained or asynchronous modal therefore cannot commit after a
source edit or an edit-then-undo cycle, even when the restored Markdown is
identical.

The surface's native history is disabled. Source-owned transactions are the
only undo boundary.

## Surface adapter

The composer surface adapter boundary is private to the shell. No editor
package type, node, selection, or serializer may cross it.

The projection plan separates text, inline atoms, and block atoms. The current
dependency-free adapter lowers them into one projected `TextField`: each atom
occupies one object-replacement position, while a block is a full-width widget
with its real measured height. It never reserves height with transparent copies
of Markdown source.

Composition-free text proposals map to one verified source transaction and the
accepted snapshot is reprojected before the proposal can replace the surface
controller value. Selection-only changes map to semantic selection without
mutating source. Hardware and soft-keyboard deletion share the same atomic
reducer, including adjacent components whose projected placeholders are
otherwise indistinguishable. Undo and redo use source-owned history.

IME composition, canonical-source copy/cut/paste, and accessibility validation
remain explicit shipping blockers. The production adapter must constrain IME
to text leaves, defer projection changes until composition ends, and serialize
selected canonical source ranges rather than the projected placeholder buffer.

The adapter is replaceable. SuperEditor is an implementation detail, not an
architectural dependency, and its Markdown import/export APIs are never used.

## Cutover

An editor implementation is chosen once when a composer is created. A live
composer must never mix legacy parsing/rendering/input formatters with the new
session in the same frame.

The first representative migration is:

1. Local Date as a plugin-owned inline atom.
2. Quote as a core-owned block atom.

This pair exercises typed plugin registration, inline navigation,
source-captured action declarations, block measurement, range selection, and
atomic removal without adding upload or network lifecycle state.
Poll, link, image, gallery/grid, and upload then use the same conformance suite
and revision-bound action host.

The legacy `MarkdownEditingController` remains the fallback until the new
surface passes these gates on desktop and mobile:

- arrows, taps, drags, selection handles, Backspace, Delete, and Escape;
- IME composition immediately before and after inline atoms;
- bidirectional ranges across inline and block atoms;
- exact raw copy, cut, paste, undo, and redo;
- surface-wired edit/remove affordances across source changes and history;
- accessible labels, focus order, and actions for text and components;
- real block height in scrolling, hit testing, and caret navigation.
