import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// Profiles trackpad scrolling of a live forum's topic list in the production
/// app, with the signed-in session, preferences and caches the build's
/// container already holds. Nothing is faked: feed pages, avatars and emoji
/// come from the forum.
///
/// It emits the same `DESKTOP_SCROLL_PHASE` and `DESKTOP_SCROLL_PROFILE`
/// lines and result shape as `desktop_scroll_profile_test.dart`, so
/// `tool/profile_desktop_scroll.py` runs it with Instruments attached.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile live topic list scrolling', semanticsEnabled: false, (
    tester,
  ) async {
    const siteHost = String.fromEnvironment(
      'LIVE_SITE',
      defaultValue: 'dev.discourse.org',
    );
    const legs = int.fromEnvironment('LIVE_LEGS', defaultValue: 12);
    const legDistance =
        0.0 + int.fromEnvironment('LIVE_LEG_PX', defaultValue: 1500);
    const profileCpu = bool.fromEnvironment('PROFILE_CPU', defaultValue: true);
    HttpClient.enableTimelineLogging = profileCpu;
    // Every widget build becomes a timeline event: names a frame's dirty
    // roots, at a cost that makes its timings incomparable.
    debugProfileBuildsEnabled = const bool.fromEnvironment('PROFILE_BUILDS');

    // A live forum can report image or layout errors the test binding would
    // turn into a failure; they are recorded with the result instead.
    final errors = <String>[];
    final testOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is TestFailure) return testOnError?.call(details);
      final line = details.exceptionAsString().split('\n').first;
      if (errors.length < 20) debugPrint('LIVE_PROFILE_ERROR $line');
      errors.add(line);
    };
    addTearDown(() => FlutterError.onError = testOnError);

    AppBootstrap.production(manifest: bundledPluginManifest).start();

    String describe() {
      final content = find.byType(MainContent).evaluate();
      final shell = content.isEmpty ? null : ShellScope.read(content.first);
      final lists = find.byType(TopicListView).evaluate();
      return jsonEncode({
        'mainContent': content.length,
        'loaded': shell?.loaded,
        'instances': [
          for (final DiscourseInstance i in shell?.instances ?? const []) i.url,
        ],
        'current': shell?.currentInstance?.url,
        'connected': shell?.currentInstance?.isConnected,
        'topicLists': lists.length,
        'scrollables': [
          for (final list in lists)
            for (final s
                in find
                    .descendant(
                      of: find.byWidget(list.widget),
                      matching: find.byType(Scrollable),
                    )
                    .evaluate())
              if ((s as StatefulElement).state case final ScrollableState st
                  when st.position.hasContentDimensions)
                [st.position.viewportDimension, st.position.maxScrollExtent],
        ],
      });
    }

    Future<T> until<T>(
      String what,
      T? Function() probe, {
      Duration timeout = const Duration(seconds: 90),
    }) async {
      final clock = Stopwatch()..start();
      while (clock.elapsed < timeout) {
        await tester.pump(const Duration(milliseconds: 100));
        if (probe() case final value?) return value;
      }
      debugPrint('LIVE_PROFILE_FAILED waiting for $what: ${describe()}');
      throw TestFailure('timed out waiting for $what');
    }

    final shell = await until<ShellController>('the shell', () {
      final content = find.byType(MainContent).evaluate();
      if (content.isEmpty) return null;
      final shell = ShellScope.read(content.first);
      return shell.loaded ? shell : null;
    });
    final index = shell.instances.indexWhere(
      (instance) => Uri.parse(instance.url).host == siteHost,
    );
    debugPrint('LIVE_PROFILE_STATE ${describe()}');
    expect(index, isNonNegative, reason: '$siteHost is not a saved site');
    if (shell.instanceIndex != index) shell.selectInstance(index);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      const window = MethodChannel('org.discourse.native/window');
      await window.invokeMethod<void>('toggleMaximized');
      // The zoom animates; measure only once the window size holds.
      var settled = 0;
      var size = tester.view.physicalSize;
      while (settled < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
        final next = tester.view.physicalSize;
        settled = next == size ? settled + 1 : 0;
        size = next;
      }
    }
    // The restored workspace may show a topic or another page; the profile
    // is of the site's Latest list in the active panel.
    shell.selectDestination(
      const SidebarDestination(
        id: 'latest',
        label: 'Latest',
        icon: DIcons.layerGroup,
      ),
      refreshIfSelected: false,
    );

    /// The topic list a pointer at its centre reaches, once it has rows
    /// enough to scroll.
    ScrollableState? reachableList() {
      final candidates = <ScrollableState>[];
      for (final list in find.byType(TopicListView).evaluate()) {
        void visit(Element child) {
          if (child is StatefulElement && child.state is ScrollableState) {
            final position = (child.state as ScrollableState).position;
            if (position.axis == Axis.vertical &&
                position.hasContentDimensions &&
                position.viewportDimension > 200) {
              candidates.add(child.state as ScrollableState);
            }
          }
          child.visitChildren(visit);
        }

        list.visitChildren(visit);
      }
      candidates.sort(
        (a, b) => b.position.viewportDimension.compareTo(
          a.position.viewportDimension,
        ),
      );
      for (final state in candidates) {
        final box = state.context.findRenderObject()! as RenderBox;
        final centre = box.localToGlobal(box.size.center(Offset.zero));
        final result = HitTestResult();
        binding.hitTestInView(result, centre, tester.view.viewId);
        if (result.path.any((entry) => identical(entry.target, box)) &&
            state.position.maxScrollExtent > state.position.viewportDimension) {
          return state;
        }
      }
      return null;
    }

    // At the top, the list's own extent check can fail while it is still
    // the list under the pointer, so the last one found stays in use.
    var scrollable = await until('a scrollable topic list', reachableList);
    // Let the first page's avatars and the session refresh land before the
    // first measured frame.
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    // During trackpad scrolling the cursor rests over the list, so rows
    // slide under a hovering mouse.
    if (const bool.fromEnvironment('LIVE_HOVER', defaultValue: true)) {
      final box = scrollable.context.findRenderObject()! as RenderBox;
      await tester.sendEventToBinding(
        TestPointer(
          1,
          PointerDeviceKind.mouse,
        ).hover(box.localToGlobal(box.size.center(Offset.zero))),
      );
    }

    const legDuration = Duration(seconds: 1);
    var pointerId = 100;
    var updates = 0;
    final track = <List<num>>[];
    Future<void> leg(ScrollableState scrollable, double pan) async {
      final box = scrollable.context.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(box.size.center(Offset.zero));
      final pointer = TestPointer(pointerId++, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(origin));
      final clock = Stopwatch()..start();
      while (clock.elapsed < legDuration) {
        final t = clock.elapsedMicroseconds / legDuration.inMicroseconds;
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(origin, pan: Offset(0, pan * t.clamp(0, 1))),
        );
        updates++;
        await binding.endOfFrame;
        final position = scrollable.position;
        track.add([
          developer.Timeline.now,
          position.pixels,
          position.maxScrollExtent,
        ]);
      }
      await tester.sendEventToBinding(pointer.panZoomEnd());
      final settle = Stopwatch()..start();
      while (settle.elapsed < const Duration(milliseconds: 500)) {
        await binding.endOfFrame;
        final position = scrollable.position;
        track.add([
          developer.Timeline.now,
          position.pixels,
          position.maxScrollExtent,
        ]);
      }
    }

    // Shell-facade notifications redraw every listener of the shell; their
    // timestamps are kept to line them up with feed page arrivals.
    final shellNotifies = <int>[];
    void onShellNotify() => shellNotifies.add(developer.Timeline.now);
    shell.addListener(onShellNotify);
    addTearDown(() => shell.removeListener(onShellNotify));

    final service = await _connect();
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    final phases = <String, Object?>{};
    final data = <String, Object?>{};

    Future<void> measure(
      String name,
      Future<double> Function() action, {
      required bool profile,
    }) async {
      await service.setFlag('profiler', '$profile');
      if (profile) {
        await service.setFlag('profile_period', '250');
        await service.clearCpuSamples(isolateId);
        await service.setVMTimelineFlags(['Dart', 'Embedder', 'GC']);
        await service.clearVMTimeline();
      }
      final frames = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      track.clear();
      shellNotifies.clear();
      debugPrint(
        'DESKTOP_SCROLL_PHASE start $name ${DateTime.now().microsecondsSinceEpoch}',
      );
      final startUs = developer.Timeline.now;
      final moved = await action();
      final endUs = developer.Timeline.now;
      debugPrint(
        'DESKTOP_SCROLL_PHASE end $name ${DateTime.now().microsecondsSinceEpoch}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      binding.removeTimingsCallback(collect);
      frames.removeWhere((f) {
        final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
        return t < startUs || t > endUs;
      });
      expect(frames.length, greaterThan(60), reason: name);
      phases[name] = {
        'legs': legs,
        'profiled': profile,
        'moved': moved,
        'seconds': (endUs - startUs) / 1e6,
        'frames': frames.length,
        'build': _summary(frames.map((f) => f.buildDuration)),
        'raster': _summary(frames.map((f) => f.rasterDuration)),
        'total': _summary(frames.map((f) => f.totalSpan)),
      };
      data['frameTimings.$name'] = [
        for (final f in frames)
          [
            f.timestampInMicroseconds(ui.FramePhase.buildStart),
            f.buildDuration.inMicroseconds,
            f.rasterDuration.inMicroseconds,
            f.timestampInMicroseconds(ui.FramePhase.rasterFinish),
            f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          ],
      ];
      data['track.$name'] = List.of(track);
      data['shellNotifies.$name'] = List.of(shellNotifies);
      if (!profile) return;
      await service.setVMTimelineFlags([]);
      final timeline = await service.getVMTimeline(
        timeOriginMicros: startUs,
        timeExtentMicros: endUs - startUs,
      );
      data['timeline.$name'] = timeline.json?['traceEvents'];
      final samples = await service.getCpuSamples(
        isolateId,
        startUs,
        endUs - startUs,
      );
      (phases[name]! as Map)['cpuSamples'] = samples.sampleCount;
      data['cpuFolded.$name'] = _folded(samples);
      final slow = [
        for (final f in frames)
          if (f.buildDuration > const Duration(milliseconds: 4))
            (
              start: f.timestampInMicroseconds(ui.FramePhase.buildStart),
              end: f.timestampInMicroseconds(ui.FramePhase.buildFinish),
            ),
      ];
      data['cpuFolded.$name.slow'] = _folded(samples, frames: slow);
      // A vsync the UI thread missed between two frames, short of the
      // phase's closing idle wait.
      final byVsync = [...frames]
        ..sort(
          (a, b) => a
              .timestampInMicroseconds(ui.FramePhase.vsyncStart)
              .compareTo(b.timestampInMicroseconds(ui.FramePhase.vsyncStart)),
        );
      final gaps = [
        for (var i = 1; i < byVsync.length; i++)
          if (byVsync[i].timestampInMicroseconds(ui.FramePhase.vsyncStart) -
                  byVsync[i - 1].timestampInMicroseconds(
                    ui.FramePhase.vsyncStart,
                  )
              case final gap when gap > 12000 && gap < 250000)
            (
              start: byVsync[i - 1].timestampInMicroseconds(
                ui.FramePhase.buildFinish,
              ),
              end: byVsync[i].timestampInMicroseconds(ui.FramePhase.buildStart),
            ),
      ];
      data['cpuFolded.$name.gaps'] = _folded(samples, frames: gaps);
    }

    Future<double> swipe(double pan, {bool untilEdge = false}) async {
      final before = scrollable.position.pixels;
      for (var run = 0; run < (untilEdge ? legs * 3 : legs); run++) {
        if (!scrollable.mounted) {
          debugPrint('LIVE_PROFILE_STATE list replaced: ${describe()}');
          scrollable = reachableList() ?? scrollable;
        }
        await leg(scrollable, pan);
        if (untilEdge && scrollable.position.pixels <= 0) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
      return scrollable.position.pixels - before;
    }

    // A negative trackpad pan reads toward the end of the list.
    await measure(
      'topicList.cold',
      () => swipe(-legDistance),
      profile: profileCpu,
    );
    await measure(
      'topicList.warmBack',
      () => swipe(legDistance, untilEdge: true),
      profile: profileCpu,
    );
    await measure(
      'topicList.warmTiming',
      () => swipe(-legDistance),
      profile: false,
    );
    await service.dispose();

    FlutterError.onError = testOnError;
    final view = tester.view;
    data['summary'] = {
      'label': const String.fromEnvironment(
        'PROFILE_LABEL',
        defaultValue: 'current',
      ),
      'site': siteHost,
      'platform': defaultTargetPlatform.name,
      'pixelRatio': view.devicePixelRatio,
      'physicalSize': [view.physicalSize.width, view.physicalSize.height],
      'refreshRate': view.display.refreshRate,
      'updates': updates,
      'hover': const bool.fromEnvironment('LIVE_HOVER', defaultValue: true),
      'profileBuilds': debugProfileBuildsEnabled,
      'errors': errors,
      'phases': phases,
    };
    final output = File(
      '${Directory.systemTemp.path}/desktop-scroll-profile.json',
    );
    await output.writeAsString(jsonEncode(data));
    debugPrint('DESKTOP_SCROLL_PROFILE ${output.path}');
    debugPrint(
      'DESKTOP_SCROLL_SUMMARY ${jsonEncode(data['summary'])}',
      wrapWidth: 1 << 20,
    );
  });
}

Future<vm.VmService> _connect() async {
  var info = await developer.Service.getInfo();
  if (info.serverUri == null) {
    info = await developer.Service.controlWebServer(enable: true);
  }
  final uri = info.serverUri!;
  return vmServiceConnectUri('ws://localhost:${uri.port}${uri.path}ws');
}

Map<String, Object> _summary(Iterable<Duration> durations) {
  final values = [for (final d in durations) d.inMicroseconds / 1000]..sort();
  double at(double q) =>
      values[math.min(values.length - 1, (values.length * q).floor())];
  return {
    'meanMs': values.reduce((a, b) => a + b) / values.length,
    'p50Ms': at(.5),
    'p90Ms': at(.9),
    'p99Ms': at(.99),
    'maxMs': values.last,
    'over8ms': values.where((v) => v > 8.333).length,
    'over16ms': values.where((v) => v > 16.667).length,
  };
}

String _folded(vm.CpuSamples samples, {List<({int start, int end})>? frames}) {
  final functions = samples.functions ?? const <vm.ProfileFunction>[];
  final names = [for (final f in functions) _functionName(f)];
  final counts = <String, int>{};
  for (final sample in samples.samples ?? const <vm.CpuSample>[]) {
    final stack = sample.stack;
    if (stack == null || stack.isEmpty) continue;
    String? root;
    if (frames != null) {
      final at = sample.timestamp ?? 0;
      final index = frames.indexWhere((f) => f.start <= at && at <= f.end);
      if (index < 0) continue;
      final frame = frames[index];
      final ms = ((frame.end - frame.start) / 1000).toStringAsFixed(1);
      root = 'frame_${index.toString().padLeft(3, '0')}_${ms}ms';
    }
    final key = [
      ?root,
      for (final index in stack.reversed)
        index < names.length ? names[index] : '?',
    ].join(';');
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final MapEntry(:key, :value) in counts.entries) '$key $value',
  ].join('\n');
}

String _functionName(vm.ProfileFunction profile) {
  final name = switch (profile.function) {
    vm.FuncRef(:final name, owner: vm.ClassRef(name: final owner)) ||
    vm.FuncRef(
      :final name,
      owner: vm.FuncRef(name: final owner),
    ) => '$owner.$name',
    vm.FuncRef(:final name) => '$name',
    vm.NativeFunction(:final name) => '$name',
    _ => profile.kind ?? '?',
  };
  final library = _library(profile.resolvedUrl ?? '');
  return '${name.replaceAll(';', ':').replaceAll(' ', '_')} [$library]';
}

final _packageLibrary = RegExp(
  r'/(?:pub\.dev/([a-z0-9_]+)-[^/]+|packages/([a-z0-9_]+))/lib/',
);

String _library(String url) {
  if (url.startsWith('dart:') ||
      url.startsWith('org-dartlang-sdk:') ||
      url.contains('/sdk/lib/')) {
    return 'dart';
  }
  if (url.startsWith('package:')) return url.substring(8).split('/').first;
  if (_packageLibrary.firstMatch(url) case final match?) {
    return match[1] ?? match[2]!;
  }
  return url.contains('/lib/') ? 'app' : 'Native';
}
