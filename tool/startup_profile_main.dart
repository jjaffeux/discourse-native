// Entrypoint of the startup profile. See tool/profile_startup.py.
//
// It is the production bootstrap with two additions the app cannot do for
// itself: a seeded profile of forums, served from a second isolate so the
// scenario needs no network and costs the UI isolate nothing, and a report of
// every startup point measured from the exec of the process.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show FramePhase;

import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/foundation/startup_timeline.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _forumCount = 6;
const _firstPort = 47610;
const _topicCount = 30;
const _categoryCount = 30;
const _responseLatency = Duration(milliseconds: 60);
const _settle = Duration(seconds: 4);
const _giveUp = Duration(seconds: 30);

final int _execMicros = _processStartMicros();
int _sinceExec() => DateTime.now().microsecondsSinceEpoch - _execMicros;

String _site(int index) => 'http://127.0.0.1:${_firstPort + index}';

// Dart's print does not reach devicectl's console on iOS, so the launch is also
// written to a file the harness copies off the device. It is written once, at
// exit, because writing per line would add file IO to what is being timed.
final List<String> _reported = [];
File _logFile(String name) => File('${Directory.systemTemp.path}/$name');

void _report(String kind, String name, int micros) {
  final line = 'STARTUP_PROFILE $kind $micros $name';
  // ignore: avoid_print
  print(line);
  _reported.add(line);
}

Never _exit() {
  _logFile(
    'startup_profile.log',
  ).writeAsStringSync('${_reported.join('\n')}\n');
  exit(0);
}

Future<void> main() async {
  // devicectl's environment does not reach the app on iOS, so a phone is asked
  // to seed by a file the harness copies into the app's container.
  final seedRequest = _logFile('startup_seed');
  final seedRequested = seedRequest.existsSync();
  if (seedRequested) seedRequest.deleteSync();
  if (seedRequested || Platform.environment['DISCOURSE_STARTUP_SEED'] == '1') {
    WidgetsFlutterBinding.ensureInitialized();
    await (await SharedPreferences.getInstance()).clear();
    await InstanceStore().save([
      for (var index = 0; index < _forumCount; index++)
        DiscourseInstance(
          url: _site(index),
          title: 'Profile forum $index',
          apiVersion: 4,
        ),
    ]);
    // A phone with no saved page opens the Start page, which requests no feed.
    final latest = ContentRoute.topicList(TopicListMode.latest);
    final location = ForumTabLocation(
      rootDestinationId: latest.id,
      contentStack: [latest],
    );
    await ForumTabStore().save([
      ForumWorkspace(
        siteUrl: _site(0),
        accountIdentity: 'anonymous',
        activeTabId: 'restored',
        tabs: [
          ForumTab(
            id: 'restored',
            rootDestinationId: latest.id,
            contentStack: [latest],
          ),
        ],
        mobile: MobileNavigationState(
          place: 'topics',
          visits: [location],
          index: 0,
        ),
      ),
    ], selectedSiteUrl: _site(0));
    // NSUserDefaults hands a write to its daemon asynchronously, and exiting
    // straight away can lose it.
    await Future<void>.delayed(const Duration(seconds: 1));
    final seeded = await InstanceStore().load();
    if (seeded.length != _forumCount) {
      throw StateError('seeded ${seeded.length} forums');
    }
    _report('seeded', 'forums', _sinceExec());
    _exit();
  }

  await Isolate.spawn(_serve, null);

  final marks = <String, int>{};
  startupMarkObserver = (point) {
    final at = _sinceExec();
    marks.putIfAbsent(point, () => at);
    _report('mark', point, at);
    if (point == 'feed shown') {
      _report('cpu', 'feed shown', _cpuMicros());
      _report('rss', 'feed shown', ProcessInfo.currentRss);
    }
  };
  markStartup('entry');

  var finishing = false;
  void finish(String why) {
    if (finishing) return;
    finishing = true;
    Timer(_settle, () {
      _report('cpu', 'done', _cpuMicros());
      _report('rss', 'done', ProcessInfo.currentRss);
      _report('done', why, _sinceExec());
      _exit();
    });
  }

  AppBootstrap.production(
    manifest: bundledPluginManifest,
    openComponentStyleguide: showComponentStyleguide,
  ).start();

  var frames = 0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      final finished =
          timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime) -
          _execMicros;
      final built =
          finished -
          (timing.timestampInMicroseconds(FramePhase.rasterFinish) -
              timing.timestampInMicroseconds(FramePhase.buildStart));
      _report('frame', '${frames++} built=$built', finished);
      if (marks['feed shown'] case final shown? when built >= shown) {
        finish('feed');
      }
    }
  });
  Timer(_giveUp, () => finish('timeout'));
}

/// When the kernel created this process, in microseconds since the epoch.
int _processStartMicros() {
  final library = DynamicLibrary.process();
  final malloc = library
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  final sysctl = library
      .lookupFunction<
        Int32 Function(
          Pointer<Int32>,
          Uint32,
          Pointer<Uint8>,
          Pointer<IntPtr>,
          Pointer<Void>,
          IntPtr,
        ),
        int Function(
          Pointer<Int32>,
          int,
          Pointer<Uint8>,
          Pointer<IntPtr>,
          Pointer<Void>,
          int,
        )
      >('sysctl');
  const kinfoProcSize = 648;
  final mib = malloc(16).cast<Int32>();
  final size = malloc(8).cast<IntPtr>();
  final info = malloc(kinfoProcSize);
  mib[0] = 1; // CTL_KERN
  mib[1] = 14; // KERN_PROC
  mib[2] = 1; // KERN_PROC_PID
  mib[3] = pid;
  size.value = kinfoProcSize;
  if (sysctl(mib, 4, info, size, nullptr, 0) != 0) {
    throw StateError('sysctl(KERN_PROC_PID) failed');
  }
  // extern_proc begins with a union holding p_starttime, a timeval.
  final seconds = info.cast<Int64>().value;
  final micros = (info + 8).cast<Int32>().value;
  return seconds * Duration.microsecondsPerSecond + micros;
}

/// CPU time this process has consumed on all threads.
int _cpuMicros() => DynamicLibrary.process()
    .lookupFunction<IntPtr Function(), int Function()>('clock')();

Future<void> _serve(Object? _) async {
  _logFile('startup_profile_requests.log').writeAsStringSync('');
  for (var index = 0; index < _forumCount; index++) {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _firstPort + index,
    );
    server.listen((request) => unawaited(_answer(request, index)));
  }
}

Future<void> _answer(HttpRequest request, int forum) async {
  final line =
      'STARTUP_PROFILE request ${_sinceExec()} ${request.method} $forum ${request.uri}';
  // ignore: avoid_print
  print(line);
  _logFile(
    'startup_profile_requests.log',
  ).writeAsStringSync('$line\n', mode: FileMode.append);
  if (request.uri.path.startsWith('/message-bus/')) {
    // A live connection long-polls for as long as nothing happens.
    await Future<void>.delayed(const Duration(seconds: 25));
    request.response.write('[]');
    await request.response.close();
    return;
  }
  await Future<void>.delayed(_responseLatency);
  final response = request.response;
  final body = switch (request.uri.path) {
    '/latest.json' => _latest(forum),
    '/site.json' => _sitePayload(),
    '/site/basic-info.json' => {
      'title': 'Profile forum $forum',
      'description': 'A forum for profiling startup.',
      'login_required': false,
    },
    '/site/settings.json' => const {'default_homepage': 'latest'},
    final path when path.endsWith('.json') => const <String, Object?>{},
    _ => null,
  };
  response.headers.contentType = ContentType.json;
  if (body == null) response.statusCode = HttpStatus.notFound;
  response.write(
    jsonEncode(
      body ??
          {
            'errors': const ['not served'],
          },
    ),
  );
  await response.close();
}

Map<String, Object?> _sitePayload() => {
  'categories': [
    for (var id = 1; id <= _categoryCount; id++)
      {
        'id': id,
        'name': 'Category $id',
        'slug': 'category-$id',
        'color': '0088cc',
        'text_color': 'ffffff',
        'topic_count': 120,
        'post_count': 840,
        'position': id,
        'description_text': 'Conversations about subject number $id.',
        'can_edit': false,
        'permission': 1,
      },
  ],
  'post_action_types': const [],
  'topic_flag_types': const [],
  'notification_types': const {'mentioned': 1, 'replied': 2},
  'trust_levels': const {'newuser': 0, 'basic': 1},
  'filters': const ['latest', 'top'],
  'periods': const ['all', 'yearly'],
  'top_menu_items': const ['latest', 'top'],
  'anonymous_top_menu_items': const ['latest', 'top'],
  'can_create_tag': false,
  'groups': const [],
  'top_tags': const ['performance', 'startup', 'mobile'],
};

Map<String, Object?> _latest(int forum) {
  final users = [
    for (var id = 1; id <= 12; id++)
      {
        'id': id,
        'username': 'member$id',
        'name': 'Member $id',
        'avatar_template': '/letter_avatar_proxy/v4/letter/m/8e7dd6/{size}.png',
        'trust_level': 2,
      },
  ];
  return {
    'users': users,
    'primary_groups': const [],
    'topic_list': {
      'can_create_topic': false,
      'per_page': _topicCount,
      'more_topics_url': '/latest?page=1',
      'topics': [
        for (var id = 1; id <= _topicCount; id++)
          {
            'id': 1000 * (forum + 1) + id,
            'title': 'A topic with a realistically long title, number $id',
            'fancy_title':
                'A topic with a realistically long title, number $id',
            'slug': 'a-topic-with-a-realistically-long-title-$id',
            'posts_count': 12 + id,
            'reply_count': 8 + id,
            'highest_post_number': 12 + id,
            'created_at': '2026-11-01T10:00:00.000Z',
            'last_posted_at': '2026-11-07T10:00:00.000Z',
            'bumped_at': '2026-11-07T10:00:00.000Z',
            'bumped': true,
            'unseen': false,
            'pinned': false,
            'visible': true,
            'closed': false,
            'archived': false,
            'views': 420 + id,
            'like_count': 7 + id,
            'category_id': (id % _categoryCount) + 1,
            'tags': const ['performance', 'startup'],
            'archetype': 'regular',
            'last_poster_username': 'member${(id % 12) + 1}',
            'excerpt':
                'A paragraph that gives the reader a sense of what the topic '
                'discusses, long enough to wrap onto a second line.',
            'posters': [
              for (var poster = 0; poster < 4; poster++)
                {
                  'extras': poster == 0 ? 'latest' : null,
                  'description': 'Frequent Poster',
                  'user_id': ((id + poster) % 12) + 1,
                },
            ],
          },
      ],
    },
  };
}
