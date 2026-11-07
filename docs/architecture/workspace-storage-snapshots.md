# Workspace storage snapshots

`ForumTabStore.load` returns one immutable `ForumTabSnapshot` containing both
workspaces and their selected site. The storage adapter no longer publishes a
mutable selected-site property as a side effect of loading or saving.

Shell startup reads the workspace document alongside settings and instance
storage, then waits for those independent operations. It chooses the forum and
restores tabs from the same returned snapshot. Another operation on a reused
store cannot replace the selection belonging to that earlier document while
startup is waiting.

`_WorkspaceController` owns the last selection it requested for persistence.
That value only avoids duplicate saves; current shell selection remains the
navigation authority. Loading storage elsewhere cannot change this controller's
persistence bookkeeping. The value records an accepted save request, not a
claim that disk acknowledged the write.

Save calls still capture immutable workspace lists and coalesce through the
existing snapshot writer. Load results use the same snapshot type. The versioned
wire document, malformed-selection fallback, optional-state repair policy, and
refusal to overwrite an unreadable document remain unchanged.

Keeping a revision beside the former scalar side channel would leave callers
responsible for pairing two independently mutable values in the right order.
Returning the actual document makes that pairing part of the type and removes
the old API. All callers and the shared test fake use the new result directly.

`workspace_snapshot_selection_test.dart` gates the independent instance read,
changes selection through another save after workspace reading finishes, and
verifies startup keeps the selection from its own document. The previous code
opened the other forum. Store tests also verify snapshots and their lists remain
unchanged after later IO. Existing startup, tab, and default-route suites cover
restoration and persistence normalization.
