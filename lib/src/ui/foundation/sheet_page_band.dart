import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// The reader position used before its first scroll layout.
enum DSheetReaderStart { top, scrolled }

class DSheetRiseScope extends InheritedWidget {
  const DSheetRiseScope({
    super.key,
    required this.edge,
    required this.overlap,
    required this.readerStart,
    required this.scrollTo,
    required super.child,
  });
  final ValueNotifier<double> edge;
  final double overlap;
  final DSheetReaderStart? readerStart;
  final ValueChanged<double> scrollTo;
  @override
  bool updateShouldNotify(DSheetRiseScope oldWidget) =>
      overlap != oldWidget.overlap || readerStart != oldWidget.readerStart;
}

/// Where the content of a page sheet says what its condensed head is doing
/// over the sheet's top edge, inside the card's rounded outline.
abstract interface class DSheetPageBand {
  DSheetReaderStart? get readerStart;
  void scrollTo(double offset);

  static ValueListenable<double>? edgeOf(BuildContext context) =>
      maybeOf(context) == null
      ? null
      : context.dependOnInheritedWidgetOfExactType<DSheetRiseScope>()?.edge;

  static Widget followEdge(BuildContext context, {required Widget child}) {
    final edge = edgeOf(context);
    return edge == null
        ? child
        : ValueListenableBuilder<double>(
            valueListenable: edge,
            builder: (_, value, child) =>
                Transform.translate(offset: Offset(0, value), child: child),
            child: child,
          );
  }

  /// [owner] is the head reporting; a later report from it replaces this one.
  /// [condensed]: the head is drawn in to its band. [coversGrabber]: enough is
  /// still there to cover the grabber.
  void report(
    Object owner, {
    required bool condensed,
    required bool coversGrabber,
  });

  /// [owner] no longer has a band over the sheet.
  void withdraw(Object owner);

  /// The page sheet [context] is in, if any.
  static DSheetPageBand? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DSheetPageBandScope>()?.band;
}

class DSheetPageBandScope extends InheritedWidget {
  const DSheetPageBandScope({
    super.key,
    required this.band,
    required super.child,
  });

  final DSheetPageBand band;

  @override
  bool updateShouldNotify(DSheetPageBandScope oldWidget) =>
      band != oldWidget.band;
}
