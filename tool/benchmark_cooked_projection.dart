import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as parser;

String tableHtml(int rows) =>
    '<table><tr><th>Name</th><th>Value</th><th>Notes</th></tr>'
    '${List.generate(rows, (i) => '<tr><td>Member $i</td><td>${rows - i}</td><td><strong>Note $i</strong><br><a href="/t/example/12">link $i</a> &amp; <code>code $i</code></td></tr>').join()}</table>';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final trace = Platform.environment['COOKED_PROJECTION_TRACE'] == '1';
  void stage(String value) {
    if (trace) stdout.writeln(jsonEncode({'stage': value}));
  }

  stage('dart-started');
  await stdout.flush();
  runApp(const MaterialApp(home: SizedBox.shrink()));
  stage('initial-frame');
  await binding.endOfFrame.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      stderr.writeln('Initial frame timed out');
      exit(2);
    },
  );
  await const MethodChannel(
    'org.discourse.native/window',
  ).invokeMethod<void>('dismissLaunchScreen');
  stage('initial-frame-complete');
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.toString());
  };
  final result = <String, Object?>{};
  final source = tableHtml(1000);
  final table = parser.parseFragment(source).querySelector('table')!;
  final content = CookedDocument(
    source,
  ).bind((_, fragment, style) => Text(fragment.html));
  var checksum = 0;
  double measure(Widget? Function() run, int iterations) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final widget = run();
      if (widget == null) throw StateError('Table was not claimed');
      checksum += consumeTableProjection(widget);
    }
    watch.stop();
    return watch.elapsedMicroseconds / iterations;
  }

  for (var i = 0; i < 6; i++) {
    measure(() => cookedTableWidgetBuilder(table, content: content), 5);
  }
  result['table_adapter_us'] = measure(
    () => cookedTableWidgetBuilder(table, content: content),
    20,
  );
  result['table_parse_adapter_us'] = measure(
    () => cookedTableWidgetBuilder(
      parser.parseFragment(source).querySelector('table')!,
      content: content,
    ),
    15,
  );
  stage('adapters-complete');
  final key = GlobalKey();
  var mounted = tableHtml(250);
  Future<void> mount(int iteration) async {
    runApp(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: CookedHtml(
                key: ValueKey(iteration),
                html: mounted,
                siteUrl: 'https://example.test',
                buildAsync: false,
              ),
            ),
          ),
        ),
      ),
    );
    stage('mount-$iteration-first-frame');
    await binding.endOfFrame.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        stderr.writeln('Mount $iteration first frame timed out');
        exit(2);
      },
    );
    binding.scheduleFrame();
    stage('mount-$iteration-second-frame');
    await binding.endOfFrame.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        stderr.writeln('Mount $iteration second frame timed out');
        exit(2);
      },
    );
    stage('mount-$iteration-complete');
  }

  await mount(-1);
  final times = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    await mount(i);
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  result['table_mount_us'] = times;
  final watch = Stopwatch()..start();
  await mount(2);
  watch.stop();
  result['table_unchanged_rebuild_us'] = watch.elapsedMicroseconds;
  mounted = source;
  await mount(-2);
  final largeTimes = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    await mount(100 + i);
    watch.stop();
    largeTimes.add(watch.elapsedMicroseconds);
  }
  result['table_1000_mount_us'] = largeTimes;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final capture = Platform.environment['COOKED_PROJECTION_CAPTURE'];
  if (capture != null) {
    stage('capture-start');
    final image = await boundary
        .toImage(pixelRatio: 1)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            stderr.writeln('Capture timed out');
            exit(2);
          },
        );
    stage('capture-complete');
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    stdout.writeln(
      jsonEncode({'capture_png': base64Encode(bytes!.buffer.asUint8List())}),
    );
    image.dispose();
  }
  final text = <String>[];
  void collect(RenderObject object) {
    if (object is RenderParagraph) text.add(object.text.toPlainText());
    object.visitChildren(collect);
  }

  collect(boundary);
  if (!text.contains('Member 0') ||
      !text.contains('Member 24') ||
      text.contains('Member 249')) {
    errors.add('Mounted page did not contain exactly the expected row range');
  }
  result['rendered_text'] = text;
  result['render_size'] = [boundary.size.width, boundary.size.height];
  result['checksum'] = checksum;
  result['errors'] = errors;
  result['mode'] = 'macOS release AOT';
  result['rss_bytes_after'] = ProcessInfo.currentRss;
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
  exit(errors.isEmpty ? 0 : 1);
}

int consumeTableProjection(Widget widget) {
  final dynamic table = widget;
  var checksum = 2166136261;
  void consume(dynamic cell) {
    for (final value in [
      cell.text as String,
      cell.html as String,
      cell.copyText as String,
    ]) {
      for (final unit in value.codeUnits) {
        checksum = ((checksum ^ unit) * 16777619) & 0xffffffff;
      }
    }
  }

  for (final cell in table.headers as Iterable<Object>) {
    consume(cell);
  }
  for (final row in table.rows as Iterable<Iterable<Object>>) {
    for (final cell in row) {
      consume(cell);
    }
  }
  return checksum;
}
