# Keyed reader geometry

## Problem

TopicView used to coordinate post IDs, separated child indexes, cached heights,
and pre-layout scroll corrections with TopicPostSliver. The coordinator already
owns generation-safe restoration, paging and read timing. Preserve that policy
boundary and the existing SuperSliverList backend.

## Usage

TopicView constructs TopicReaderGeometry before TopicViewportCoordinator and
passes it as the coordinator's TopicViewportGeometry. Controller getters follow
the coordinator's current generation. The view passes each coordinator window
change to the adapter before constructing TopicPostSliver.

```dart
_reader.applyWindowChange(_viewport.updateWindow(snapshot, hasHeader: showHeader));
final posts = TopicPostSliver(geometry: _reader, itemCount: itemCount,
  itemBuilder: buildPost, separatorBuilder: buildSeparator);
final bounds = _reader.boundsForPost(postId);
```

The view supplies post content and decides first unread, day separators, HTML
measurement eligibility and widget retention. It reads semantic post indexes
from TopicPostWindow rather than decoding backend child ranges.

## Shape

TopicPostWindow owns the post ID projection, logical-item conversion, separator
keys and expanded-child conversion. A mapping belongs to one delegate build.
TopicReaderGeometry owns attached contexts, retained measurements, width,
sliver key and extent generation. It implements bounds, anchor capture, reveal
and jump operations. The adapter and specialized sliver, element, render object
and scroll position share the topic_post_sliver.dart library.

A prepend moves the backend extent table before delegate reconciliation, then
corrects pixels by the extent delta. It invalidates the former first post's
neighbor-dependent geometry. The render object repairs moved child offsets and
preceding-sliver changes. The scroll position repeats layout until an opening
or held target stabilizes. None of these corrections waits until paint.

TopicPostRetention still bounds live row trees. Retained large-row heights are
reused only for identical post and topic records, matching summary/read-time
inputs, and width within half a pixel. Unsettled bodies cannot overwrite a
settled larger measurement. Deferred invalidation checks controller and extent
generation before mutating the table.

## Synthesis decision

Two independent candidates considered a complete coordinator API redesign and
an adapter around the existing logical-item geometry contract. The independent
cross-judge selected the latter. It preserves restoration policy and adopts the
former candidate's ownership of contexts, measurements and backend corrections.
Model the Domain led to one window projection. Laziness Protocol kept the
coordinator's window classification and initial logical-item positioning.

## Tradeoffs and alternatives

The coordinator still uses logical item positions for stream-start and saved
post restoration. The adapter alone translates those positions into backend
children. A post-ID-only coordinator API would need another representation for
stream start and loading headers, broadening this behavior-preserving change.
A generic Topic and Chat reader would also combine different restoration and
live-edge policies. Neither alternative is part of this boundary.

The content snapshot supplies existing retained-height identity inputs. The
adapter does not fetch posts, admit retained trees or decide when a body is
settled. TopicView supplies those facts from its content and row lifecycle.

## Acceptance and implementation reconciliation

The initial 52 owning tests pass before extraction. The same files pin drag
continuity, viewport position, element identity, width reflow, progressive
content, paging, bounded retention and coordinator policy after extraction.
Additional mapping tests cover header and loading rows, keyed separators and
visible anchors. Header variants reuse the ID projection and anchor capture uses
the previous window. The scan-count pin covers both header transitions. The
view supplies whether the stream starts at its beginning independently of
loading-header presence, preserving the opening jump rule. The integration entry point runs the production reader's
churn, progressive content and moving-header cases on a native renderer. Its
short-topic fixture sizes the viewport from the laid-out document because
native fonts and platform chrome change the required short-scroll geometry.

The accepted implementation retains WindowChange and ExtentAction as coordinator
policy history and uses the adapter's window as the rendering projection.
Backend internals remain private in one Dart library. Deferred geometry work
also rejects a retired controller or extent generation, as requested by the
independent design review. This changes no read timing or Chat policy.

No scrolling speedup is claimed. The acceptance target is preserved behavior
and one owner for backend geometry knowledge.
