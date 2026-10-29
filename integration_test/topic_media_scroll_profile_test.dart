import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';
import '../test/support/media_pipeline.dart';
import '../test/support/topic_post_list.dart';
import 'topic_media_fixtures.dart';

const _host = 'scroll.example';
const _site = 'https://$_host';
const _postCount = 120;
const _users = [
  'sam',
  'alex',
  'jordan',
  'riley',
  'morgan',
  'casey',
  'taylor',
  'quinn',
];
const _reactionIds = [
  'heart',
  '+1',
  'laughing',
  'open_mouth',
  'clap',
  'tada',
  'eyes',
  'rocket',
];

/// Profiles scrolling a reply stream dense with lightboxed photos, PNG
/// screenshots, animated GIFs, still and animated AVIF, emoji, reactions and
/// formatted text. Every byte is served from memory, so a run needs no forum.
///
/// The run reads down the whole topic, building every reply and decoding
/// every image as it scrolls in, then back up over what it built. Each phase
/// reports frame timings and a folded Dart CPU profile of the UI isolate
/// (`cpuFolded.<phase>`, one `frame;frame;leaf count` line per stack);
/// `tool/topic_media_scroll_profile.py` turns them into flame graphs. With
/// `PROFILE_TIMELINE=true` the run instead records the VM timeline of the
/// first part of the cold read with per-widget build, layout and paint
/// events (`timeline`).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // A phone runs without semantics unless assistive technology asks for
  // them; testWidgets would otherwise build the tree on every frame.
  testWidgets(
    'profile scrolling a media-heavy topic',
    semanticsEnabled: false,
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }

      final media = await Isolate.run(_Media.generate);
      final served = <String, int>{};
      final client = MockClient((request) async {
        final path = request.url.path;
        final (bytes, type) = media.serve(path);
        served.update(type ?? 'missing', (n) => n + 1, ifAbsent: () => 1);
        if (bytes == null) return http.Response('', 404);
        // A distinct buffer per URL, as the network would deliver: identical
        // bytes would share decoded images and hide repeated decodes.
        return http.Response.bytes(
          Uint8List.fromList(bytes),
          200,
          headers: {'content-type': type!},
        );
      });
      installTestMediaPipeline(client: client);

      final posts = [
        for (var n = 1; n <= _postCount; n++)
          Post.fromJson(_postJson(n), _site, extensions: pluginRegistry),
      ];
      final lifecycle = SiteLifecycle();
      final siteImages = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle,
        client: client,
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance(_host)]),
        api: FakeDiscourseApi(
          topics: {
            7: topicPayload(
              id: 7,
              title: 'Show your desk setup',
              posts: posts,
              postsCount: posts.length,
            ),
          },
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        lifecycle: lifecycle,
        siteImages: siteImages,
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'desks', title: 'Desks'),
      );
      await shell.loadTopic(7, 'desks');
      expect(shell.currentPostIds, hasLength(_postCount));

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        // An iPhone 15 Pro viewport, so the layout and decode sizes match the
        // phone; the desktop window only clips what it composites.
        tester.view.physicalSize = const Size(1179, 2556);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
      }
      final theme = AppTheme.light.copyWith(platform: TargetPlatform.iOS);
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: TopicView(inbox: false, route: shell.currentContent),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = topicPostList(tester);
      final scroll = list.controller!;

      // A brisk reading pace: one 2000 px swipe a second, each released
      // without a fling so every leg covers the same distance.
      const legDistance = 2000.0;
      const legDuration = Duration(seconds: 1);
      var updates = 0;
      final origin = tester.getCenter(topicPostListFinder());
      Future<void> leg(double delta) async {
        final drag = scroll.position.drag(
          DragStartDetails(globalPosition: origin),
          () {},
        );
        final clock = Stopwatch()..start();
        var travelled = 0.0;
        while (clock.elapsed < legDuration) {
          final next =
              delta *
              (clock.elapsedMicroseconds / legDuration.inMicroseconds).clamp(
                0.0,
                1.0,
              );
          drag.update(
            DragUpdateDetails(
              globalPosition: origin + Offset(0, next),
              delta: Offset(0, next - travelled),
              primaryDelta: next - travelled,
            ),
          );
          travelled = next;
          updates++;
          await binding.endOfFrame;
        }
        drag.update(
          DragUpdateDetails(
            globalPosition: origin + Offset(0, delta),
            delta: Offset(0, delta - travelled),
            primaryDelta: delta - travelled,
          ),
        );
        drag.end(DragEndDetails(primaryVelocity: 0));
      }

      /// Swipes toward the end of the topic, or back to its start when
      /// [down] is false, until it stops moving or [legs] run out.
      Future<int> read({required bool down, int legs = 1 << 30}) async {
        var run = 0;
        while (run < legs) {
          final before = scroll.position.pixels;
          await leg(down ? -legDistance : legDistance);
          run++;
          final position = scroll.position;
          if ((position.pixels - before).abs() < legDistance / 2 ||
              (down && position.pixels >= position.maxScrollExtent - 1) ||
              (!down && position.pixels <= position.minScrollExtent + 1)) {
            break;
          }
        }
        // Let a released overscroll settle before the next phase.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return run;
      }

      binding.reportData ??= {};
      final phases = <String, Object?>{};
      const timelineRun = bool.fromEnvironment('PROFILE_TIMELINE');
      const profileCpu = bool.fromEnvironment(
        'PROFILE_CPU',
        defaultValue: true,
      );
      if (timelineRun) {
        // Per-widget build, layout and paint events cost time themselves:
        // this run attributes work and is never compared for timing.
        debugProfileBuildsEnabled = true;
        debugProfileLayoutsEnabled = true;
        debugProfilePaintsEnabled = true;
        try {
          await binding.traceAction(
            () => read(down: true, legs: 6),
            streams: ['Dart', 'Embedder', 'GC'],
          );
        } finally {
          debugProfileBuildsEnabled = false;
          debugProfileLayoutsEnabled = false;
          debugProfilePaintsEnabled = false;
        }
      } else {
        final service = await _connect();
        final isolateId = developer.Service.getIsolateId(Isolate.current)!;
        // Four samples a millisecond, so a single slow frame holds enough
        // of them to attribute. Sampling costs frame time itself, so timing
        // comparisons run with PROFILE_CPU=false.
        await service.setFlag('profiler', '$profileCpu');
        if (profileCpu) await service.setFlag('profile_period', '250');
        Future<void> measure(String name, Future<int> Function() action) async {
          if (profileCpu) await service.clearCpuSamples(isolateId);
          final frames = <ui.FrameTiming>[];
          void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
          binding.addTimingsCallback(collect);
          final startUs = developer.Timeline.now;
          final legs = await action();
          final endUs = developer.Timeline.now;
          await Future<void>.delayed(const Duration(seconds: 1));
          binding.removeTimingsCallback(collect);
          frames.removeWhere((f) {
            final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
            return t < startUs || t > endUs;
          });
          expect(frames.length, greaterThan(100), reason: name);
          phases[name] = {
            'legs': legs,
            'seconds': (endUs - startUs) / 1e6,
            'frames': frames.length,
            'build': _summary(frames.map((f) => f.buildDuration)),
            'raster': _summary(frames.map((f) => f.rasterDuration)),
            'total': _summary(frames.map((f) => f.totalSpan)),
          };
          binding.reportData!['frameTimings.$name'] = [
            for (final f in frames)
              [
                f.timestampInMicroseconds(ui.FramePhase.buildStart),
                f.buildDuration.inMicroseconds,
                f.rasterDuration.inMicroseconds,
                f.timestampInMicroseconds(ui.FramePhase.rasterFinish),
              ],
          ];
          if (!profileCpu) return;
          final samples = await service.getCpuSamples(
            isolateId,
            startUs,
            endUs - startUs,
          );
          (phases[name]! as Map)['cpuSamples'] = samples.sampleCount;
          binding.reportData!['cpuFolded.$name'] = _folded(samples);
          // Frames that used more than half the 120 Hz budget to build, each
          // folded under its own root so the tail can be read frame by frame.
          final slow = [
            for (final f in frames)
              if (f.buildDuration > const Duration(milliseconds: 4))
                (
                  start: f.timestampInMicroseconds(ui.FramePhase.buildStart),
                  end: f.timestampInMicroseconds(ui.FramePhase.buildFinish),
                ),
          ];
          binding.reportData!['cpuFolded.$name.slow'] = _folded(
            samples,
            frames: slow,
          );
        }

        // First exposure: every reply is built, and every image fetched and
        // decoded, while it scrolls in.
        await measure('coldDown', () => read(down: true));
        // Back over replies that were built before; images may have to be
        // decoded again once the image cache has evicted them.
        await measure('warmUp', () => read(down: false));
        await service.dispose();
      }

      expect(tester.takeException(), isNull);
      final report = <String, Object?>{
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'platform': defaultTargetPlatform.name,
        'debug': kDebugMode,
        'timeline': timelineRun,
        'semantics': binding.semanticsEnabled,
        'pixelRatio': tester.view.devicePixelRatio,
        'physicalSize': [
          tester.view.physicalSize.width,
          tester.view.physicalSize.height,
        ],
        'refreshRate': tester.view.display.refreshRate,
        'updates': updates,
        'served': served,
        'phases': phases,
      };
      debugPrint(
        'TOPIC_MEDIA_SCROLL_PROFILE ${jsonEncode(report)}',
        wrapWidth: 8192,
      );
      binding.reportData!['summary'] = report;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<vm.VmService> _connect() async {
  final info = await developer.Service.getInfo();
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

/// Folds each sample's stack, root first, into Brendan Gregg's collapsed
/// format, which flame graph tools read directly.
///
/// With [frames], keeps only the samples taken while one of them was being
/// built, under a root naming that frame and its build time.
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

/// The package a profiled function belongs to: `flutter`, `dart`, a pub or
/// vendored package by name, or `app` for this application's own library.
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

Map<String, dynamic> _postJson(int n) {
  final user = _users[n % _users.length];
  final reactions = [
    for (var i = 0; i < (n * 7) % 6; i++)
      {
        'id': _reactionIds[(n + i) % _reactionIds.length],
        'type': 'emoji',
        'count': 1 + (n * (i + 3)) % 17,
      },
  ];
  return {
    'id': 9000 + n,
    'post_number': n,
    'post_type': 1,
    'username': user,
    'name': '${user[0].toUpperCase()}${user.substring(1)}',
    'avatar_template': '/user_avatar/$_host/$user/{size}/7_2.png',
    'created_at': DateTime.utc(
      2026,
      9,
      1,
    ).add(Duration(hours: n * 5)).toIso8601String(),
    'cooked': _cooked(n),
    'actions_summary': [
      {'id': Post.likeActionId, 'count': (n * 5) % 23, 'can_act': true},
    ],
    if (reactions.isNotEmpty) ...{
      'reactions': reactions,
      'reaction_users_count': reactions.fold<int>(
        0,
        (sum, r) => sum + (r['count'] as int),
      ),
      'current_user_used_main_reaction': false,
    },
  };
}

String _emoji(String name) =>
    '<img src="$_site/images/emoji/twitter/$name.png?v=12" title=":$name:" '
    'class="emoji" alt=":$name:" loading="lazy" width="20" height="20">';

String _lightbox(
  String name,
  String extension, {
  required int width,
  required int height,
  required String information,
}) {
  final base = '$_site/uploads/default/optimized/1X/${name}_2';
  final shown = '${base}_${width}x$height.$extension';
  return '<div class="lightbox-wrapper"><a class="lightbox" '
      'href="$_site/uploads/default/original/1X/$name.$extension" '
      'data-download-href="$_site/uploads/default/$name" title="$name">'
      '<img src="$shown" alt="$name" data-base62-sha1="$name" '
      'width="$width" height="$height" '
      'srcset="$shown, ${base}_${width * 3 ~/ 2}x${height * 3 ~/ 2}.$extension 1.5x, '
      '${base}_${width * 2}x${height * 2}.$extension 2x" '
      'data-dominant-color="6E7F8C"><div class="meta">'
      '<svg class="fa d-icon d-icon-far-image svg-icon" aria-hidden="true">'
      '<use href="#far-image"></use></svg><span class="filename">$name</span>'
      '<span class="informations">$information</span>'
      '<svg class="fa d-icon d-icon-discourse-expand svg-icon" '
      'aria-hidden="true"><use href="#discourse-expand"></use></svg>'
      '</div></a></div>';
}

String _cooked(int n) => [
  '<p>Reply $n ${_emoji(_reactionIds[n % _reactionIds.length])}: here is '
      'what changed on <strong>my desk</strong> since the last thread, with '
      'a <a href="https://example.com/desk/$n">parts list</a>.</p>',
  if (n % 3 == 0)
    '<p>${_lightbox('photo$n', 'jpeg', width: 690, height: 460, information: '1600×1066 245 KB')}</p>',
  if (n % 4 == 1)
    '<p><img src="$_site/uploads/default/original/1X/loop$n.gif" '
        'alt="loop$n" data-base62-sha1="loop$n" width="360" height="240" '
        'class="animated"></p>',
  for (var p = 0; p < 1 + n % 4; p++)
    '<p>The ${_emoji('eyes')} monitor arm finally holds the '
        '<em>ultrawide</em> without sagging, and the <code>usb-c</code> hub '
        'now powers the lamp. Cable management took an afternoon, but the '
        'result is worth it ${_emoji('tada')}.</p>',
  if (n % 5 == 2)
    '<p>${_lightbox('still$n', 'avif', width: 690, height: 460, information: '1035×690 17 KB')}</p>',
  if (n % 6 == 4)
    '<p>${_lightbox('screen$n', 'png', width: 690, height: 460, information: '1380×920 412 KB')}</p>',
  if (n % 7 == 3)
    '<p><img src="$_site/uploads/default/original/1X/motion$n.avif" '
        'alt="motion$n" data-base62-sha1="motion$n" width="480" height="270" '
        'class="animated"></p>',
  if (n % 8 == 5)
    '<blockquote><p>Which keyboard is that? ${_emoji('open_mouth')}</p>'
        '</blockquote><p>A split board with <strong>tented</strong> halves.</p>',
  if (n % 9 == 6)
    '<pre><code class="lang-yaml">desk:\n  height: 74cm\n  arm: dual\n'
        '  lamp: usb-c\n</code></pre>',
].join();

final class _Media {
  _Media({
    required this.photos,
    required this.screenshot,
    required this.gif,
    required this.avatar,
    required this.emoji,
    required this.stillAvif,
    required this.animatedAvif,
  });

  final List<Uint8List> photos;
  final Uint8List screenshot;
  final Uint8List gif;
  final Uint8List avatar;
  final Uint8List emoji;
  final Uint8List stillAvif;
  final Uint8List animatedAvif;

  static _Media generate() {
    final random = math.Random(7);
    Uint8List photo(int seed) {
      final image = img.Image(width: 1380, height: 920);
      final hue = seed * 47 % 255;
      for (final pixel in image) {
        final x = pixel.x, y = pixel.y;
        final noise = random.nextInt(40);
        pixel
          ..r = (x * 255 ~/ 1380 + hue + noise) % 256
          ..g = (y * 255 ~/ 920 + noise) % 256
          ..b = ((x + y) * 128 ~/ 2300 + 255 - hue) % 256;
      }
      return img.encodeJpg(image, quality: 82);
    }

    final screen = img.Image(width: 1380, height: 920);
    img.fill(screen, color: img.ColorRgb8(246, 246, 248));
    for (var row = 0; row < 18; row++) {
      img.fillRect(
        screen,
        x1: 60,
        y1: 60 + row * 46,
        x2: 60 + 400 + (row * 97) % 800,
        y2: 84 + row * 46,
        color: img.ColorRgb8(30 + row * 9, 90, 200 - row * 6),
      );
    }

    final animation = img.Image(width: 360, height: 240, numChannels: 3);
    for (var frame = 0; frame < 16; frame++) {
      final image = frame == 0
          ? animation
          : img.Image(width: 360, height: 240, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(20 + frame * 10, 40, 120));
      img.fillCircle(
        image,
        x: 30 + frame * 20,
        y: 120,
        radius: 40,
        color: img.ColorRgb8(250, 200, 40),
      );
      image.frameDuration = 60;
      if (frame > 0) animation.addFrame(image);
    }

    final avatar = img.Image(width: 144, height: 144);
    img.fill(avatar, color: img.ColorRgb8(90, 140, 210));
    img.fillCircle(
      avatar,
      x: 72,
      y: 56,
      radius: 30,
      color: img.ColorRgb8(240, 220, 200),
    );
    final emoji = img.Image(width: 72, height: 72, numChannels: 4);
    img.fillCircle(
      emoji,
      x: 36,
      y: 36,
      radius: 34,
      color: img.ColorRgba8(255, 204, 51, 255),
    );

    return _Media(
      photos: [for (var seed = 0; seed < 6; seed++) photo(seed)],
      screenshot: img.encodePng(screen),
      gif: img.encodeGif(animation),
      avatar: img.encodePng(avatar),
      emoji: img.encodePng(emoji),
      stillAvif: base64Decode(stillAvifBase64),
      animatedAvif: base64Decode(animatedAvifBase64),
    );
  }

  (Uint8List?, String?) serve(String path) {
    if (path.startsWith('/user_avatar/')) return (avatar, 'image/png');
    if (path.startsWith('/images/emoji/')) return (emoji, 'image/png');
    final name = path.split('/').last;
    final number = int.tryParse(RegExp(r'\d+').firstMatch(name)?[0] ?? '');
    if (name.startsWith('photo')) {
      return (photos[(number ?? 0) % photos.length], 'image/jpeg');
    }
    if (name.startsWith('screen')) return (screenshot, 'image/png');
    if (name.startsWith('loop')) return (gif, 'image/gif');
    if (name.startsWith('still')) return (stillAvif, 'image/avif');
    if (name.startsWith('motion')) return (animatedAvif, 'image/avif');
    return (null, null);
  }
}
