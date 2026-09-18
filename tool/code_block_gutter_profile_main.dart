// Run with temporary instrumentation from code_block_gutter_instrument.py.
// GUTTER_MODE=baseline|fixed GUTTER_OUTPUT=/absolute/result.json
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

final _body = ValueNotifier<Widget>(const SizedBox.shrink());

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final semantics = binding.ensureSemantics();
  final foreground = _ForegroundGuard(binding);
  binding.addObserver(foreground);
  final records = <Map<String, Object?>>[];
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: _body,
          builder: (context, child, _) => child,
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 10));
  foreground.check();
  foreground.capturing = true;
  final view = binding.platformDispatcher.views.single;
  stdout.writeln(
    'GUTTER_METADATA ${jsonEncode({'mode': Platform.environment['GUTTER_MODE'], 'flutter': const String.fromEnvironment('PROFILE_FLUTTER_VERSION'), 'dart': Platform.version, 'os': Platform.operatingSystemVersion, 'dpr': view.devicePixelRatio, 'physicalWidth': view.physicalSize.width, 'physicalHeight': view.physicalSize.height, 'lifecycle': binding.lifecycleState.toString(), 'semanticsEnabled': binding.semanticsEnabled})}',
  );
  // Fixture parsing and token creation happen before the capture loops.
  final fixtures = <({int count, bool numbered, CodeBlockData data})>[];
  for (final count in [20, 100, 500, 1000]) {
    for (final numbered in [false, true]) {
      final lines = List.generate(
        count,
        (i) => '  final value$i = values[$i] + offset;',
      );
      final markup = numbered
          ? '<pre><code class="lang-text"><ol start="98">${lines.map((s) => '<li>$s</li>').join()}</ol></code></pre>'
          : '<pre><code class="lang-text">${lines.join('\n')}</code></pre>';
      fixtures.add((
        count: count,
        numbered: numbered,
        data: CodeBlockData.from(html.parse(markup).querySelector('pre')!),
      ));
    }
  }
  for (var cycle = 0; cycle < 4; cycle++) {
    for (final fixture in fixtures) {
      foreground.check();
      final key = GlobalKey();
      _body.value = SingleChildScrollView(
        child: CodeBlock(key: key, data: fixture.data),
      );
      await binding.endOfFrame;
      foreground.check(key);
      // Each rebuild executes production build and its LayoutBuilder callback.
      // Three warmups precede twelve retained callbacks per fixture/cycle.
      for (var iteration = 0; iteration < 15; iteration++) {
        foreground.check(key);
        stdout.writeln(
          'GUTTER_CASE ${jsonEncode({'cycle': cycle, 'lines': fixture.count, 'numbered': fixture.numbered, 'iteration': iteration, 'retained': iteration >= 3, 'semanticsEnabled': binding.semanticsEnabled})}',
        );
        final start = developer.Timeline.now;
        (key.currentContext! as Element).markNeedsBuild();
        await binding.endOfFrame;
        foreground.check(key);
        records.add({
          'cycle': cycle,
          'lines': fixture.count,
          'numbered': fixture.numbered,
          'iteration': iteration,
          'start': start,
          'frameComplete': developer.Timeline.now,
          'semanticsEnabled': binding.semanticsEnabled,
        });
      }
      _body.value = const SizedBox.shrink();
      await binding.endOfFrame;
    }
  }
  final output = Platform.environment['GUTTER_OUTPUT'];
  if (output != null) {
    await File(output).writeAsString(jsonEncode(records));
  }
  foreground.check();
  foreground.capturing = false;
  semantics.dispose();
  binding.removeObserver(foreground);
  stdout.writeln('GUTTER_DONE');
  exit(0);
}

class _ForegroundGuard extends WidgetsBindingObserver {
  _ForegroundGuard(this.binding);
  final WidgetsBinding binding;
  bool capturing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (capturing && state != AppLifecycleState.resumed) {
      stderr.writeln('GUTTER_INVALID foreground lost: $state');
      exit(2);
    }
  }

  void check([GlobalKey? key]) {
    if (!binding.semanticsEnabled) {
      stderr.writeln('GUTTER_INVALID semantics disabled');
      exit(2);
    }
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      stderr.writeln('GUTTER_INVALID not resumed: ${binding.lifecycleState}');
      exit(2);
    }
    if (key != null) {
      final render = key.currentContext?.findRenderObject();
      if (render is! RenderBox ||
          !render.attached ||
          !render.hasSize ||
          render.size.width <= 0 ||
          render.size.height <= 0) {
        stderr.writeln('GUTTER_INVALID missing mounted code block geometry');
        exit(2);
      }
    }
  }
}
