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
import 'package:flutter/rendering.dart';
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
///
/// One launch records, per pass: frame timings, the requests the app made
/// (writes and topic loads are refused), which legs failed to move the list
/// and what the cursor hit instead, the elements mounted at its end, and,
/// for the two closing census passes, every build, layout and paint block
/// counted per frame.
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

    // The profile only scrolls lists. Anything that would act on the forum,
    // such as a hover prefetch counting a topic view, is refused and logged.
    final http = _ReadOnlyHttpOverrides();
    HttpOverrides.global = http;
    addTearDown(() => HttpOverrides.global = null);

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
        'activeTab': shell?.activeTabId,
        'content': shell?.currentContent?.destination.identity.toString(),
        'topicListContent': shell?.topicListContent?.destination.identity
            .toString(),
        'readingTopic': shell?.readingTopicId,
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
    Offset? hoverAt;
    if (const bool.fromEnvironment('LIVE_HOVER', defaultValue: true)) {
      final box = scrollable.context.findRenderObject()! as RenderBox;
      final at = hoverAt = box.localToGlobal(box.size.center(Offset.zero));
      await tester.sendEventToBinding(
        TestPointer(1, PointerDeviceKind.mouse).hover(at),
      );
    }

    // While a census pass runs, FlutterTimeline collects every build, layout
    // and paint block; it is drained between legs, outside any frame, so the
    // collection never holds more than one leg.
    var censusEnabled = false;
    final census = <TimedBlock>[];
    void drainCensus() {
      if (!censusEnabled) return;
      census.addAll(FlutterTimeline.debugCollect().timedBlocks);
    }

    const legDuration = Duration(seconds: 1);
    var pointerId = 100;
    var updates = 0;
    final track = <List<num>>[];
    // Per leg: where the list started and ended, whether a gesture at the
    // pointer reaches the list at all, and what is hit first there.
    final legLog = <List<Object>>[];
    Future<void> leg(ScrollableState scrollable, double pan) async {
      final box = scrollable.context.findRenderObject()! as RenderBox;
      // The system delivers a trackpad scroll at the cursor. The list's own
      // centre moves as its page header retracts.
      final origin = hoverAt ?? box.localToGlobal(box.size.center(Offset.zero));
      final hits = HitTestResult();
      binding.hitTestInView(hits, origin, tester.view.viewId);
      final reaches = hits.path.any((entry) => identical(entry.target, box));
      final first = [
        for (final entry in hits.path.take(8))
          switch (entry.target) {
            RenderParagraph(:final text) when !reaches =>
              'RenderParagraph("${text.toPlainText()}")',
            final target => '${target.runtimeType}',
          },
      ];
      if (!reaches) {
        debugPrint('LIVE_PROFILE_STATE pointer off the list: ${describe()}');
      }
      final startPixels = scrollable.position.pixels;
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
      drainCensus();
      legLog.add([
        developer.Timeline.now,
        startPixels,
        scrollable.position.pixels,
        reaches,
        first.join(' < '),
      ]);
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
      bool countBlocks = false,
    }) async {
      await service.setFlag('profiler', '$profile');
      censusEnabled = countBlocks;
      if (countBlocks) {
        census.clear();
        await service.setVMTimelineFlags([]);
        debugProfileBuildsEnabled = true;
        debugProfileLayoutsEnabled = true;
        debugProfilePaintsEnabled = true;
        FlutterTimeline.debugCollectionEnabled = true;
      }
      final requestsBefore = http.log.length;
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
      legLog.clear();
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
      if (countBlocks) {
        drainCensus();
        FlutterTimeline.debugCollectionEnabled = false;
        debugProfileBuildsEnabled = false;
        debugProfileLayoutsEnabled = false;
        debugProfilePaintsEnabled = false;
        censusEnabled = false;
      }
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
      data['legs.$name'] = List.of(legLog);
      (phases[name]! as Map)['stuckLegs'] = legLog
          .where((leg) => ((leg[2] as double) - (leg[1] as double)).abs() < 1)
          .length;
      data['shellNotifies.$name'] = List.of(shellNotifies);
      data['requests.$name'] = http.log.sublist(requestsBefore);
      data['elements.$name'] = _elementCensus();
      final images = PaintingBinding.instance.imageCache;
      (phases[name]! as Map)['imageCache'] = {
        'count': images.currentSize,
        'bytes': images.currentSizeBytes,
        'live': images.liveImageCount,
        'pending': images.pendingImageCount,
      };
      (phases[name]! as Map)['requests'] = http.log.length - requestsBefore;
      (phases[name]! as Map)['refused'] = http.log
          .sublist(requestsBefore)
          .where((r) => r[4] == true)
          .length;
      if (countBlocks) {
        data['census.$name'] = _censusReport(census, frames);
      }
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
    // Per-widget build, layout and paint blocks make these passes' timings
    // incomparable; they count what each frame did instead.
    if (const bool.fromEnvironment('LIVE_CENSUS', defaultValue: true)) {
      const censusLegs = int.fromEnvironment(
        'LIVE_CENSUS_LEGS',
        defaultValue: 6,
      );
      await measure(
        'topicList.censusUp',
        () async {
          final before = scrollable.position.pixels;
          for (var run = 0; run < censusLegs; run++) {
            await leg(scrollable, legDistance);
          }
          return scrollable.position.pixels - before;
        },
        profile: false,
        countBlocks: true,
      );
      await measure(
        'topicList.censusDown',
        () async {
          final before = scrollable.position.pixels;
          for (var run = 0; run < censusLegs; run++) {
            await leg(scrollable, -legDistance);
          }
          return scrollable.position.pixels - before;
        },
        profile: false,
        countBlocks: true,
      );
    }
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
      'requests': http.log.length,
      'refused': [
        for (final r in http.log)
          if (r[4] == true) '${r[1]} ${r[3]}',
      ],
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

/// Logs every request as `[timeUs, method, host, path, refused]` (query
/// strings dropped) and refuses the ones that would act on the forum: any
/// write other than the message bus's long poll, and topic loads, which
/// count a view.
final class _ReadOnlyHttpOverrides extends HttpOverrides {
  final log = <List<Object>>[];

  bool _refuses(String method, Uri url) {
    if (url.path.startsWith('/t/')) return true;
    if (method == 'GET' || method == 'HEAD') return false;
    return !url.path.startsWith('/message-bus/');
  }

  Future<HttpClientRequest> _open(
    HttpClient inner,
    String method,
    Uri url,
  ) async {
    final refused = _refuses(method.toUpperCase(), url);
    log.add([developer.Timeline.now, method, url.host, url.path, refused]);
    if (refused) {
      debugPrint('LIVE_PROFILE_REFUSED $method ${url.host}${url.path}');
      throw HttpException('refused by the read-only profile', uri: url);
    }
    return inner.openUrl(method, url);
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ReadOnlyHttpClient(super.createHttpClient(context), this);
}

final class _ReadOnlyHttpClient implements HttpClient {
  _ReadOnlyHttpClient(this._inner, this._guard);

  final HttpClient _inner;
  final _ReadOnlyHttpOverrides _guard;

  Uri _url(String host, int port, String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _guard._open(_inner, method, url);
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, _url(host, port, path));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;
  @override
  set keyLog(void Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// What is mounted at the end of a pass: the whole tree, and inside each
/// topic list the widget types, render objects and ticker-capable states.
Map<String, Object?> _elementCensus() {
  var tree = 0;
  void count(Element element) {
    tree++;
    element.visitChildren(count);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(count);
  final byType = <String, int>{};
  var elements = 0;
  var renderObjects = 0;
  var tickers = 0;
  var rows = 0;
  for (final list in find.byType(TopicListView).evaluate()) {
    void visit(Element element) {
      elements++;
      final type = element.widget.runtimeType.toString();
      byType.update(type, (n) => n + 1, ifAbsent: () => 1);
      if (type == '_TopicRow') rows++;
      if (element is RenderObjectElement) renderObjects++;
      if (element is StatefulElement && element.state is TickerProvider) {
        tickers++;
      }
      element.visitChildren(visit);
    }

    visit(list);
  }
  final top = byType.entries.toList()..sort((a, b) => b.value - a.value);
  return {
    'tree': tree,
    'listElements': elements,
    'listRenderObjects': renderObjects,
    'listTickerStates': tickers,
    'rows': rows,
    'byType': {for (final e in top.take(60)) e.key: e.value},
  };
}

/// Frame-phase blocks the framework names itself, as opposed to widget,
/// render object and paint blocks named by runtime type.
const _censusPhases = {
  'Animate',
  'BUILD',
  'LAYOUT',
  'LAYOUT (root)',
  'UPDATING COMPOSITING BITS',
  'PAINT',
  'COMPOSITING',
  'FINALIZE TREE',
  'SEMANTICS',
  'Semantics.updateChildren',
};

/// Aggregates census blocks by name (count, self and outermost-inclusive
/// microseconds) for the pass and for each of its slowest-building frames.
Map<String, Object?> _censusReport(
  List<TimedBlock> blocks,
  List<ui.FrameTiming> frames,
) {
  final sorted = [...blocks]
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.end.compareTo(a.end);
    });
  final self = List<double>.filled(sorted.length, 0);
  final outermost = List<bool>.filled(sorted.length, true);
  final stack = <int>[];
  final open = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    final block = sorted[i];
    while (stack.isNotEmpty && sorted[stack.last].end <= block.start) {
      final closed = stack.removeLast();
      open.update(sorted[closed].name, (n) => n - 1);
    }
    if (stack.isNotEmpty) self[stack.last] -= block.duration;
    self[i] += block.duration;
    outermost[i] = (open[block.name] ?? 0) == 0;
    open.update(block.name, (n) => n + 1, ifAbsent: () => 1);
    stack.add(i);
  }
  Map<String, List<num>> aggregate(Iterable<int> indices) {
    final out = <String, List<num>>{};
    for (final i in indices) {
      final entry = out.putIfAbsent(sorted[i].name, () => [0, 0.0, 0.0]);
      entry[0] = entry[0] + 1;
      entry[1] = entry[1] + self[i];
      if (outermost[i]) entry[2] = entry[2] + sorted[i].duration;
    }
    return out;
  }

  final windows = [
    for (final f in frames)
      (
        start: f.timestampInMicroseconds(ui.FramePhase.buildStart),
        end: f.timestampInMicroseconds(ui.FramePhase.buildFinish),
        build: f.buildDuration.inMicroseconds,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final perFrame = List.generate(windows.length, (_) => <int>[]);
  var w = 0;
  for (var i = 0; i < sorted.length; i++) {
    final at = sorted[i].start;
    while (w < windows.length && windows[w].end < at) {
      w++;
    }
    if (w < windows.length && windows[w].start <= at) perFrame[w].add(i);
  }
  final slowest = List.generate(windows.length, (i) => i)
    ..sort((a, b) => windows[b].build - windows[a].build);
  int widgetBlocks(List<int> indices) =>
      indices.where((i) => !_censusPhases.contains(sorted[i].name)).length;
  return {
    'blocks': sorted.length,
    'frames': windows.length,
    'framesWithBlocks': perFrame.where((f) => f.isNotEmpty).length,
    'blocksPerFrame': [for (final f in perFrame) widgetBlocks(f)],
    'buildUsPerFrame': [for (final f in windows) f.build],
    'byName': aggregate(List.generate(sorted.length, (i) => i)),
    'slowFrames': [
      for (final index in slowest.take(12))
        {
          'buildUs': windows[index].build,
          'startUs': windows[index].start,
          'blocks': widgetBlocks(perFrame[index]),
          'byName': aggregate(perFrame[index]),
        },
    ],
  };
}
