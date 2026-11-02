import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/topic_list_scroll_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile large desktop topic list scrolling', (tester) async {
    expect(Platform.isMacOS, isTrue);
    expect(kProfileMode, isTrue);
    SharedPreferences.setMockInitialValues({});
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
    const count = 3000;
    final shell = await topicListScrollController(
      count: count,
      pageSize: 30,
      events: true,
      assignments: true,
    );
    for (var page = 1; page < count ~/ 30; page++) {
      await shell.loadMoreFeed('latest');
    }
    expect(shell.currentFeed!.rowCount, count);
    addTearDown(() async {
      shell.dispose();
      await shell.pluginTeardown;
      await shell.plugins.close();
    });
    await tester.pumpWidget(
      TopicListScrollFixture(
        controller: shell,
        width: double.infinity,
        height: double.infinity,
      ),
    );
    await const MethodChannel(
      'org.discourse.native/window',
    ).invokeMethod<void>('dismissLaunchScreen');
    await tester.pumpAndSettle();
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(100000));
    final point = tester.getCenter(scrollable);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: point);
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();

    final profileCpu = Platform.environment['TOPIC_LIST_CPU'] == '1';
    final uri = (await developer.Service.getInfo()).serverUri!;
    final service = await vmServiceConnectUri(
      'ws://localhost:${uri.port}${uri.path}ws',
    );
    addTearDown(service.dispose);
    await service.setFlag('profiler', '$profileCpu');
    if (profileCpu) await service.setFlag('profile_period', '250');
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    final phases = <String, Object?>{};
    binding.reportData = {};
    Future<void> measure(String name, double delta) async {
      final before = position.pixels;
      final beforeTitle = tester
          .widget<TopicTitle>(find.byType(TopicTitle).first)
          .title;
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      if (profileCpu) await service.clearCpuSamples(isolate);
      binding.addTimingsCallback(collect);
      final start = developer.Timeline.now;
      final clock = Stopwatch()..start();
      const updates = 240;
      for (var step = 0; step < updates; step++) {
        final due = (step + 1) * 16667 - clock.elapsedMicroseconds;
        if (due > 0) await Future<void>.delayed(Duration(microseconds: due));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: Offset(0, delta),
            viewId: tester.view.viewId,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }
      await binding.endOfFrame;
      final end = developer.Timeline.now;
      final after = position.pixels;
      final afterTitle = tester
          .widget<TopicTitle>(find.byType(TopicTitle).first)
          .title;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      binding.removeTimingsCallback(collect);
      frames.removeWhere((f) {
        final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
        return t < start || t > end;
      });
      // Restoring variable-height rows legitimately corrects estimated offsets.
      // Bound that correction, and compare reached topics across both builds.
      expect(
        after - before,
        closeTo(updates * delta, (updates * delta).abs() * .05),
      );
      expect(afterTitle, isNot(beforeTitle));
      expect(frames.length, greaterThan(100));
      expect(clock.elapsed, lessThan(const Duration(seconds: 7)));
      expect(tester.takeException(), isNull);
      final phase = <String, Object?>{
        'wallMs': (end - start) / 1000,
        'updates': updates,
        'frames': frames.length,
        'offsetBefore': before,
        'offsetAfter': after,
        'firstTitleBefore': beforeTitle,
        'firstTitleAfter': afterTitle,
        'mountedTitles': find.byType(TopicTitle).evaluate().length,
        'build': _summary(frames.map((f) => f.buildDuration)),
        'raster': _summary(frames.map((f) => f.rasterDuration)),
        'total': _summary(frames.map((f) => f.totalSpan)),
      };
      phases[name] = phase;
      binding.reportData!['frameTimings.$name'] = [
        for (final f in frames)
          [
            f.timestampInMicroseconds(ui.FramePhase.buildStart),
            f.buildDuration.inMicroseconds,
            f.rasterDuration.inMicroseconds,
            f.totalSpan.inMicroseconds,
          ],
      ];
      if (profileCpu) {
        final samples = await service.getCpuSamples(
          isolate,
          start,
          end - start,
        );
        phase['cpuSamples'] = samples.sampleCount;
        phase['widgetCensus'] = _widgetCensus(tester);
        binding.reportData!['cpuFolded.$name'] = _folded(samples);
      }
      debugPrint(
        'TOPIC_LIST_PHASE $name ${jsonEncode(phase)}',
        wrapWidth: 8192,
      );
    }

    await measure('slowDown', 40);
    await measure('fastDown', 240);
    await measure('fastUp', -240);
    expect(shell.currentFeed!.rowCount, count);
    final summary = {
      'profileMode': kProfileMode,
      'profileCpu': profileCpu,
      'platform': defaultTargetPlatform.name,
      'physicalSize': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height,
      ],
      'pixelRatio': tester.view.devicePixelRatio,
      'topics': count,
      'failures': 0,
      'phases': phases,
    };
    binding.reportData!['summary'] = summary;
    final output = Platform.environment['TOPIC_LIST_OUTPUT'];
    if (output != null) {
      File(output).writeAsStringSync(jsonEncode(binding.reportData));
    }
    debugPrint('TOPIC_LIST_PROFILE ${jsonEncode(summary)}', wrapWidth: 16384);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, semanticsEnabled: false);
}

Map<String, Object> _summary(Iterable<Duration> durations) {
  final values = [for (final d in durations) d.inMicroseconds / 1000]..sort();
  double at(double q) =>
      values[(values.length * q).floor().clamp(0, values.length - 1)];
  return {
    'meanMs': values.reduce((a, b) => a + b) / values.length,
    'p50Ms': at(.5),
    'p95Ms': at(.95),
    'p99Ms': at(.99),
    'maxMs': values.last,
    'over8ms': values.where((v) => v > 8.333).length,
    'over16ms': values.where((v) => v > 16.667).length,
  };
}

String _folded(vm.CpuSamples samples) {
  final names = [
    for (final profile in samples.functions ?? const <vm.ProfileFunction>[])
      switch (profile.function) {
        vm.FuncRef(:final name, owner: vm.ClassRef(name: final owner)) ||
        vm.FuncRef(
          :final name,
          owner: vm.FuncRef(name: final owner),
        ) => '$owner.$name',
        vm.FuncRef(:final name) => '$name',
        vm.NativeFunction(:final name) => '$name',
        _ => profile.kind ?? '?',
      }.replaceAll(';', ':').replaceAll(' ', '_'),
  ];
  final counts = <String, int>{};
  for (final sample in samples.samples ?? const <vm.CpuSample>[]) {
    final stack = sample.stack;
    if (stack == null || stack.isEmpty) continue;
    final key = [for (final index in stack.reversed) names[index]].join(';');
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  return [for (final e in counts.entries) '${e.key} ${e.value}'].join('\n');
}

Map<String, Object> _widgetCensus(WidgetTester tester) {
  final widgets = <String, int>{};
  final tickerDomains = <Object, int>{};
  var elements = 0;
  for (final element in tester.allElements) {
    elements++;
    final name = element.widget.runtimeType.toString();
    widgets.update(name, (count) => count + 1, ifAbsent: () => 1);
    if (element is StatefulElement && element.state is TickerProvider) {
      final notifier = TickerMode.getValuesNotifier(element);
      tickerDomains.update(notifier, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final domains = tickerDomains.values.toList()..sort((a, b) => b.compareTo(a));
  final sorted = widgets.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    'elements': elements,
    'tickerProviders': domains.fold<int>(0, (sum, count) => sum + count),
    'tickerProvidersPerDomain': domains,
    'widgetCounts': Map.fromEntries(sorted),
  };
}
