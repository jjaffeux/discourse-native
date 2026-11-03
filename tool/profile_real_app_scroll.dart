import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/main.dart' as production;
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

// A release-build entrypoint for the real, signed app and its existing data.
// Build with flutter build ios --release -t tool/profile_real_app_scroll.dart.
// SCROLL_PROFILE_AUTOSCROLL replays brisk swipes only on topic 195627;
// SCROLL_PROFILE_BUILD_CAUSES adds stack logging for attribution, not timing.
// Saves Documents/real-app-scroll-profile.json once collection has ended.
// It observes semantics without enabling or disabling accessibility. No labels,
// post text, URLs, account details, or images are recorded.
void main() {
  final binding = _ScrollProfileBinding();
  binding.start();
  production.main();
}

class _ScrollProfileBinding extends WidgetsFlutterBinding {
  static const duration = Duration(
    seconds: int.fromEnvironment('SCROLL_PROFILE_SECONDS', defaultValue: 120),
  );

  final rows = <Map<String, Object?>>[];
  bool collecting = true;
  int _lastTreeSample = 0;
  double? _scrollPixels;
  double? _scrollMax;

  void start() {
    rows.add({
      'kind': 'start',
      'utc': DateTime.now().toUtc().toIso8601String(),
      'us': developer.Timeline.now,
      'revision': const String.fromEnvironment('SCROLL_PROFILE_REVISION'),
      'semanticsEnabled': semanticsEnabled,
      'durationSeconds': duration.inSeconds,
    });
    addTimingsCallback(_timings);
    addSemanticsEnabledListener(_semanticsChanged);
    pointerRouter.addGlobalRoute(_pointer);
    if (const bool.fromEnvironment('SCROLL_PROFILE_BUILD_CAUSES')) {
      final scheduled = buildOwner!.onBuildScheduled;
      buildOwner!.onBuildScheduled = () {
        if (collecting) {
          rows.add({
            'kind': 'build-scheduled',
            'us': developer.Timeline.now,
            'stack': StackTrace.current.toString(),
          });
        }
        scheduled?.call();
      };
    }
    if (const bool.fromEnvironment('SCROLL_PROFILE_AUTOSCROLL')) {
      Timer(const Duration(seconds: 10), () => unawaited(_replay()));
    }
    Timer(duration, () => unawaited(_finish()));
  }

  @override
  PipelineOwner createRootPipelineOwner() => _ProfilePipelineOwner(this);

  @override
  Widget wrapWithDefaultView(Widget rootWidget) => super.wrapWithDefaultView(
    NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (collecting && notification.metrics.axis == Axis.vertical) {
          _scrollPixels = notification.metrics.pixels;
          _scrollMax = notification.metrics.maxScrollExtent;
          rows.add({
            'kind': 'scroll',
            'us': developer.Timeline.now,
            'event': notification.runtimeType.toString(),
            'depth': notification.depth,
            'pixels': notification.metrics.pixels,
            'maxScrollExtent': notification.metrics.maxScrollExtent,
            'viewportDimension': notification.metrics.viewportDimension,
          });
        }
        return false;
      },
      child: rootWidget,
    ),
  );

  Future<void> _replay() async {
    var topicPresent = false;
    ScrollPosition? topicPosition;
    void findScroll(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.axis == Axis.vertical &&
            position.hasContentDimensions &&
            position.viewportDimension >
                (topicPosition?.viewportDimension ?? 0)) {
          topicPosition = position;
        }
      }
      element.visitChildren(findScroll);
    }

    void findTopic(Element element) {
      if (element.widget case TopicView(:final route)
          when route?.topicId == 195627 &&
              ShellScope.read(element).currentContent?.topicId == 195627) {
        topicPresent = true;
        element.visitChildren(findScroll);
      }
      element.visitChildren(findTopic);
    }

    rootElement?.visitChildren(findTopic);
    if (!topicPresent) {
      rows.add({'kind': 'replay-error', 'reason': 'Algolia topic is not open'});
      return;
    }
    _scrollPixels = topicPosition?.pixels;
    _scrollMax = topicPosition?.maxScrollExtent;
    final view = platformDispatcher.implicitView!;
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    var forward = true;
    const legs = int.fromEnvironment('SCROLL_PROFILE_LEGS', defaultValue: 60);
    for (var leg = 0; collecting && leg < legs; leg++) {
      final pixels = _scrollPixels;
      final max = _scrollMax;
      if (pixels == null || max == null || max < 1000) {
        rows.add({'kind': 'replay-error', 'reason': 'No scrolling topic'});
        return;
      }
      if (pixels < 700) forward = true;
      if (max - pixels < 700) forward = false;
      final start = Offset(
        logicalSize.width / 2,
        logicalSize.height * (forward ? .7 : .3),
      );
      final delta = Offset(0, logicalSize.height * (forward ? -.4 : .4));
      final pointer = 1000 + leg;
      rows.add({
        'kind': 'replay-leg',
        'us': developer.Timeline.now,
        'forward': forward,
        'pixels': pixels,
      });
      handlePointerEvent(
        PointerDownEvent(
          pointer: pointer,
          position: start,
          timeStamp: Duration(microseconds: developer.Timeline.now),
        ),
      );
      final clock = Stopwatch()..start();
      var previous = start;
      while (clock.elapsedMilliseconds < 140) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        final position =
            start + delta * (clock.elapsedMicroseconds / 140000).clamp(0, 1);
        handlePointerEvent(
          PointerMoveEvent(
            pointer: pointer,
            position: position,
            delta: position - previous,
            timeStamp: Duration(microseconds: developer.Timeline.now),
          ),
        );
        previous = position;
      }
      handlePointerEvent(
        PointerUpEvent(
          pointer: pointer,
          position: previous,
          timeStamp: Duration(microseconds: developer.Timeline.now),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }

  void _timings(List<ui.FrameTiming> batch) {
    if (!collecting) return;
    for (final timing in batch) {
      rows.add({
        'kind': 'frame',
        'number': timing.frameNumber,
        'vsyncUs': timing.timestampInMicroseconds(ui.FramePhase.vsyncStart),
        'buildStartUs': timing.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        ),
        'buildFinishUs': timing.timestampInMicroseconds(
          ui.FramePhase.buildFinish,
        ),
        'rasterStartUs': timing.timestampInMicroseconds(
          ui.FramePhase.rasterStart,
        ),
        'rasterFinishUs': timing.timestampInMicroseconds(
          ui.FramePhase.rasterFinish,
        ),
        'buildUs': timing.buildDuration.inMicroseconds,
        'rasterUs': timing.rasterDuration.inMicroseconds,
        'totalUs': timing.totalSpan.inMicroseconds,
      });
    }
  }

  void _pointer(PointerEvent event) {
    if (!collecting || event is PointerHoverEvent) return;
    rows.add({
      'kind': 'pointer',
      'us': developer.Timeline.now,
      'event': event.runtimeType.toString(),
      'pointer': event.pointer,
      'x': event.position.dx,
      'y': event.position.dy,
    });
  }

  void _semanticsChanged() {
    if (collecting) {
      rows.add({
        'kind': 'semantics-enabled',
        'us': developer.Timeline.now,
        'enabled': semanticsEnabled,
      });
    }
  }

  void recordSemantics(int start, int elapsed) {
    if (!collecting) return;
    rows.add({
      'kind': 'semantics-flush',
      'us': start,
      'elapsedUs': elapsed,
      'enabled': semanticsEnabled,
    });
    if (start - _lastTreeSample < 1000000) return;
    _lastTreeSample = start;
    var nodes = 0;
    var labelCharacters = 0;
    bool visitNode(SemanticsNode node) {
      nodes++;
      labelCharacters += node.label.length;
      node.visitChildren(visitNode);
      return true;
    }

    void visitOwner(PipelineOwner owner) {
      final root = owner.semanticsOwner?.rootSemanticsNode;
      if (root != null) visitNode(root);
      owner.visitChildren(visitOwner);
    }

    visitOwner(rootPipelineOwner);
    rows.add({
      'kind': 'semantics-tree',
      'us': start,
      'nodes': nodes,
      'labelCharacters': labelCharacters,
    });
  }

  Future<void> _finish() async {
    collecting = false;
    removeTimingsCallback(_timings);
    removeSemanticsEnabledListener(_semanticsChanged);
    pointerRouter.removeGlobalRoute(_pointer);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/real-app-scroll-profile.json');
    await file.writeAsString(jsonEncode(rows));
    rows.clear();
  }
}

final class _ProfilePipelineOwner extends PipelineOwner {
  _ProfilePipelineOwner(this.binding) : super(onSemanticsUpdate: (_) {});

  final _ScrollProfileBinding binding;

  @override
  void flushSemantics() {
    final start = developer.Timeline.now;
    super.flushSemantics();
    binding.recordSemantics(start, developer.Timeline.now - start);
  }
}
