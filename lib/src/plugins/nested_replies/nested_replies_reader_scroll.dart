part of 'nested_replies_reader.dart';

class _NestedRepliesScrollController extends ScrollController {
  _NestedRepliesScrollController({super.initialScrollOffset});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _NestedRepliesScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );

  @override
  _NestedRepliesScrollPosition get position =>
      super.position as _NestedRepliesScrollPosition;

  void correctAnchor(double destination) => position.correctAnchor(destination);
}

class _NestedRepliesScrollPosition extends ScrollPositionWithSingleContext {
  _NestedRepliesScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  bool get hasUserMotion =>
      activity is DragScrollActivity || activity is BallisticScrollActivity;

  void correctAnchor(double destination) {
    final current = activity;
    if (current is DragScrollActivity) {
      forcePixels(destination);
    } else if (current is BallisticScrollActivity) {
      // Ballistic simulations use absolute pixels, so rebase after correction.
      final velocity = current.velocity;
      forcePixels(destination);
      goBallistic(velocity);
    } else {
      jumpTo(destination);
    }
  }
}
