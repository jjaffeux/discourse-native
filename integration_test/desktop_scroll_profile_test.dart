import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/forum_tab_scope.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';
import 'topic_media_fixtures.dart';

const _postCount = 120;
const _topicCount = 300;
const _messageCount = 400;
const _users = ['sam', 'alex', 'jordan', 'riley', 'morgan', 'casey'];
const _reactionIds = ['heart', '+1', 'laughing', 'open_mouth', 'clap', 'tada'];

/// Profiles trackpad scrolling in the maximized desktop shell: the topic
/// list, a topic, a chat channel, and a channel beside a topic in the
/// secondary panel. Every byte, API payload and image alike, is generated
/// in-process; images are served over loopback HTTP so they travel the
/// production fetch and decode path.
///
/// Each route runs three passes: a cold pass into content that has never
/// been built, a warm pass back, both with the UI isolate's CPU sampled at
/// 4 kHz and the Dart, Embedder and GC timeline recorded, then an unprofiled
/// warm pass whose frame timings are the comparable numbers. Results go to
/// `desktop-scroll-profile.json` in the app's temporary directory, whose
/// path the run prints; `DESKTOP_SCROLL_PHASE` lines bracket every pass so a
/// host-side sampler can attribute raster-thread time.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile desktop scrolling', semanticsEnabled: false, (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const opens = MethodChannel('org.discourse.native/notification_opens');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      opens,
      (_) async => null,
    );
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
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final served = <String, int>{};
    server.listen((request) async {
      final (bytes, type) = media.serve(request.uri.path);
      served.update(type ?? 'missing', (n) => n + 1, ifAbsent: () => 1);
      final response = request.response;
      if (bytes == null) {
        response.statusCode = 404;
      } else {
        response.headers.contentType = ContentType.parse(type!);
        response.add(bytes);
      }
      await response.close();
    });
    final host = '127.0.0.1:${server.port}';
    final site = 'http://$host';

    final user = DiscourseUser(
      id: 1,
      username: 'reader',
      name: 'Reader',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
      ),
    );
    final instance = DiscourseInstance(
      url: site,
      title: 'Profile forum',
      apiVersion: 4,
      user: user,
      config: SiteConfig(
        plugins: PluginData.none.withValue(
          chatSettingsDataKey,
          const ChatSettings(),
        ),
      ),
    );
    const channel = ChatChannel(
      id: 9,
      title: 'General',
      kind: ChatChannelKind.category,
      membership: ChatMembership(
        following: true,
        lastReadMessageId: _messageCount,
      ),
      tracking: ChatTracking(),
    );
    final topics = [for (var id = 1; id <= _topicCount; id++) _topic(id, site)];
    final api = FakeDiscourseApi(
      user: user,
      feeds: {'/latest.json': topics},
      topics: {
        for (final id in const [7, 8])
          id: topicPayload(
            id: id,
            title: topics[id - 1].title,
            posts: [
              for (var n = 1; n <= _postCount; n++)
                Post.fromJson(
                  _postJson(id, n, host),
                  site,
                  extensions: pluginRegistry,
                ),
            ],
            postsCount: _postCount,
          ),
      },
      chatChannelsBySite: {
        site: const ChatChannels(public: [channel]),
      },
      chatMessagesByKey: {
        '9': (
          messages: [
            for (var id = 1; id <= _messageCount; id++) _message(id, site),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
    );
    const latest = ContentRoute(
      destination: FeedDestination(key: 'latest', mode: TopicListMode.latest),
      title: 'Topics',
      icon: DIcons.layerGroup,
    );
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([instance]),
        api: api,
        authenticator: FakeAuthenticator()..keys[site] = 'profile-key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore([
          ForumWorkspace(
            siteUrl: site,
            accountIdentity: 'user:reader',
            activeTabId: 'list',
            tabs: [
              ForumTab(
                id: 'list',
                rootDestinationId: latest.id,
                contentStack: const [latest],
              ),
              ForumTab(
                id: 'topic',
                rootDestinationId: latest.id,
                contentStack: [
                  ContentRoute.topic(
                    topicId: 7,
                    slug: topics[6].slug,
                    title: topics[6].title,
                  ),
                ],
              ),
              ForumTab(
                id: 'chat',
                rootDestinationId: 'chat-c-9',
                contentStack: const [
                  ContentRoute(
                    destination: ExtensionDestination('chat-c-9'),
                    title: 'General',
                    icon: DIcons.comment,
                  ),
                ],
              ),
            ],
          ),
        ]),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        pluginManifest: bundledWidgetTestManifest,
      ),
    );
    await tester.pumpAndSettle();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      const window = MethodChannel('org.discourse.native/window');
      await window.invokeMethod<void>('dismissLaunchScreen');
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
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );

    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
    }

    /// The tallest vertical scrollable of [panel]'s content that a pointer
    /// at its centre reaches; retained tabs keep theirs mounted underneath.
    ScrollableState scrollableIn(ForumPanel panel) {
      final candidates = <ScrollableState>[];
      for (final element in find.byType(MainContent).evaluate()) {
        final scope = element.getInheritedWidgetOfExactType<ForumTabScope>();
        if ((scope?.panel ?? ForumPanel.main) != panel) continue;
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

        element.visitChildren(visit);
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
        if (result.path.any((entry) => identical(entry.target, box))) {
          return state;
        }
      }
      fail('no reachable scrollable in $panel');
    }

    // A brisk trackpad pace: 2000 logical pixels a second, one-second
    // swipes released into the framework's own fling.
    const legDistance = 2000.0;
    const legDuration = Duration(seconds: 1);
    var pointerId = 100;
    var updates = 0;
    Future<double> leg(ScrollableState scrollable, double pan) async {
      final box = scrollable.context.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(box.size.center(Offset.zero));
      final before = scrollable.position.pixels;
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
      }
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return scrollable.position.pixels - before;
    }

    /// Swipes with [pan] until the content stops moving or [legs] run out.
    Future<int> swipe(
      ForumPanel panel, {
      required double pan,
      required int legs,
    }) async {
      var run = 0;
      while (run < legs) {
        final moved = await leg(scrollableIn(panel), pan);
        run++;
        if (moved.abs() < legDistance / 4) break;
      }
      await settle();
      return run;
    }

    final service = await _connect();
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    final phases = <String, Object?>{};
    final data = <String, Object?>{};

    Future<void> measure(
      String name,
      Future<int> Function() action, {
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
      debugPrint(
        'DESKTOP_SCROLL_PHASE start $name ${DateTime.now().microsecondsSinceEpoch}',
      );
      final startUs = developer.Timeline.now;
      final legs = await action();
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
          ],
      ];
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
    }

    /// Cold out, warm back, then the unprofiled warm pass out again.
    Future<void> route(
      String name,
      ForumPanel panel, {
      required double forward,
      int legs = 8,
    }) async {
      await settle();
      await measure(
        '$name.cold',
        () => swipe(panel, pan: forward, legs: legs),
        profile: true,
      );
      await measure(
        '$name.warmBack',
        () => swipe(panel, pan: -forward, legs: legs + 4),
        profile: true,
      );
      await measure(
        '$name.warmTiming',
        () => swipe(panel, pan: forward, legs: legs),
        profile: false,
      );
    }

    // Trackpad pans move content with the fingers: a negative pan reads
    // toward the end of a topic or list, a positive one into chat history.
    await route('topicList', ForumPanel.main, forward: -legDistance);
    shell.selectTab('topic');
    await tester.pumpAndSettle();
    await route('topic', ForumPanel.main, forward: -legDistance);
    shell.selectTab('chat');
    await tester.pumpAndSettle();
    await route('channel', ForumPanel.main, forward: legDistance);

    shell.createTab(panel: ForumPanel.secondary);
    shell.pushContent(
      ContentRoute.topic(
        topicId: 8,
        slug: topics[7].slug,
        title: topics[7].title,
      ),
    );
    await tester.pumpAndSettle();
    shell.selectTab('chat');
    await tester.pumpAndSettle();
    expect(shell.selectedTabIn(ForumPanel.secondary), isNotNull);
    await route('splitTopic', ForumPanel.secondary, forward: -legDistance);
    await route('splitChannel', ForumPanel.main, forward: legDistance);
    await service.dispose();

    expect(tester.takeException(), isNull);
    final view = tester.view;
    data['summary'] = {
      'label': const String.fromEnvironment(
        'PROFILE_LABEL',
        defaultValue: 'current',
      ),
      'platform': defaultTargetPlatform.name,
      'pixelRatio': view.devicePixelRatio,
      'physicalSize': [view.physicalSize.width, view.physicalSize.height],
      'refreshRate': view.display.refreshRate,
      'updates': updates,
      'served': served,
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
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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

/// Folds each sample's stack, root first, into collapsed-stack lines. With
/// [frames], keeps only samples taken while one of them was being built,
/// under a root naming that frame and its build time.
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

Topic _topic(int id, String site) => Topic(
  id: id,
  title: id.isEven
      ? 'Topic $id: a longer title about desk setups that wraps onto a second line'
      : 'Topic $id about desk setups',
  slug: 'topic-$id',
  categoryId: 2,
  excerpt: id % 3 == 0
      ? 'An excerpt with enough words to wrap across the row and show how '
            'the list lays out longer previews of the first post.'
      : null,
  tags: const [
    TopicTag(name: 'hardware'),
    TopicTag(name: 'setup'),
  ],
  views: id * 37,
  postsCount: id % 40 + 1,
  likeCount: id % 17,
  lastPosterUsername: _users[id % _users.length],
  bumpedAt: DateTime.utc(2026, 10, 1).subtract(Duration(hours: id)),
  closed: id % 9 == 0,
  pinned: id <= 2,
  unreadPosts: id % 5 == 0 ? id % 7 + 1 : 0,
  newPosts: id % 11 == 0 ? 3 : 0,
  posters: [
    for (var i = 0; i < 1 + id % 5; i++)
      TopicPoster(
        userId: 10 + (id + i) % _users.length,
        username: _users[(id + i) % _users.length],
        avatarUrl:
            '$site/user_avatar/${_users[(id + i) % _users.length]}/96/7_2.png',
      ),
  ],
);

ChatMessage _message(int id, String site) {
  final author = (id ~/ 3) % _users.length;
  return ChatMessage(
    id: id,
    channelId: 9,
    cooked: [
      '<p>Message $id: <strong>rich channel history</strong> with '
          '<a href="https://example.com/$id">a link</a>, ${_emoji(site, 'tada')} '
          'and <code>inline code</code>.</p>',
      if (id % 3 == 0)
        '<p><img src="$site/uploads/default/original/1X/photo$id.jpeg" '
            'width="480" height="320"></p>',
      if (id % 4 == 1)
        '<aside class="onebox" data-onebox-src="https://example.com/$id">'
            '<header><a href="https://example.com/$id">Example publication</a></header>'
            '<article class="onebox-body">'
            '<img class="thumbnail" src="$site/uploads/default/original/1X/thumb$id.jpeg" '
            'width="640" height="427">'
            '<h3><a href="https://example.com/$id">A useful article $id</a></h3>'
            '<p>Preview $id with <strong>formatting</strong> and enough text to '
            'wrap across several lines.</p></article></aside>',
      if (id % 5 == 2)
        '<aside class="quote" data-username="alex">'
            '<div class="title">alex:</div><blockquote>'
            '<p>Quoted reply $id with <em>emphasis</em>.</p></blockquote></aside>',
      if (id % 7 == 0)
        '<pre><code class="lang-ruby">def scroll(channel)\n'
            '  channel.messages.each { |message| render(message) }\nend</code></pre>',
    ].join(),
    reactions: [
      if (id % 2 == 0)
        const ChatReaction(emoji: 'heart', count: 4, reacted: true),
      if (id % 3 == 0) const ChatReaction(emoji: '+1', count: 2),
    ],
    uploads: id % 8 == 0
        ? [
            for (var image = 0; image < 2; image++)
              ChatUpload(
                id: id * 2 + image,
                url:
                    '$site/uploads/default/original/1X/photo${id + image}.jpeg',
                originalFilename: 'photo-$id-$image.jpg',
                kind: ChatUploadKind.image,
                width: 640,
                height: 427,
              ),
          ]
        : const [],
    author: ChatMessageAuthor(
      id: 10 + author,
      username: _users[author],
      avatarUrl: '$site/user_avatar/${_users[author]}/96/7_2.png',
    ),
    createdAt: DateTime(
      2026,
      10,
      1,
    ).add(Duration(hours: (id - 1) ~/ 6, minutes: id % 6 * 7)),
  );
}

Map<String, dynamic> _postJson(int topic, int n, String host) {
  final user = _users[n % _users.length];
  final reactions = [
    for (var i = 0; i < (n * 7) % 5; i++)
      {
        'id': _reactionIds[(n + i) % _reactionIds.length],
        'type': 'emoji',
        'count': 1 + (n * (i + 3)) % 17,
      },
  ];
  return {
    'id': topic * 1000 + n,
    'post_number': n,
    'post_type': 1,
    'username': user,
    'name': '${user[0].toUpperCase()}${user.substring(1)}',
    'avatar_template': '/user_avatar/$user/{size}/7_2.png',
    'created_at': DateTime.utc(
      2026,
      9,
      1,
    ).add(Duration(hours: n * 5)).toIso8601String(),
    'cooked': _cooked(topic, n, 'http://$host'),
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

String _emoji(String site, String name) =>
    '<img src="$site/images/emoji/twitter/$name.png?v=12" title=":$name:" '
    'class="emoji" alt=":$name:" loading="lazy" width="20" height="20">';

String _lightbox(
  String site,
  String name,
  String extension, {
  required int width,
  required int height,
}) {
  final base = '$site/uploads/default/optimized/1X/${name}_2';
  final shown = '${base}_${width}x$height.$extension';
  return '<div class="lightbox-wrapper"><a class="lightbox" '
      'href="$site/uploads/default/original/1X/$name.$extension" '
      'data-download-href="$site/uploads/default/$name" title="$name">'
      '<img src="$shown" alt="$name" data-base62-sha1="$name" '
      'width="$width" height="$height" '
      'srcset="$shown, ${base}_${width * 2}x${height * 2}.$extension 2x" '
      'data-dominant-color="6E7F8C"><div class="meta">'
      '<span class="filename">$name</span>'
      '<span class="informations">1600×1066 245 KB</span>'
      '</div></a></div>';
}

String _cooked(int topic, int n, String site) => [
  '<p>Reply $n ${_emoji(site, _reactionIds[n % _reactionIds.length])}: here '
      'is what changed on <strong>my desk</strong> since the last thread, '
      'with a <a href="https://example.com/desk/$n">parts list</a>.</p>',
  if (n % 3 == 0)
    '<p>${_lightbox(site, 'photo$topic$n', 'jpeg', width: 690, height: 460)}</p>',
  if (n % 4 == 1)
    '<p><img src="$site/uploads/default/original/1X/loop$topic$n.gif" '
        'alt="loop" width="360" height="240" class="animated"></p>',
  for (var p = 0; p < 1 + n % 4; p++)
    '<p>The ${_emoji(site, 'eyes')} monitor arm finally holds the '
        '<em>ultrawide</em> without sagging, and the <code>usb-c</code> hub '
        'now powers the lamp. Cable management took an afternoon, but the '
        'result is worth it.</p>',
  if (n % 5 == 2)
    '<p>${_lightbox(site, 'still$topic$n', 'avif', width: 690, height: 460)}</p>',
  if (n % 6 == 4)
    '<p>${_lightbox(site, 'screen$topic$n', 'png', width: 690, height: 460)}</p>',
  if (n % 8 == 5)
    '<blockquote><p>Which keyboard is that?</p></blockquote>'
        '<p>A split board with <strong>tented</strong> halves.</p>',
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
  });

  final List<Uint8List> photos;
  final Uint8List screenshot;
  final Uint8List gif;
  final Uint8List avatar;
  final Uint8List emoji;
  final Uint8List stillAvif;

  static _Media generate() {
    final random = math.Random(7);
    Uint8List photo(int seed) {
      final image = img.Image(width: 1380, height: 920);
      final hue = seed * 47 % 255;
      for (final pixel in image) {
        final noise = random.nextInt(40);
        pixel
          ..r = (pixel.x * 255 ~/ 1380 + hue + noise) % 256
          ..g = (pixel.y * 255 ~/ 920 + noise) % 256
          ..b = ((pixel.x + pixel.y) * 128 ~/ 2300 + 255 - hue) % 256;
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
    for (var frame = 0; frame < 12; frame++) {
      final image = frame == 0
          ? animation
          : img.Image(width: 360, height: 240, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(20 + frame * 10, 40, 120));
      img.fillCircle(
        image,
        x: 30 + frame * 25,
        y: 120,
        radius: 40,
        color: img.ColorRgb8(250, 200, 40),
      );
      image.frameDuration = 60;
      if (frame > 0) animation.addFrame(image);
    }
    final avatar = img.Image(width: 192, height: 192);
    img.fill(avatar, color: img.ColorRgb8(90, 140, 210));
    img.fillCircle(
      avatar,
      x: 96,
      y: 76,
      radius: 40,
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
    );
  }

  (Uint8List?, String?) serve(String path) {
    if (path.startsWith('/user_avatar/')) return (avatar, 'image/png');
    if (path.startsWith('/images/emoji/')) return (emoji, 'image/png');
    final name = path.split('/').last;
    final number = int.tryParse(RegExp(r'\d+').firstMatch(name)?[0] ?? '');
    if (name.startsWith('photo') || name.startsWith('thumb')) {
      return (photos[(number ?? 0) % photos.length], 'image/jpeg');
    }
    if (name.startsWith('screen')) return (screenshot, 'image/png');
    if (name.startsWith('loop')) return (gif, 'image/gif');
    if (name.startsWith('still')) return (stillAvif, 'image/avif');
    return (null, null);
  }
}
