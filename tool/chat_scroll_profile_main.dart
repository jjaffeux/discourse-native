// flutter run --profile -d macos -t tool/chat_scroll_profile_main.dart
// Mounts the real channel with deterministic local messages and fake transport.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:flutter/widgets.dart';

import '../test/support/chat_scroll_fixture.dart';
import 'chat_scroll_trace.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final semantics = _option('SCROLL_SEMANTICS', 'false') == 'true'
      ? binding.ensureSemantics()
      : null;
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final rich =
      _option('SCROLL_RICH', const String.fromEnvironment('SCROLL_RICH')) ==
      'true';
  if (rich) MediaPipeline.replace(chatScrollMediaPipeline());
  const configuredMessages = String.fromEnvironment('SCROLL_MESSAGES');
  final controller = await chatScrollController(
    rich: rich,
    count: int.parse(
      _option(
        'SCROLL_MESSAGES',
        configuredMessages.isEmpty
            ? (rich ? '1000' : '500')
            : configuredMessages,
      ),
    ),
    directMessage:
        _option('SCROLL_DM', const String.fromEnvironment('SCROLL_DM')) ==
        'true',
    group:
        _option('SCROLL_GROUP', const String.fromEnvironment('SCROLL_GROUP')) ==
        'true',
  );
  final diagnostics = DiagnosticsController.start(
    persistence: MemoryDiagnosticsPersistence(),
  );
  runApp(
    ChatScrollFixture(
      controller: controller,
      diagnostics: diagnostics,
      width: double.parse(
        _option(
          'SCROLL_WIDTH',
          const String.fromEnvironment('SCROLL_WIDTH', defaultValue: '800'),
        ),
      ),
      dark:
          _option('SCROLL_DARK', const String.fromEnvironment('SCROLL_DARK')) ==
          'true',
    ),
  );
  await Future<void>.delayed(
    Duration(seconds: int.parse(_option('SCROLL_START_DELAY', '3'))),
  );
  ScrollableState? scrollable;
  void findScrollable(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
        scrollable ??= state;
      }
    }
    element.visitChildren(findScrollable);
  }

  binding.rootElement!.visitChildren(findScrollable);
  final position = scrollable!.position;
  final capture = diagnostics.topicScrollCapture;
  final label = _option(
    'SCROLL_LABEL',
    const String.fromEnvironment('SCROLL_LABEL', defaultValue: 'capture'),
  );
  final fastSteps = int.parse(
    _option('SCROLL_FAST_STEPS', rich ? '100' : '12'),
  );
  final local = _option('SCROLL_LOCAL', 'false') == 'true';
  for (final (name, delta, steps) in [
    ('steady', rich ? 40.0 : 10.0, 360),
    if (local) ...[
      ('revisit', -40.0, 180),
      ('reread', 40.0, 180),
    ] else ...[
      ('fast', 1200.0, fastSteps),
      ('return', -1200.0, fastSteps),
    ],
  ]) {
    final trace = _option('SCROLL_TRACE_PHASE', '') == name
        ? await ChatScrollTrace.start()
        : null;
    capture.start(
      displayRefreshRate:
          binding.platformDispatcher.views.first.display.refreshRate,
    );
    capture.recordTopicEvent('chat.fixture.phase', {
      'rich': rich,
      'semanticsEnabled': binding.semanticsEnabled,
      'phase': name,
      'steps': steps,
      'delta': delta,
      'startPixels': position.pixels,
      'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
    });
    for (var step = 0; step < steps; step++) {
      position.pointerScroll(delta);
      await binding.endOfFrame;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    var mountedMessages = 0;
    void countMessages(Element element) {
      if (element.widget is ChatMessageTile) mountedMessages++;
      element.visitChildren(countMessages);
    }

    binding.rootElement!.visitChildren(countMessages);
    capture.recordTopicEvent('chat.fixture.finished', {
      'mountedMessages': mountedMessages,
      'endPixels': position.pixels,
      'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
      'pendingImages': PaintingBinding.instance.imageCache.pendingImageCount,
    });
    capture.stop();
    await trace?.finish('$label-$name');
    final file = File(
      '${Directory.systemTemp.path}/chat-scroll-$label-$name.json',
    );
    await file.writeAsString(await capture.buildJsonReport());
    stdout.writeln('CHAT_SCROLL_PROFILE $name ${file.path}');
    final report = await capture.buildPerformanceReport();
    await File(
      file.path.replaceFirst('.json', '-summary.txt'),
    ).writeAsString(report);
    stdout.writeln(report);
  }
  stdout.writeln('CHAT_SCROLL_PROFILE complete');
  semantics?.dispose();
  if (_option('SCROLL_EXIT', 'false') == 'true') exit(0);
}

// Runtime overrides let the same native build compare all fixture layouts.
String _option(String name, String fallback) =>
    Platform.environment[name] ?? fallback;
