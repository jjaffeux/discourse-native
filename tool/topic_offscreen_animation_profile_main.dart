import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final lifecycleGuard = _LifecycleGuard();
  binding.addObserver(lifecycleGuard);
  final semantics = binding.ensureSemantics();
  final site = instance('meta.example');
  final bytes = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
    'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
  );
  final lifecycle = SiteLifecycle();
  final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
  final siteImages = SiteImageRepository(
    credentials: authenticator,
    lifecycle: lifecycle,
    client: MockClient(
      (_) async => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/gif'},
      ),
    ),
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    lifecycle: lifecycle,
    siteImages: siteImages,
    trackers: FakeSiteTracker.reset(),
  );

  await controller.load();
  await siteImages.load(siteUrl: site.url, url: '${site.url}/uploads/test.gif');
  controller.store
    ..put(
      site.url,
      TopicDetail(
        id: 1,
        title: 'One',
        stream: [for (var id = 1; id <= 35; id++) id],
        postsCount: 35,
      ),
    )
    ..putAll(site.url, [
      const Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked:
            '<p>Animated post</p><img src="/uploads/test.gif" width="100" height="100">',
      ),
      for (var id = 2; id <= 35; id++)
        Post(
          id: id,
          postNumber: id,
          username: 'sam',
          cooked: List.filled(5, '<p>Post $id</p>').join(),
        ),
    ]);
  controller.pushContent(
    ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
  );

  runApp(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: TopicView()),
      ),
    ),
  );
  const label = String.fromEnvironment(
    'TOPIC_GIF_LABEL',
    defaultValue: 'candidate',
  );
  final report = <String, Object?>{
    'label': label,
    'phases': <Object?>[],
    'valid': false,
  };
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> frames) => timings.addAll(frames);
  binding.addTimingsCallback(collect);
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (binding.lifecycleState != AppLifecycleState.resumed) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('startup never resumed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    lifecycleGuard.armed = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    lifecycleGuard.check();
    final elements = <Element>[];
    void visit(Element element) {
      elements.add(element);
      element.visitChildren(visit);
    }

    binding.rootElement!.visitChildren(visit);
    List<Element> descendants(Element root) {
      final result = <Element>[];
      void collect(Element element) {
        result.add(element);
        element.visitChildren(collect);
      }

      root.visitChildren(collect);
      return result;
    }

    final siteImage = elements.singleWhere(
      (element) =>
          element.widget is SiteImage &&
          Uri.parse((element.widget as SiteImage).url).path ==
              '/uploads/test.gif',
    );
    final image = descendants(
      siteImage,
    ).singleWhere((element) => element.widget is Image);
    final raw = descendants(image).singleWhere(
      (element) =>
          element.widget is RawImage &&
          (element.widget as RawImage).image != null,
    );
    final provider = (image.widget as Image).image;
    if (provider is! MemoryImage &&
        !(provider is ResizeImage && provider.imageProvider is MemoryImage)) {
      throw StateError('Unexpected cooked GIF provider: $provider');
    }
    report['imageUrl'] = (siteImage.widget as SiteImage).url;
    report['provider'] = provider.runtimeType.toString();
    report['dpr'] = binding.platformDispatcher.views.first.devicePixelRatio;
    report['physicalViewport'] = binding
        .platformDispatcher
        .views
        .first
        .physicalSize
        .toString();
    final listElement = elements.firstWhere(
      (element) => element.widget is SuperSliverList,
    );
    final list = (listElement.widget as SuperSliverList).listController!;
    final scroll = Scrollable.of(listElement).widget.controller!;
    final stream = (image.widget as Image).image
        .resolve(createLocalImageConfiguration(image))
        .completer!;
    if (stream is! MultiFrameImageStreamCompleter) {
      throw StateError('not a real animated image');
    }
    RenderObject? row = image.renderObject;
    while (row != null && row.parentData is! SliverMultiBoxAdaptorParentData) {
      row = row.parent;
    }
    Map<String, Object?> state() {
      final range = list.visibleRange;
      final viewport =
          scroll.position.context.storageContext.findRenderObject()!
              as RenderBox;
      final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
      final box = image.mounted ? image.renderObject! as RenderBox : null;
      final rect = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      return {
        'imageRect': rect?.toString(),
        'viewportRect': viewportRect.toString(),
        'imageIntersectsViewport': rect?.overlaps(viewportRect) ?? false,
        'mounted': image.mounted,
        'keptAlive': image.mounted
            ? (row!.parentData! as SliverMultiBoxAdaptorParentData).keptAlive
            : null,
        'visibleRange': range == null ? null : [range.$1, range.$2],
        'firstPostVisible': range != null && range.$1 == 0,
        // Existing-stream observation; adding a listener changes the workload.
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        'hasListeners': stream.hasListeners,
        'schedulerHasFrame': binding.hasScheduledFrame,
        'lifecycle': binding.lifecycleState?.name,
      };
    }

    Future<void> phase(
      String name, {
      required bool mounted,
      required bool keptAlive,
      required bool visible,
    }) async {
      // Drain transition frames and the decoder's one in-flight frame before
      // measuring idle work. Observation never adds an image stream listener.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      lifecycleGuard.check();
      final before = state();
      void checkGeometry(Map<String, Object?> observation) {
        if (observation['mounted'] != mounted ||
            observation['firstPostVisible'] != visible ||
            (mounted && observation['keptAlive'] != keptAlive) ||
            (visible && observation['imageIntersectsViewport'] != true)) {
          throw StateError('$name wrong geometry: $observation');
        }
      }

      checkGeometry(before);
      var frameChanges = 0;
      var sample = mounted ? (raw.widget as RawImage).image!.clone() : null;
      final start = developer.Timeline.now;
      final samples = <Object?>[];
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        lifecycleGuard.check();
        if (mounted) {
          final current = (raw.widget as RawImage).image!;
          if (!sample!.isCloneOf(current)) frameChanges++;
          sample.dispose();
          sample = current.clone();
        }
        final observation = state();
        checkGeometry(observation);
        samples.add(observation);
      }
      final end = developer.Timeline.now;
      sample?.dispose();
      // Engine timing delivery is batched. Only timestamps inside the actual
      // phase count; frames delivered during this drain cannot contaminate it.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      lifecycleGuard.check();
      final after = state();
      checkGeometry(after);
      final frames = timings.where((frame) {
        final vsyncStart = frame.timestampInMicroseconds(FramePhase.vsyncStart);
        return vsyncStart >= start && vsyncStart < end;
      }).toList();
      final result = <String, Object?>{
        'name': name,
        'startUs': start,
        'endUs': end,
        'before': before,
        'after': after,
        'samples': samples,
        'imageFrameChanges': frameChanges,
        'idleFrames': frames.length,
        'uiTotalUs': frames.fold<int>(
          0,
          (sum, frame) => sum + frame.buildDuration.inMicroseconds,
        ),
        'rasterTotalUs': frames.fold<int>(
          0,
          (sum, frame) => sum + frame.rasterDuration.inMicroseconds,
        ),
        'frames': [
          for (final frame in frames)
            {
              'vsyncStartUs': frame.timestampInMicroseconds(
                FramePhase.vsyncStart,
              ),
              'uiUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
            },
        ],
      };
      (report['phases']! as List<Object?>).add(result);
      stdout.writeln(
        'TOPIC_GIF $name frames=${frames.length} imageChanges=$frameChanges before=$before',
      );
    }

    await phase('visible', mounted: true, keptAlive: false, visible: true);
    list.jumpToItem(index: 16, scrollController: scroll, alignment: 0);
    await phase('offscreen', mounted: true, keptAlive: true, visible: false);
    list.jumpToItem(index: 0, scrollController: scroll, alignment: 0);
    await phase('reentry', mounted: true, keptAlive: false, visible: true);
    for (var index = 8; index <= 64; index += 8) {
      list.jumpToItem(index: index, scrollController: scroll, alignment: 0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      lifecycleGuard.check();
    }
    await phase('evicted', mounted: false, keptAlive: false, visible: false);
    report['valid'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    report['lifecycleTransitions'] = lifecycleGuard.transitions;
    final file = File('${Directory.systemTemp.path}/topic-gif-$label.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('TOPIC_GIF_RESULT ${file.path} valid=${report['valid']}');
    binding.removeTimingsCallback(collect);
    binding.removeObserver(lifecycleGuard);
    semantics.dispose();
  }
}

class _LifecycleGuard with WidgetsBindingObserver {
  bool armed = false;
  bool invalidated = false;
  final transitions = <Object?>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    transitions.add({'timeUs': developer.Timeline.now, 'state': state.name});
    if (armed && state != AppLifecycleState.resumed) invalidated = true;
  }

  void check() {
    if (invalidated ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw StateError('Background or inactive native sample rejected');
    }
  }
}
