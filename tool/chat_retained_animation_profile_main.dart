// Run in profile mode under the shared desktop/profiling lease.
// Three real GIFs enter the production chat viewport, become retained offscreen,
// re-enter, and finally get evicted. Samples do not add image stream listeners.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/shell/site_image.dart';
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
    if (element.widget case ChatMessageTile(
      messageId: final id,
    ) when const {98, 99, 100}.contains(id)) {
      rows.add(element);
    }
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
  void images(Element element, {bool target = false}) {
    final widget = element.widget;
    final withinTarget =
        target ||
        (widget is SiteImage &&
            const {
              '$chatScrollSite/animated-98.gif',
              '$chatScrollSite/animated-99.gif',
              '$chatScrollSite/animated-100.gif',
            }.contains(widget.url));
    if (withinTarget && widget is Image) trackedImages.add(element);
    element.visitChildren((child) => images(child, target: withinTarget));
  }

  for (final row in rows) {
    row.visitChildren((child) => images(child));
  }
  if (rows.length != 3 || trackedImages.length != 3) {
    throw StateError(
      'Expected exactly three mounted GIF rows and Images; '
      'found ${rows.length} rows and ${trackedImages.length} Images',
    );
  }
  final completers = [
    for (final element in trackedImages)
      (element.widget as Image).image
          .resolve(createLocalImageConfiguration(element))
          .completer!,
  ];
  if (!completers.every((c) => c is MultiFrameImageStreamCompleter)) {
    throw StateError(
      'Expected multi-frame image completers for the three GIFs',
    );
  }
  Map<String, int> phaseState(String phase) {
    var keptAlive = 0;
    var visible = 0;
    final viewport = scrollable!.context.findRenderObject()! as RenderBox;
    final viewportRect = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      Offset.zero & viewport.size,
    );
    for (final row in rows.where((e) => e.mounted)) {
      RenderObject? render = row.renderObject;
      while (render != null &&
          render.parentData is! SliverMultiBoxAdaptorParentData) {
        render = render.parent;
      }
      final parentData = render?.parentData;
      if (parentData is! SliverMultiBoxAdaptorParentData) {
        throw StateError('Tracked row is no longer owned by the chat sliver');
      }
      if (parentData.keptAlive) {
        keptAlive++;
      } else {
        final box = row.renderObject! as RenderBox;
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
        if (rect.overlaps(viewportRect)) visible++;
      }
    }
    final state = {
      'mountedRows': rows.where((e) => e.mounted).length,
      'mountedImages': trackedImages.where((e) => e.mounted).length,
      'keptAliveRows': keptAlive,
      'visibleRows': visible,
    };
    final expectedMounted = phase == 'evicted' ? 0 : 3;
    final expectedKeptAlive = phase == 'retained' ? 3 : 0;
    final expectedVisible = phase == 'visible' || phase == 'reentered' ? 3 : 0;
    if (state['mountedRows'] != expectedMounted ||
        state['mountedImages'] != expectedMounted ||
        keptAlive != expectedKeptAlive ||
        visible != expectedVisible) {
      throw StateError(
        'Invalid $phase phase: $state; expected '
        '$expectedMounted mounted rows/images, $expectedKeptAlive retained, '
        '$expectedVisible visible',
      );
    }
    return state;
  }

  final previous = <Element, ui.Image>{};
  var seededImages = 0;
  var imageFrames = 0;
  var schedulerFrames = 0;
  var sampling = false;
  void sampleRaw(Element element, {bool seed = false}) {
    if (element.widget case RawImage(image: final image?)) {
      if (seed) seededImages++;
      final old = previous[element];
      if (old == null || !old.isCloneOf(image)) {
        if (!seed) imageFrames++;
        old?.dispose();
        previous[element] = image.clone();
      }
    }
    element.visitChildren((child) => sampleRaw(child, seed: seed));
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
    final startState = phaseState(phase);
    foreground.lost = binding.lifecycleState != AppLifecycleState.resumed;
    // Reset to the actual frame displayed at this phase's start. Work during
    // scrolling/grace and the first observation must not count as idle changes.
    seededImages = 0;
    for (final image in trackedImages.where((e) => e.mounted)) {
      image.visitChildren((child) => sampleRaw(child, seed: true));
    }
    if (seededImages != startState['mountedImages']) {
      throw StateError('Expected a decoded RawImage for every tracked Image');
    }
    imageFrames = 0;
    schedulerFrames = 0;
    final timings = <ui.FrameTiming>[];
    void onTimings(List<ui.FrameTiming> frames) => timings.addAll(frames);
    binding.addTimingsCallback(onTimings);
    final startUs = developer.Timeline.now;
    sampling = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    final endUs = developer.Timeline.now;
    sampling = false;
    final endState = phaseState(phase);
    final foregroundValid = !foreground.lost;
    final lifecycle = binding.lifecycleState?.name;
    final transientCallbacks = binding.transientCallbackCount;
    final hasScheduledFrame = binding.hasScheduledFrame;
    // This isolated collector reads diagnostic state without adding listeners.
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    final imageListeners = completers.where((c) => c.hasListeners).length;
    // Profile timings arrive in batches. Keep the callback alive beyond the
    // measurement, then select only frames whose vsync started inside it.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    binding.removeTimingsCallback(onTimings);
    final selected = timings.where((frame) {
      final vsyncUs = frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      return vsyncUs >= startUs && vsyncUs < endUs;
    }).toList();
    results.add({
      'phase': phase,
      'foregroundValid': foregroundValid,
      'lifecycle': lifecycle,
      'startUs': startUs,
      'endUs': endUs,
      'durationUs': endUs - startUs,
      'startState': startState,
      'endState': endState,
      'sampleMs': 3000,
      'imageListeners': imageListeners,
      'imageFrames': imageFrames,
      'schedulerFrames': schedulerFrames,
      'uiFrameCount': selected.length,
      'vsyncStartUs': [
        for (final f in selected)
          f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
      ],
      'uiBuildUs': [for (final f in selected) f.buildDuration.inMicroseconds],
      'rasterUs': [for (final f in selected) f.rasterDuration.inMicroseconds],
      'uiBuildUsTotal': selected.fold<int>(
        0,
        (sum, f) => sum + f.buildDuration.inMicroseconds,
      ),
      'transientCallbacks': transientCallbacks,
      'hasScheduledFrame': hasScheduledFrame,
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
