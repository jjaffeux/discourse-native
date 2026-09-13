// flutter run --profile -d macos -t tool/long_post_render_profile_main.dart
// Isolates cold HTML rendering from topic pagination and networking.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

final _body = ValueNotifier<Widget>(const SizedBox.shrink());
final _layouts = <int>[];
final _frames = <ui.FrameTiming>[];

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  binding.addTimingsCallback(_frames.addAll);
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
  await Future<void>.delayed(const Duration(seconds: 2));
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  final service = uri == null
      ? null
      : await vmServiceConnectUri(uri.toString());
  final flags = await service?.getVMTimelineFlags();
  await service?.setVMTimelineFlags(
    {...?flags?.recordedStreams, 'Dart'}.toList(),
  );
  final results = <Map<String, Object?>>[];
  for (var run = 0; run < 4; run++) {
    for (final mode in [
      RenderMode.column,
      RenderMode.sliverList,
      const ProgressiveHtmlMode(),
    ]) {
      final scroll = ScrollController();
      _body.value = const SizedBox.shrink();
      await binding.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _frames.clear();
      _layouts.clear();
      final start = developer.Timeline.now;
      final html = List.generate(
        450,
        (i) =>
            '<p>Paragraph $i: This local paragraph '
            'exercises the production HTML renderer with variable post heights. '
            'Scrolling through a long discussion should remain responsive.</p>',
      ).join();
      Future<void>? mounting;
      final cooked = CookedHtml(
        html: html,
        buildAsync: true,
        renderMode: mode,
        textStyle: AppTheme.light.textTheme.bodyLarge?.copyWith(height: 1.5),
      );
      _body.value = NotificationListener<HtmlBodyMountingNotification>(
        onNotification: (notification) {
          mounting = notification.completion;
          return false;
        },
        child: Center(
          child: SizedBox(
            width: 680,
            child: SelectionArea(
              child: DScrollBar(
                controller: scroll,
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    if (mode != RenderMode.sliverList)
                      SliverToBoxAdapter(child: _MeasureLayout(child: cooked))
                    else
                      _MeasureSliver(child: cooked),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      var paragraphs = 0;
      void count(Element e) {
        if (e.widget is RichText) paragraphs++;
        e.visitChildren(count);
      }

      while (paragraphs == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        paragraphs = 0;
        binding.rootElement!.visitChildren(count);
      }
      final ready = developer.Timeline.now;
      if (mounting != null) {
        await mounting;
        await binding.endOfFrame;
      }
      final complete = developer.Timeline.now;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final timeline = await service?.getVMTimeline(
        timeOriginMicros: start,
        timeExtentMicros: complete - start,
      );
      final builds = _htmlBuildDurations(timeline);
      if (run == 0 && mode == RenderMode.column) {
        final file = File(
          '${Directory.systemTemp.path}/long-post-cold-timeline.json',
        );
        await file.writeAsString(jsonEncode(timeline?.toJson()));
      }
      final coldFrames = _frames
          .where(
            (f) => f.timestampInMicroseconds(ui.FramePhase.vsyncStart) >= start,
          )
          .toList();
      final coldLayouts = List.of(_layouts);
      _frames.clear();
      _layouts.clear();
      for (var i = 0; i < 60; i++) {
        scroll.position.pointerScroll(100);
        await binding.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final result = <String, Object?>{
        'run': run,
        'mode': mode == RenderMode.column
            ? 'column'
            : mode == RenderMode.sliverList
            ? 'sliver'
            : 'progressive',
        'htmlCharacters': html.length,
        'mountedParagraphs': paragraphs,
        'firstParagraphReadyUs': ready - start,
        'bodyCompleteUs': complete - start,
        'htmlTreeBuildUs': builds,
        'coldUiUs': coldFrames
            .map((f) => f.buildDuration.inMicroseconds)
            .toList(),
        'coldLayoutUs': coldLayouts,
        'scrollUiUs': _frames
            .map((f) => f.buildDuration.inMicroseconds)
            .toList(),
      };
      results.add(result);
      stdout.writeln('LONG_POST_RENDER ${jsonEncode(result)}');
      _body.value = const SizedBox.shrink();
      await binding.endOfFrame;
      scroll.dispose();
    }
  }
  await service?.setVMTimelineFlags(flags?.recordedStreams ?? []);
  await service?.dispose();
  final file = File(
    '${Directory.systemTemp.path}/long-post-render-profile.json',
  );
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('LONG_POST_RENDER complete ${file.path}');
}

List<int> _htmlBuildDurations(vm.Timeline? timeline) {
  final stacks = <int, List<({String name, int start})>>{};
  final durations = <int>[];
  for (final event in timeline?.traceEvents ?? <vm.TimelineEvent>[]) {
    final e = event.json ?? <String, Object?>{};
    final name = e['name'] as String? ?? '';
    final tid = e['tid'] as int?;
    final ts = e['ts'] as int?;
    if (tid == null || ts == null) continue;
    final stack = stacks.putIfAbsent(tid, () => []);
    if (e['ph'] == 'B') stack.add((name: name, start: ts));
    if (e['ph'] == 'E' && stack.isNotEmpty) {
      final start = stack.removeLast();
      if (start.name.startsWith('Build ') &&
          start.name.contains('HtmlWidget')) {
        durations.add(ts - start.start);
      }
    }
    if (e['ph'] == 'X' &&
        name.startsWith('Build ') &&
        name.contains('HtmlWidget')) {
      durations.add(e['dur'] as int);
    }
  }
  return durations;
}

class _MeasureLayout extends SingleChildRenderObjectWidget {
  const _MeasureLayout({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _Layout();
}

class _Layout extends RenderProxyBox {
  @override
  void performLayout() {
    final timer = Stopwatch()..start();
    super.performLayout();
    _layouts.add(timer.elapsedMicroseconds);
  }
}

class _MeasureSliver extends SingleChildRenderObjectWidget {
  const _MeasureSliver({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _SliverLayout();
}

class _SliverLayout extends RenderProxySliver {
  @override
  void performLayout() {
    final timer = Stopwatch()..start();
    super.performLayout();
    _layouts.add(timer.elapsedMicroseconds);
  }
}
