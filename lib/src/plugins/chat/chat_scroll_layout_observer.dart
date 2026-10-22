import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ChatScrollLayoutObserver extends SingleChildRenderObjectWidget {
  const ChatScrollLayoutObserver({
    super.key,
    required this.index,
    required this.onLayout,
    required super.child,
  });

  final int index;
  final ValueChanged<int> onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderChatScrollLayoutObserver(index, onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderChatScrollLayoutObserver renderObject,
  ) {
    renderObject
      ..index = index
      ..onLayout = onLayout;
  }
}

class RenderChatScrollLayoutObserver extends RenderProxyBox {
  RenderChatScrollLayoutObserver(this.index, this.onLayout);

  int index;
  ValueChanged<int> onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout(index);
  }
}
