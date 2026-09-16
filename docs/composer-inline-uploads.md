# Inline topic uploads

Topic uploads reserve editable document slots as soon as files are admitted.
Each slot projects the existing Native `DAttachment` upload row inside the
composer, with progress, retry and cancel actions. Completed standalone uploads
replace their own slot atomically, preserving selections and text on either side.
Plugin targets, including chat, retain their existing attachment workflow.

Slots are draft-local tokens and are stripped from saved and submitted Markdown.
Removing slots cancels all affected requests before any ready peers are flushed.
Undo cannot revive a completed or cancelled request. Existing gallery routing,
automatic grouping and failure/retry ordering remain in the controller; pending
gallery rows appear beside the destination gallery.

## Verification — 2026-09-16

- `flutter analyze --no-pub`: clean.
- Focused composer/controller, spacing, submission, close-safety, image/gallery,
  picker, panel-control and component-conformance tests: 213 passed, followed by
  two additional regression tests for deleting a batch with a ready result and
  keeping a caret before a newly created gallery. The affected five suites were
  rerun after those fixes: 127 passed.
- Topic upload panel `upload lifecycle` group: 17 passed (picker, paste, drop,
  validation, progress and failed actions).
- Focused chat upload/drop tests: 12 passed.
- macOS debug fixture build passed. An isolated ad-hoc-signed app with the
  production `ComposerEditor` and in-memory uploader was inspected through CUA.
  Checked light/wide and dark/320px layouts, typing after pending slots, multiple
  uploads, cancelling the first slot independently, failure/retry and replacement
  with the image projection. No real file upload or account write was used; the
  completed image used a fixture URL, so network image decoding was not tested.
  The final controller-only batch-deletion and caret-boundary fixes were verified
  by the focused tests above. Mobile checks were widget tests, not device tests.

The broader upload-panel/chat/attachment-fixture run also reproduced 11 unrelated
failures on unchanged main `e0463c02`, verified in an isolated baseline checkout:
old Material control finders and existing selection/media toolbar overflows.
Those failures were left outside this change. All topic upload-lifecycle cases
and the chat upload/drop cases pass.
