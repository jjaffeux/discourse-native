import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/models/forum_background.dart';
import 'src/shell/forum_theme_surfaces.dart';
import 'src/theme/app_theme.dart';

final _errors = <String>[];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    _errors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    _errors.add('$error');
    return false;
  };
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> with WidgetsBindingObserver {
  final _capture = GlobalKey();
  final _scroll = ScrollController();
  final _frames = <ui.FrameTiming>[];
  final _results = <Map<String, Object>>[];
  final _captureTimes = <String, List<int>>{};
  final _lifecycleChanges = <({int at, AppLifecycleState state})>[];
  var _effect = ForumBackgroundEffect.lava;
  var _enabled = true;
  var _reduced = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<ui.FrameTiming> values) => _frames.addAll(values);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleChanges.add((at: Timeline.now, state: state));
    stdout.writeln('DECORATIVE_LIFECYCLE ${state.name}');
  }

  Future<void> _sample(String phase, Future<void> Function() workload) async {
    _frames.clear();
    final initialLifecycle = WidgetsBinding.instance.lifecycleState?.name;
    final start = Timeline.now;
    await workload();
    final end = Timeline.now;
    await Future<void>.delayed(const Duration(milliseconds: 1250));
    if (!mounted) throw StateError('Fixture closed during $phase');
    final view = View.of(context);
    final frames = _frames.where((frame) {
      final time = frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      return time >= start && time < end;
    }).toList();
    final lifecycleStates = [
      initialLifecycle ?? 'unknown',
      ..._lifecycleChanges
          .where((change) => change.at >= start && change.at < end)
          .map((change) => change.state.name),
    ];
    final raster = frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    final build = frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final firstFrameGap = frames.isEmpty
        ? 0
        : frames.first.timestampInMicroseconds(ui.FramePhase.vsyncStart) -
              start;
    final lastFrameGap = frames.isEmpty
        ? 0
        : end - frames.last.timestampInMicroseconds(ui.FramePhase.vsyncStart);
    int percentile(List<int> values, double q) =>
        values.isEmpty ? 0 : values[((values.length - 1) * q).round()];
    final row = <String, Object>{
      'effect': _effect.name,
      'phase': phase,
      'elapsedUs': end - start,
      'startUs': start,
      'endUs': end,
      'frameTimingsUs': [
        for (final frame in frames)
          [
            frame.timestampInMicroseconds(ui.FramePhase.vsyncStart),
            frame.buildDuration.inMicroseconds,
            frame.rasterDuration.inMicroseconds,
            frame.totalSpan.inMicroseconds,
          ],
      ],
      'frames': frames.length,
      'rasterTotalUs': raster.fold<int>(0, (sum, v) => sum + v),
      'rasterP50Us': percentile(raster, .5),
      'rasterP95Us': percentile(raster, .95),
      'buildP95Us': percentile(build, .95),
      'scrollOffset': _scroll.offset,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
      'lifecycleStates': lifecycleStates,
      'width': view.physicalSize.width,
      'height': view.physicalSize.height,
      'pixelRatio': view.devicePixelRatio,
      'firstFrameGapUs': firstFrameGap,
      'lastFrameGapUs': lastFrameGap,
    };
    if ((phase == 'idle' || phase == 'scroll') && frames.isEmpty) {
      throw StateError('No submitted frames during $_effect $phase');
    }
    if ((phase == 'idle' || phase == 'scroll') &&
        lifecycleStates.any((state) => state != 'resumed')) {
      throw StateError(
        'Foreground state changed during $_effect $phase: $lifecycleStates',
      );
    }
    if ((phase == 'idle' || phase == 'scroll') &&
        (firstFrameGap > 100000 || lastFrameGap > 100000)) {
      throw StateError('Incomplete timing window for $_effect $phase');
    }
    if (_errors.isNotEmpty) throw StateError(_errors.join('\n'));
    _results.add(row);
    stdout.writeln('DECORATIVE_SAMPLE ${jsonEncode(row)}');
  }

  Future<void> _image(String path) async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _waitForEffect() async {
    final key = ValueKey(
      _effect == ForumBackgroundEffect.gradient
          ? 'forum-gradient-texture'
          : 'forum-reference-texture',
    );
    bool ready() {
      var found = false;
      void visit(Element element) {
        if (element.widget.key == key) found = true;
        element.visitChildElements(visit);
      }

      (_capture.currentContext! as Element).visitChildElements(visit);
      return found;
    }

    for (var attempt = 0; attempt < 150; attempt++) {
      if (_errors.isNotEmpty) throw StateError(_errors.join('\n'));
      if (ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('Decorative painter not ready for $_effect');
  }

  Future<void> _run() async {
    final name = Platform.environment['DECORATIVE_OUTPUT'];
    if (name == null) return;
    final output = '${Directory.systemTemp.path}/$name';
    try {
      if (Platform.isMacOS) {
        await const MethodChannel(
          'org.discourse.native/window',
        ).invokeMethod<void>('dismissLaunchScreen');
      }
      for (var attempt = 0; attempt < 100; attempt++) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw StateError(
          'Window did not become active: ${WidgetsBinding.instance.lifecycleState}',
        );
      }
      for (final effect
          in [ForumBackgroundEffect.lava, ForumBackgroundEffect.gradient].where(
            (effect) =>
                Platform.environment['DECORATIVE_EFFECT'] == null ||
                Platform.environment['DECORATIVE_EFFECT'] == effect.name,
          )) {
        setState(() {
          _effect = effect;
          _enabled = true;
          _reduced = false;
        });
        await _waitForEffect();
        await Future<void>.delayed(const Duration(seconds: 2));
        await _sample(
          'idle',
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await _sample('scroll', () async {
          if (!_scroll.hasClients || _scroll.position.maxScrollExtent < 900) {
            throw StateError(
              'Reader did not provide the required scroll range',
            );
          }
          await _scroll.animateTo(
            900,
            duration: const Duration(milliseconds: 1500),
            curve: Curves.linear,
          );
          if ((_scroll.offset - 900).abs() > 1) {
            throw StateError(
              'Reader did not reach the requested scroll offset',
            );
          }
          await _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 1500),
            curve: Curves.linear,
          );
        });
        setState(() => _enabled = false);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _sample(
          'covered',
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        setState(() {
          _enabled = true;
          _reduced = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _sample(
          'reduced',
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        setState(() => _reduced = false);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (Platform.environment['DECORATIVE_CAPTURE'] == 'true') {
          final times = _captureTimes[effect.name] = [];
          for (var i = 0; i < 60; i++) {
            times.add(Timeline.now);
            await _image(
              '$output-${effect.name}-${i.toString().padLeft(3, '0')}.png',
            );
            await Future<void>.delayed(const Duration(milliseconds: 33));
          }
        }
      }
      stdout.writeln(
        'DECORATIVE_RESULT ${jsonEncode({'platform': Platform.operatingSystem, 'release': const bool.fromEnvironment('dart.vm.product'), 'samples': _results, 'errors': _errors.length, 'output': output, 'captureTimesUs': _captureTimes})}',
      );
      await stdout.flush();
      exit(0);
    } catch (error, stack) {
      stderr.writeln(
        jsonEncode({
          'errors': _errors.length + 1,
          'error': '$error',
          'stack': '$stack',
        }),
      );
      await stderr.flush();
      exit(1);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeAnimationStyle: AnimationStyle.noAnimation,
    theme: DMaterialTheme.apply(
      AppTheme.forBrightness(
        Brightness.dark,
        background: ForumBackground.appearance(
          effect: _effect,
          noiseIntensity: .7,
        ),
      ),
      DAppearanceMaterial.standard,
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: _reduced),
      child: TickerMode(
        enabled: _enabled,
        child: RepaintBoundary(
          key: _capture,
          child: ForumWindowBackground(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 64, 40, 32),
              child: DPageSurface.headed(
                title: const Text('Reading with a decorative background'),
                controls: DButton(onPressed: () {}, label: const Text('Reply')),
                bodyBuilder: (context, header) => DPageScrollInsets(
                  builder: (context, padding) => ListView.builder(
                    controller: _scroll,
                    padding: padding,
                    itemCount: 100,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Post ${index + 1}. The animation should remain subtle while the reader scrolls through this discussion. The text stays still when reading stops.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium!.copyWith(inherit: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
