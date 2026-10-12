import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';

/// A movable overlay whose visible surface is its entire hit target.
///
/// Dragging snaps to the nearest horizontal edge. Drag beyond that edge to
/// tuck the panel into a restore button. The caller owns the content and safe
/// area (including any navigation or keyboard insets). Tucking never disposes
/// the child or invokes its actions. Use the controller for non-drag actions.
class DFloatingPanel extends StatefulWidget {
  const DFloatingPanel({
    super.key,
    required this.child,
    required this.restoreLabel,
    this.controller,
    this.width = 184,
  });

  final Widget child;
  final String restoreLabel;
  final DFloatingPanelController? controller;
  final double width;

  @override
  State<DFloatingPanel> createState() => _DFloatingPanelState();
}

class DFloatingPanelController extends ChangeNotifier {
  bool _tucked = false;
  bool _right = true;
  bool get tucked => _tucked;
  bool get right => _right;

  void tuck() {
    if (_tucked) return;
    _tucked = true;
    notifyListeners();
  }

  void restore() {
    if (!_tucked) return;
    _tucked = false;
    notifyListeners();
  }

  void moveToEdge({required bool right}) {
    _right = right;
    _tucked = false;
    notifyListeners();
  }
}

class _DFloatingPanelState extends State<DFloatingPanel> {
  final _surfaceKey = GlobalKey();
  late DFloatingPanelController _controller;
  double _vertical = 1;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DFloatingPanelController();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(DFloatingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _controller.removeListener(_changed);
    if (oldWidget.controller == null) _controller.dispose();
    _controller = widget.controller ?? DFloatingPanelController();
    _controller.addListener(_changed);
    _drag = Offset.zero;
  }

  void _changed() => setState(() => _drag = Offset.zero);

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _finish(Size available) {
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final travel = Size(
      math.max(0, available.width - box.size.width),
      math.max(0, available.height - box.size.height),
    );
    final x = (_controller.right ? travel.width : 0) + _drag.dx;
    final y = (_vertical + 1) / 2 * travel.height + _drag.dy;
    final tuck = x < -32 || x > travel.width + 32;
    final right = x + box.size.width / 2 >= available.width / 2;
    setState(() {
      _vertical = travel.height == 0
          ? 1
          : (y / travel.height * 2 - 1).clamp(-1.0, 1.0);
      _drag = Offset.zero;
    });
    _controller.moveToEdge(right: right);
    if (tuck) _controller.tuck();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            AnimatedAlign(
              alignment: Alignment(_controller.right ? 1 : -1, _vertical),
              duration: _drag == Offset.zero
                  ? DMotion.duration(context, DMotion.change)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              child: Transform.translate(
                offset: _drag,
                child: GestureDetector(
                  onPanUpdate: _controller.tucked
                      ? null
                      : (details) => setState(() => _drag += details.delta),
                  onPanEnd: _controller.tucked
                      ? null
                      : (_) => _finish(available),
                  onPanCancel: () => setState(() => _drag = Offset.zero),
                  child: Semantics(
                    customSemanticsActions: {
                      CustomSemanticsAction(
                        label: context.l10n.floatingPanelMoveLeft,
                      ): () =>
                          _controller.moveToEdge(right: false),
                      CustomSemanticsAction(
                        label: context.l10n.floatingPanelMoveRight,
                      ): () =>
                          _controller.moveToEdge(right: true),
                      if (!_controller.tucked)
                        CustomSemanticsAction(
                          label: context.l10n.floatingPanelHide,
                        ): _controller.tuck,
                    },
                    child: Material(
                      elevation: 10,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(DRadius.panel),
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: _controller.tucked,
                            child: ExcludeFocus(
                              excluding: _controller.tucked,
                              child: SizedBox(
                                key: _surfaceKey,
                                width: math.min(widget.width, available.width),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: available.height,
                                  ),
                                  child: SingleChildScrollView(
                                    primary: false,
                                    child: widget.child,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_controller.tucked)
                            DButton.iconOnly(
                              key: const ValueKey('floating-panel-restore'),
                              tooltip: widget.restoreLabel,
                              variant: DButtonVariant.secondary,
                              icon: DIcon(
                                _controller.right
                                    ? DIcons.chevronLeft
                                    : DIcons.chevronRight,
                              ),
                              onPressed: _controller.restore,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
