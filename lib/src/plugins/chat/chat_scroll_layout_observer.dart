import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../diagnostics/topic_scroll_capture.dart';

/// Reports actual row layouts without subscribing to capture state.
class ChatScrollLayoutObserver extends SingleChildRenderObjectWidget {
  const ChatScrollLayoutObserver({
    super.key,
    required this.capture,
    required this.index,
    required this.onLayout,
    required super.child,
  });

  final TopicScrollCaptureController? capture;
  final int index;
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderChatScrollLayoutObserver(capture, index, onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderChatScrollLayoutObserver renderObject,
  ) {
    renderObject
      ..capture = capture
      ..index = index
      ..onLayout = onLayout;
  }
}

class RenderChatScrollLayoutObserver extends RenderProxyBox {
  RenderChatScrollLayoutObserver(this.capture, this.index, this.onLayout);

  TopicScrollCaptureController? capture;
  int index;
  VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    final recorder = capture;
    if (recorder == null || !recorder.isRecording) {
      super.performLayout();
      return;
    }
    final started = developer.Timeline.now;
    super.performLayout();
    recorder.recordTopicEvent('chat.row.layout', {
      'index': index,
      'durationUs': developer.Timeline.now - started,
      'width': size.width,
      'height': size.height,
    });
  }
}
