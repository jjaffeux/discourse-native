// flutter run --profile -d macos -t tool/forum_switch_profile_main.dart
// Mounts the production app with local data and isolated preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_cpu_profile.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/site_appearance_fixtures.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('forum_switch_profile.');
  final preferences = await SharedPreferences.getInstance();
  await preferences.clear();
  final label = Platform.environment['FORUM_SWITCH_LABEL'] ?? 'capture';
  final passes = int.parse(Platform.environment['FORUM_SWITCH_PASSES'] ?? '8');
  if (passes < 1 || passes > 30) throw ArgumentError('Use 1–30 passes');
  const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
  final forums = [
    instance('first.invalid', title: 'First forum').copyWith(
      user: user,
      appearance: siteAppearance(
        accent: const Color(0xFF3366CC),
        alternateAccent: const Color(0xFF6688DD),
      ),
    ),
    instance('second.invalid', title: 'Second forum').copyWith(
      user: user,
      appearance: siteAppearance(
        accent: const Color(0xFF884488),
        alternateAccent: const Color(0xFFBB77BB),
      ),
    ),
  ];
  final topics = [
    for (var id = 1; id <= 60; id++)
      Topic(
        id: id,
        title: 'Discussion $id about switching forums',
        slug: 'discussion-$id',
        categoryId: id % 12 + 1,
        tags: const [TopicTag(name: 'performance')],
      ),
  ];
  final api = _SwitchApi(
    user: user,
    siteAppearances: {for (final forum in forums) forum.url: forum.appearance!},
    feeds: {'/latest.json': topics},
    feedCategoriesByPath: {
      '/latest.json': [
        for (var id = 1; id <= 12; id++)
          TopicCategory(id: id, name: 'Category $id', color: '3366CC'),
      ],
    },
    topics: {
      for (final topic in topics.take(2))
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
                    '<blockquote><p>Restore the same reading position.</p></blockquote>'
                    '<p>Measure the switch with the topic reader visible.</p>'
                    '<pre><code>final result = await load();</code></pre>',
              ),
          ],
        ),
    },
  );
  final authenticator = FakeAuthenticator();
  for (final forum in forums) {
    authenticator.keys[forum.url] = 'fixture';
  }
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    DiscourseApp(
      store: FakeInstanceStore(forums),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  ShellController? controller;
  void findShell(Element element) {
    if (element.widget is AdaptiveShell) {
      controller = ShellScope.read(element);
      return;
    }
    element.visitChildren(findShell);
  }

  binding.rootElement!.visitChildren(findShell);
  final shell = controller!;
  if (!shell.loaded) throw StateError('Shell failed to load');
  if (Platform.environment['FORUM_SWITCH_MANUAL_START'] == 'true') {
    final signal = File('${Directory.systemTemp.path}/forum-switch-start');
    if (await signal.exists()) await signal.delete();
    stdout.writeln('FORUM_SWITCH ready; create ${signal.path} to start');
    while (!await signal.exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await signal.delete();
  } else {
    await Future<void>.delayed(const Duration(seconds: 12));
  }
  final semantics = binding.ensureSemantics();
  await binding.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final frames = <FrameTiming>[];
  final runs = <Map<String, Object?>>[];
  final view = binding.platformDispatcher.views.first;
  final budgetUs = 1000000 / view.display.refreshRate;
  binding.addTimingsCallback(frames.addAll);
  Future<void> capture(String name, int index) async {
    frames.clear();
    final events = <Map<String, Object?>>[];
    var notifications = 0;
    void notified() => notifications++;
    shell.addListener(notified);
    final requests = api.feedPaths.length;
    final start = developer.Timeline.now;
    SurfaceOpeningTrace.observer = (name, timestamp) =>
        events.add({'name': name, 'elapsedUs': timestamp - start});
    shell.selectInstance(index);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final end = developer.Timeline.now;
    SurfaceOpeningTrace.observer = null;
    shell.removeListener(notified);
    // Timings arrive in batches; select by frame timestamps, not delivery time.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final selected = frames.where((frame) {
      final timestamp = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      return timestamp >= start && timestamp <= end;
    }).toList();
    if (selected.isEmpty || shell.instanceIndex != index) {
      throw StateError('No rendered switch for $name');
    }
    Map<String, Object?> summarize(List<int> values) {
      values.sort();
      return {
        'maxUs': values.last,
        'p95Us': values[((values.length - 1) * .95).ceil()],
        'overBudget': values.where((value) => value > budgetUs).length,
      };
    }

    final run = <String, Object?>{
      'name': name,
      'notifications': notifications,
      'feedRequests': api.feedPaths.length - requests,
      'frames': selected.length,
      'build': summarize([
        for (final frame in selected) frame.buildDuration.inMicroseconds,
      ]),
      'raster': summarize([
        for (final frame in selected) frame.rasterDuration.inMicroseconds,
      ]),
      'events': events,
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
    if (Platform.environment['FORUM_SWITCH_CPU'] == 'true') {
      run['cpu'] = await collectTopicCpuProfile(
        startUs: start,
        endUs: end,
        slowFrames: [
          for (final frame in selected)
            if (frame.buildDuration.inMicroseconds > budgetUs)
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
      'FORUM_SWITCH ${jsonEncode(Map.of(run)
        ..remove('events')
        ..remove('timings')
        ..remove('cpu'))}',
    );
  }

  await capture('cold-list', 1);
  for (var pass = 0; pass < passes; pass++) {
    await capture('warm-list-$pass', pass % 2);
  }
  for (var index = 0; index < forums.length; index++) {
    shell.selectInstance(index);
    shell.openTopicFromList(topics[index]);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (shell.currentTopic == null) throw StateError('Topic failed to load');
  }
  for (var pass = 0; pass < passes; pass++) {
    await capture('warm-topic-$pass', pass % 2);
    if (shell.currentTopic?.id != topics[pass % 2].id) {
      throw StateError('Wrong topic restored');
    }
  }
  binding.removeTimingsCallback(frames.addAll);
  semantics.dispose();
  final report = {
    'label': label,
    'semanticsEnabledDuringCapture': true,
    'refreshRate': view.display.refreshRate,
    'physicalSize': [view.physicalSize.width, view.physicalSize.height],
    'devicePixelRatio': view.devicePixelRatio,
    'runs': runs,
  };
  final file = File('${Directory.systemTemp.path}/forum-switch-$label.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('FORUM_SWITCH complete ${file.path}');
}

class _SwitchApi extends FakeDiscourseApi {
  _SwitchApi({
    required super.user,
    required super.siteAppearances,
    required super.feeds,
    required super.feedCategoriesByPath,
    required super.topics,
  });

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
