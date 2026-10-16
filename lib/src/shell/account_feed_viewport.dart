import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Keeps a surviving visible row in place when a bounded feed changes edges.
class AccountFeedViewport extends StatefulWidget {
  const AccountFeedViewport({
    super.key,
    required this.identity,
    required this.rows,
    required this.builder,
    this.separated = false,
    this.revealEnd = false,
  });

  final Object identity;
  final List<Object> rows;
  final bool separated;
  final bool revealEnd;
  final Widget Function(BuildContext, AccountFeedViewportState) builder;

  @override
  State<AccountFeedViewport> createState() => AccountFeedViewportState();
}

class AccountFeedViewportState extends State<AccountFeedViewport> {
  final scrollController = ScrollController();
  final listController = ListController();
  final Map<Object, GlobalKey> _keys = {};
  Object? _restoration;
  bool get restoring => _restoration != null;

  Widget row(Object id, Widget child) =>
      KeyedSubtree(key: _keys.putIfAbsent(id, GlobalKey.new), child: child);

  int? indexForKey(Key key) {
    for (final entry in _keys.entries) {
      if (entry.value != key) continue;
      final index = widget.rows.indexOf(entry.key);
      return index < 0 ? null : index * (widget.separated ? 2 : 1);
    }
    return null;
  }

  RenderBox? _box(Object id) {
    final object = _keys[id]?.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  @override
  void didUpdateWidget(AccountFeedViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _keys.clear();
      _revealBoundary();
      return;
    }
    if (listEquals(oldWidget.rows, widget.rows)) return;
    _restoration = null;
    final root = context.findRenderObject();
    final retained = widget.rows.toSet();
    Object? anchor;
    double? top;
    if (root is RenderBox && root.hasSize && scrollController.hasClients) {
      final bounds = root.localToGlobal(Offset.zero) & root.size;
      for (final id in oldWidget.rows) {
        if (!retained.contains(id)) continue;
        final box = _box(id);
        if (box == null) continue;
        final at = box.localToGlobal(Offset.zero).dy;
        if (at + box.size.height > bounds.top && at < bounds.bottom) {
          anchor = id;
          top = at;
          break;
        }
      }
    }
    _keys.removeWhere((id, _) => !retained.contains(id));
    if (anchor == null || top == null) {
      if (widget.rows.isNotEmpty) _revealBoundary(end: widget.revealEnd);
      return;
    }
    final targetIndex = widget.rows.indexOf(anchor);
    if (targetIndex == oldWidget.rows.indexOf(anchor)) return;
    final token = Object();
    _restoration = token;
    final savedAnchor = anchor;
    final savedTop = top;
    void restore({bool correct = true}) {
      if (!mounted ||
          !identical(_restoration, token) ||
          !listController.isAttached ||
          !scrollController.hasClients) {
        return;
      }
      final box = _box(savedAnchor);
      if (box == null) {
        listController.jumpToItem(
          index: targetIndex * (widget.separated ? 2 : 1),
          scrollController: scrollController,
          alignment: 0,
        );
      } else {
        final position = scrollController.position;
        final offset =
            scrollController.offset +
            box.localToGlobal(Offset.zero).dy -
            savedTop;
        if (offset.isFinite) {
          scrollController.jumpTo(
            offset.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        }
      }
      if (correct) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => restore(correct: false),
        );
        WidgetsBinding.instance.scheduleFrame();
      } else {
        _restoration = null;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  void _revealBoundary({bool end = false}) {
    final token = Object();
    _restoration = token;
    void reveal({bool correct = true}) {
      if (!mounted || !identical(_restoration, token)) return;
      if (scrollController.hasClients) {
        scrollController.jumpTo(
          end ? scrollController.position.maxScrollExtent : 0,
        );
      }
      if (end && correct) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => reveal(correct: false),
        );
        WidgetsBinding.instance.scheduleFrame();
      } else {
        _restoration = null;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
  }

  @override
  void dispose() {
    _restoration = null;
    listController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}
