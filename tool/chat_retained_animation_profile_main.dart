// Run in profile mode under the shared desktop/profiling lease.
// Three real GIFs enter the production chat viewport, become retained offscreen,
// re-enter, and finally get evicted. Samples do not add image stream listeners.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../test/support/chat_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final controller = await chatScrollController(
    count: 100,
    animatedBytes: base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
      'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
    ),
  );
  final diagnostics = DiagnosticsController.start(
    persistence: MemoryDiagnosticsPersistence(),
  );
  runApp(ChatScrollFixture(controller: controller, diagnostics: diagnostics));
  final foreground = _ForegroundProbe();
  binding.addObserver(foreground);
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (binding.lifecycleState != AppLifecycleState.resumed) {
    if (DateTime.now().isAfter(deadline)) {
      stderr.writeln(
        'CHAT_ANIMATION invalid: app did not enter resumed lifecycle',
      );
      exit(2);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(seconds: 3));
  final rows = <Element>[];
  ScrollableState? scrollable;
  void visit(Element element) {
    if (element.widget is ChatMessageTile) rows.add(element);
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
        scrollable ??= state;
      }
    }
    element.visitChildren(visit);
  }

  binding.rootElement!.visitChildren(visit);
  final trackedImages = <Element>[];
  void images(Element element) {
    if (element.widget is Image) trackedImages.add(element);
    element.visitChildren(images);
  }

  for (final row in rows) {
    row.visitChildren(images);
  }
  final completers = [
    for (final element in trackedImages)
      (element.widget as Image).image
          .resolve(createLocalImageConfiguration(element))
          .completer!,
  ];
  final previous = <Element, ui.Image>{};
  var imageFrames = 0;
  var schedulerFrames = 0;
  var sampling = false;
  void sampleRaw(Element element) {
    if (element.widget case RawImage(image: final image?)) {
      final old = previous[element];
      if (old == null || !old.isCloneOf(image)) {
        imageFrames++;
        old?.dispose();
        previous[element] = image.clone();
      }
    }
    element.visitChildren(sampleRaw);
  }

  binding.addPersistentFrameCallback((_) {
    if (!sampling) return;
    schedulerFrames++;
    // Capture after the widget frame has updated RawImage.
    binding.addPostFrameCallback((_) {
      for (final image in trackedImages) {
        if (image.mounted) image.visitChildren(sampleRaw);
      }
    });
  });
  final results = <Map<String, Object?>>[];
  Future<void> measure(String phase) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    foreground.lost = binding.lifecycleState != AppLifecycleState.resumed;
    imageFrames = 0;
    schedulerFrames = 0;
    final timings = <ui.FrameTiming>[];
    void onTimings(List<ui.FrameTiming> frames) => timings.addAll(frames);
    binding.addTimingsCallback(onTimings);
    sampling = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    sampling = false;
    binding.removeTimingsCallback(onTimings);
    var keptAlive = 0;
    for (final row in rows.where((e) => e.mounted)) {
      RenderObject? render = row.renderObject;
      while (render != null &&
          render.parentData is! SliverMultiBoxAdaptorParentData) {
        render = render.parent;
      }
      if ((render?.parentData as SliverMultiBoxAdaptorParentData?)?.keptAlive ==
          true) {
        keptAlive++;
      }
    }
    results.add({
      'phase': phase,
      'foregroundValid': !foreground.lost,
      'lifecycle': binding.lifecycleState?.name,
      'sampleMs': 3000,
      'trackedMountedRows': rows.where((e) => e.mounted).length,
      'trackedKeptAliveRows': keptAlive,
      // This isolated measurement fixture reads diagnostic state without
      // adding listeners that would change the behavior being measured.
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      'imageListeners': completers.where((c) => c.hasListeners).length,
      'imageFrames': imageFrames,
      'schedulerFrames': schedulerFrames,
      'uiFrameCount': timings.length,
      'uiBuildUsTotal': timings.fold<int>(
        0,
        (sum, f) => sum + f.buildDuration.inMicroseconds,
      ),
      'transientCallbacks': binding.transientCallbackCount,
      'hasScheduledFrame': binding.hasScheduledFrame,
    });
  }

  await measure('visible');
  final position = scrollable!.position;
  for (var i = 0; i < 8; i++) {
    position.pointerScroll(150);
    await binding.endOfFrame;
  }
  await measure('retained');
  for (var i = 0; i < 8; i++) {
    position.pointerScroll(-150);
    await binding.endOfFrame;
  }
  await measure('reentered');
  position.jumpTo(position.maxScrollExtent);
  await measure('evicted');
  final label = Platform.environment['CHAT_ANIMATION_LABEL'] ?? 'capture';
  final file = File('${Directory.systemTemp.path}/chat-animation-$label.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('CHAT_ANIMATION ${file.path}\n${await file.readAsString()}');
  for (final image in previous.values) {
    image.dispose();
  }
  runApp(const SizedBox.shrink());
  await binding.endOfFrame;
  await diagnostics.close();
  controller.dispose();
  exit(0);
}

class _ForegroundProbe extends WidgetsBindingObserver {
  bool lost = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) lost = true;
  }
}
