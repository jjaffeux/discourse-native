// flutter run --profile -d macos -t tool/surface_opening_profile_main.dart
// Synthetic data and isolated preferences; mounts the production shell.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/data/topic_presentation_store.dart';
import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_cpu_profile.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final sheet = Platform.environment['OPENING_SHEET'] == 'true';
  final label = Platform.environment['OPENING_LABEL'] ?? 'capture';
  SharedPreferences.setPrefix('surface_opening_profile.');
  final preferences = await SharedPreferences.getInstance();
  await preferences.clear();
  await preferences.setString(
    TopicPresentationStore.storageKey,
    sheet ? 'sheet' : 'docked',
  );
  final placement = ComposerPlacement.values.firstWhere(
    (value) => value.name == Platform.environment['OPENING_PLACEMENT'],
    orElse: () => ComposerPlacement.right,
  );
  await const ComposerLayoutStore().write(
    ComposerLayoutPreference(placement: placement),
  );
  const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
  final topics = [
    for (var id = 1; id <= 30; id++)
      Topic(
        id: id,
        title: 'Opening a rich discussion $id',
        slug: 'discussion-$id',
      ),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('opening.invalid').copyWith(user: user),
    ]),
    api: _OpeningApi(
      user: user,
      feeds: {'/latest.json': topics},
      topics: {
        for (final topic in topics)
          topic.id: topicPayload(
            id: topic.id,
            title: topic.title,
            canCreatePost: true,
            posts: [
              for (var number = 1; number <= 20; number++)
                Post(
                  id: topic.id * 100 + number,
                  postNumber: number,
                  username: 'reader',
                  createdAt: DateTime.utc(2026, 9, 1),
                  cooked:
                      '<p>Reply $number with <strong>formatted text</strong> '
                      'and an <a href="https://example.com/">ordinary link</a>.</p>'
                      '<blockquote><p>How does this behave on the first frame?</p></blockquote>'
                      '<p>Measure opening, content layout, and editor focus together. '
                      'Keep the same reader and draft when changing presentation.</p>'
                      '<pre><code>final result = await load();</code></pre>',
                ),
            ],
          ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://opening.invalid'] = 'fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.loadFeed('latest');
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: const bool.fromEnvironment('OPENING_DARK')
            ? AppTheme.dark
            : AppTheme.light,
        builder: (context, child) => DToaster(child: child!),
        home: const Scaffold(body: AdaptiveShell()),
      ),
    ),
  );
  if (Platform.environment['OPENING_MANUAL_START'] == 'true') {
    final signal = File('${Directory.systemTemp.path}/surface-opening-start');
    if (await signal.exists()) await signal.delete();
    stdout.writeln('OPENING_PROFILE ready; create ${signal.path} to start');
    while (!await signal.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await signal.delete();
  } else {
    await Future<void>.delayed(const Duration(seconds: 15));
  }
  final semantics = binding.ensureSemantics();
  await binding.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final frames = <FrameTiming>[];
  final events = <Map<String, Object?>>[];
  final runs = <Map<String, Object?>>[];
  binding.addTimingsCallback(frames.addAll);
  Future<void> capture(String name, VoidCallback action) async {
    frames.clear();
    events.clear();
    final start = developer.Timeline.now;
    SurfaceOpeningTrace.observer = (name, timestamp) =>
        events.add({'name': name, 'elapsedUs': timestamp - start});
    action();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final end = developer.Timeline.now;
    SurfaceOpeningTrace.observer = null;
    // Engine timings are batched. Filter by vsync timestamps, not callback time.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final selected = frames.where((frame) {
      final timestamp = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      return timestamp >= start && timestamp <= end;
    }).toList();
    if (selected.isEmpty) throw StateError('No rendered frames for $name');
    final rate = binding.platformDispatcher.views.first.display.refreshRate;
    final budget = 1000000 / rate;
    Map<String, Object?> summarize(List<int> values) {
      values.sort();
      return {
        'p95Us': values.isEmpty
            ? null
            : values[((values.length - 1) * .95).ceil()],
        'maxUs': values.isEmpty ? null : values.last,
        'overBudget': values.where((value) => value > budget).length,
      };
    }

    final run = <String, Object?>{
      'name': name,
      'frames': selected.length,
      'build': summarize(
        selected.map((frame) => frame.buildDuration.inMicroseconds).toList(),
      ),
      'raster': summarize(
        selected.map((frame) => frame.rasterDuration.inMicroseconds).toList(),
      ),
      'events': List.of(events),
      'timings': [
        for (final frame in selected)
          {
            'elapsedUs':
                frame.timestampInMicroseconds(FramePhase.vsyncStart) - start,
            'buildUs': frame.buildDuration.inMicroseconds,
            'rasterUs': frame.rasterDuration.inMicroseconds,
          },
      ],
    };
    if (Platform.environment['OPENING_CPU'] == 'true') {
      run['cpu'] = await collectTopicCpuProfile(
        startUs: start,
        endUs: end,
        slowFrames: [
          for (final frame in selected)
            if (frame.buildDuration.inMicroseconds > budget)
              (
                frameNumber: frame.frameNumber,
                startUs: frame.timestampInMicroseconds(FramePhase.buildStart),
                endUs: frame.timestampInMicroseconds(FramePhase.buildFinish),
              ),
        ],
      );
    }
    runs.add(run);
    stdout.writeln(
      'OPENING_PROFILE ${jsonEncode({...run}
        ..remove('timings')
        ..remove('events')
        ..remove('cpu'))}',
    );
  }

  final passes =
      int.tryParse(Platform.environment['OPENING_PASSES'] ?? '') ?? 5;
  if (passes < 1 || passes > topics.length) {
    throw ArgumentError.value(passes, 'OPENING_PASSES', 'Use 1–30 passes');
  }
  for (var pass = 0; pass < passes; pass++) {
    await capture('topic-$pass', () => shell.openTopicFromList(topics[pass]));
    if (shell.currentTopic == null) throw StateError('Topic failed to load');
    await capture('composer-$pass', shell.openReply);
    if (shell.visibleComposer?.focus.hasFocus != true) {
      throw StateError('Visible composer did not receive focus');
    }
    shell.closeComposer();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    shell.closeTopic();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await capture('cached-topic', () => shell.openTopicFromList(topics.first));
  for (var pass = 0; pass < 2; pass++) {
    await capture(
      'new-topic-$pass',
      () => unawaited(shell.openNewTopicFromSidebar()),
    );
    if (shell.visibleComposer?.target.createsTopic != true ||
        shell.visibleComposer?.focus.hasFocus != true) {
      throw StateError('New-topic composer failed to open and focus');
    }
    shell.closeComposer();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  binding.removeTimingsCallback(frames.addAll);
  semantics.dispose();
  final view = binding.platformDispatcher.views.first;
  final report = {
    'label': label,
    'sheet': sheet,
    'placement': placement.name,
    'semanticsEnabledDuringCapture': true,
    'refreshRate': view.display.refreshRate,
    'physicalSize': [view.physicalSize.width, view.physicalSize.height],
    'devicePixelRatio': view.devicePixelRatio,
    'runs': runs,
  };
  final file = File(
    '${Directory.systemTemp.path}/surface-opening-$label-${sheet ? 'sheet' : 'docked'}.json',
  );
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('OPENING_PROFILE complete ${file.path}');
}

class _OpeningApi extends FakeDiscourseApi {
  _OpeningApi({
    required super.user,
    required super.feeds,
    required super.topics,
  });

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    String? apiKey,
    bool summary = false,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 70));
    return super.topic(
      siteUrl: siteUrl,
      abortTrigger: abortTrigger,
      slug: slug,
      id: id,
      postNumber: postNumber,
      apiKey: apiKey,
      summary: summary,
      clientId: clientId,
    );
  }
}
