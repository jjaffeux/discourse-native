# Presentation preference acceptance

Presentation controllers accept a local choice and enqueue its persistence
before notifying listeners. A synchronous listener may accept another choice;
the existing store queues must observe those writes in the same order as the
choices. Otherwise a nested newer choice is queued first and the outer older
choice overwrites it after notification returns.

`ComposerPresentationController`, `TopicPresentationController`, and
`HeaderPreferencesController` follow this rule. Their public APIs preserve
accepted-choice ordering. Composer layout saves
use the shared coalescing snapshot writer: only the newest pending layout is
written, and superseded callers await that write. Reads wait for accepted saves.
Scalar preferences use the read-after-write queue so an older hydration read
does not delay a later save; controllers retain their hydration revision guards.
Header updates still return the completion of their
own accepted write. Composer changes with `persist: false` remain transient.
Delayed hydration still uses each controller's existing revision or edited
barrier. Retired account preference writes retain their storage guards.

App settings and forum theme-mode changes already enqueue before publication;
theme-library writes retain an explicit pending-write owner. Pane widths keep
an explicit dirty/flush contract. None needs a new generic preference writer
or changes to its hydration policy.

Tests for composer, topic, and header preferences synchronously choose a newer
value inside the first notification, then open a second controller against the
same storage. All four new reentrant cases failed before the ordering change.
The reopened controller now agrees with the latest accepted live choice.
