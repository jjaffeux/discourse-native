import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Builds the list between a [ChatChromeScrollView]'s header and footer.
///
/// [lazy] is true while the chrome stays fixed: the list then has a bounded
/// viewport of its own and scrolls itself. It is false while the chrome
/// scrolls with the list, which must then lay out every row at its natural
/// height.
typedef ChatChromeListBuilder =
    Widget Function(BuildContext context, bool lazy);

/// Fixes a Chat screen's header above its list, and an optional footer below
/// it, while the list keeps at least a touch target of the viewport. A shorter
/// viewport, such as a phone keyboard over enlarged text, leaves no room for
/// that chrome, so the list takes its natural height and the header, rows and
/// footer scroll as one view. Nested scrolling would strand the footer behind
/// the inner list.
///
/// The header and footer are measured in the same pass that decides, so the
/// switch follows the kit's control sizes and the text scale exactly. A
/// text-scaled height constant would be calibrated against today's controls
/// and overflow again when their sizes change.
class ChatChromeScrollView extends StatelessWidget {
  const ChatChromeScrollView({
    super.key,
    required this.header,
    required this.list,
    this.footer,
  });

  final Widget header;
  final ChatChromeListBuilder list;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) => SingleChildScrollView(
      // While the chrome stays fixed this view cannot scroll, so it leaves the
      // primary scroll controller to the list.
      primary: false,
      child: _ChromeLayout(
        viewportExtent: viewport.maxHeight,
        children: [
          header,
          LayoutBuilder(
            builder: (context, slot) => list(context, slot.hasBoundedHeight),
          ),
          ?footer,
        ],
      ),
    ),
  );
}

/// Lays out the header, the list and an optional footer. The list reads the
/// outcome from its constraints: a bounded height is a lazy list's own
/// viewport, an unbounded one asks for every row.
class _ChromeLayout extends MultiChildRenderObjectWidget {
  const _ChromeLayout({required this.viewportExtent, required super.children});

  final double viewportExtent;

  @override
  _RenderChromeLayout createRenderObject(BuildContext context) =>
      _RenderChromeLayout(viewportExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChromeLayout renderObject,
  ) {
    renderObject.viewportExtent = viewportExtent;
  }
}

class _ChromeParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChromeLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChromeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChromeParentData> {
  _RenderChromeLayout(this._viewportExtent);

  double _viewportExtent;
  set viewportExtent(double value) {
    if (value == _viewportExtent) return;
    _viewportExtent = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChromeParentData) {
      child.parentData = _ChromeParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final list = childAfter(header)!;
    final footer = childAfter(list);
    final width = constraints.maxWidth;
    final natural = BoxConstraints.tightFor(width: width);
    header.layout(natural, parentUsesSize: true);
    footer?.layout(natural, parentUsesSize: true);
    final headerExtent = header.size.height;
    final footerExtent = footer?.size.height ?? 0;
    final room = _viewportExtent - headerExtent - footerExtent;
    final double listExtent;
    if (room >= DSpacing.touchTarget) {
      list.layout(BoxConstraints.tightFor(width: width, height: room));
      listExtent = room;
    } else {
      list.layout(natural, parentUsesSize: true);
      listExtent = math.max(room, list.size.height);
    }
    final height = headerExtent + listExtent + footerExtent;
    (header.parentData! as _ChromeParentData).offset = Offset.zero;
    (list.parentData! as _ChromeParentData).offset = Offset(0, headerExtent);
    if (footer != null) {
      (footer.parentData! as _ChromeParentData).offset = Offset(
        0,
        height - footerExtent,
      );
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
