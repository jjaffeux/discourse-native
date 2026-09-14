import 'package:flutter/widgets.dart';

import 'composer_presentation.dart';
import 'shell_scope.dart';

/// Reports the painted reader, excluding navigation and the app-level composer.
class ReaderContentBounds extends StatefulWidget {
  const ReaderContentBounds({
    super.key,
    this.enabled = true,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<ReaderContentBounds> createState() => _ReaderContentBoundsState();
}

class _ReaderContentBoundsState extends State<ReaderContentBounds> {
  final _viewportKey = GlobalKey();

  void _report() {
    if (!mounted || !widget.enabled) return;
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
      ComposerPresentationHost.layoutChangesOf(context),
      ModalRoute.of(context)?.animation,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        if (widget.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        }
        return SizedBox.expand(key: _viewportKey, child: widget.child);
      },
    ),
  );
}
