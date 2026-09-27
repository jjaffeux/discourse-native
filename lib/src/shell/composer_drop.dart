import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/widgets.dart';

import '../models/composer_upload.dart';

/// A [DropTarget] that takes part in a native file drag only where it is what
/// the pointer is over.
///
/// `desktop_drop` hands every drag event to every enabled target whose box
/// contains the point, painted or not. Composers kept `Offstage` for another
/// tab or forum, a minimized composer's editor and the stacked chat pane
/// behind the visible one all keep that box, so without this gate a
/// screenshot dropped on one forum's sidebar would land in another forum's
/// hidden draft and upload to that forum's server. A position counts only
/// when this target is on the framework's own hit path there — the test a
/// click at that point passes — which an `Offstage` or `IgnorePointer`
/// ancestor, or a surface drawn over the target, all fail.
///
/// The gated callbacks keep the plugin's sequence: [onDragEntered] once the
/// pointer comes over the target, [onDragUpdated] while it moves there,
/// [onDragExited] when it leaves or is released, and [onDragDone] only for a
/// release over the target.
class NativeDropTarget extends StatefulWidget {
  const NativeDropTarget({
    super.key,
    required this.child,
    this.enable = true,
    this.onDragEntered,
    this.onDragUpdated,
    this.onDragExited,
    this.onDragDone,
  });

  final Widget child;
  final bool enable;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragUpdated;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragDoneCallback? onDragDone;

  @override
  State<NativeDropTarget> createState() => _NativeDropTargetState();
}

class _NativeDropTargetState extends State<NativeDropTarget> {
  bool _over = false;

  bool _aimedAt(Offset globalPosition) {
    final target = context.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return false;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      globalPosition,
      View.of(context).viewId,
    );
    return hit.path.any((entry) => identical(entry.target, target));
  }

  void _moved(DropEventDetails details) {
    if (!_aimedAt(details.globalPosition)) {
      _left(details);
    } else if (_over) {
      widget.onDragUpdated?.call(details);
    } else {
      _over = true;
      widget.onDragEntered?.call(details);
    }
  }

  void _left(DropEventDetails details) {
    if (!_over) return;
    _over = false;
    widget.onDragExited?.call(details);
  }

  void _dropped(DropDoneDetails details) {
    if (_aimedAt(details.globalPosition)) {
      _over = false;
      widget.onDragDone?.call(details);
      return;
    }
    _left(
      DropEventDetails(
        localPosition: details.localPosition,
        globalPosition: details.globalPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    enable: widget.enable,
    onDragEntered: _moved,
    onDragUpdated: _moved,
    onDragExited: _left,
    onDragDone: _dropped,
    // Translucent, so the whole region is on the hit path wherever it is
    // exposed, including gaps its children leave, without taking the hit from
    // anything behind it.
    child: MetaData(behavior: HitTestBehavior.translucent, child: widget.child),
  );
}

List<ComposerUploadFile> composerUploadFilesFromDrop(
  Iterable<DropItem> items,
) => List.unmodifiable([
  for (final item in items.whereType<DropItemFile>())
    ComposerUploadFile(
      name: item.name,
      length: () => _droppedFileLength(item),
      openRead: () => _openDroppedFile(item),
    ),
]);

bool dropContainsDirectory(Iterable<DropItem> items) =>
    items.any((item) => item is DropItemDirectory);

Stream<List<int>> _openDroppedFile(DropItemFile item) async* {
  final bookmark = item.extraAppleBookmark;
  var scoped = false;
  if (bookmark != null && bookmark.isNotEmpty) {
    scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  }
  try {
    yield* item.openRead();
  } finally {
    if (scoped) {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark!,
      );
    }
  }
}

Future<int> _droppedFileLength(DropItemFile item) async {
  final bookmark = item.extraAppleBookmark;
  var scoped = false;
  if (bookmark != null && bookmark.isNotEmpty) {
    scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  }
  try {
    return await item.length();
  } finally {
    if (scoped) {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark!,
      );
    }
  }
}
