import 'package:flutter/widgets.dart';

import 'composer/presentation_scope.dart';
import 'shell_scope.dart';

/// Names what moves the reader without giving it a new layout.
class ReaderMotionScope extends InheritedWidget {
  const ReaderMotionScope({
    super.key,
    required this.motion,
    required super.child,
  });

  final Listenable motion;

  @override
  bool updateShouldNotify(ReaderMotionScope oldWidget) =>
      motion != oldWidget.motion;
}

/// Reports the painted reader, excluding navigation and the app-level composer.
class ReaderContentBounds extends StatefulWidget {
  const ReaderContentBounds({super.key, required this.child});

  final Widget child;

  @override
  State<ReaderContentBounds> createState() => _ReaderContentBoundsState();
}

class _ReaderContentBoundsState extends State<ReaderContentBounds> {
  final _viewportKey = GlobalKey();

  void _report() {
    if (!mounted) return;
    final render = _viewportKey.currentContext?.findRenderObject();
    if (render is RenderBox && render.attached && render.hasSize) {
      ShellScope.read(context).reportReaderContentBounds(
        render.localToGlobal(Offset.zero) & render.size,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Physical docking and route animations can move the reader without
    // changing its size or requesting a new layout.
    listenable: Listenable.merge([
      ComposerPresentationScope.layoutChangesOf(context),
      ModalRoute.of(context)?.animation,
      context.dependOnInheritedWidgetOfExactType<ReaderMotionScope>()?.motion,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return SizedBox.expand(key: _viewportKey, child: widget.child);
      },
    ),
  );
}
