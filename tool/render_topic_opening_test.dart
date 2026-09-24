// Offscreen review of a topic opening from its list, frame by frame, with
// local macOS fonts. Writes numbered PNGs for every frame whose pixels change.
// TOPIC_OPENING_OUT=/tmp/topic-opening flutter test tool/render_topic_opening_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const _siteHost = 'opening-review.invalid';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // This executable is an offscreen test fixture.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });
  setUpAll(() async {
    await (FontLoader('Open Sans')
          ..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))
          ..addFont(rootBundle.load('assets/fonts/OpenSans-Italic.ttf')))
        .load();
    for (final family in [
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
  });

  final output =
      Platform.environment['TOPIC_OPENING_OUT'] ?? '/tmp/topic-opening';

  for (final scenario in _Scenario.values) {
    for (final theme in _Theme.values) {
      testWidgets('${scenario.name} ${theme.name}', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final directory = Directory('$output/${scenario.name}-${theme.name}');
        if (directory.existsSync()) directory.deleteSync(recursive: true);
        directory.createSync(recursive: true);

        final gate = Completer<void>();
        final fixture = _fixture(scenario, gate);
        final shell = fixture.shell;
        addTearDown(() async {
          shell.dispose();
          await shell.plugins.close();
        });
        await shell.load();
        for (final row in fixture.rows) {
          shell.store.put(shell.currentInstance!.url, row);
        }
        await shell.loadFeed('latest');
        final base = switch (theme) {
          _Theme.dark => AppTheme.forBrightness(
            Brightness.dark,
            fontFamily: 'Open Sans',
          ),
          _Theme.light => AppTheme.forBrightness(
            Brightness.light,
            fontFamily: 'Open Sans',
          ),
          // Discourse's default dark scheme, as the site's CSS resolves it.
          _Theme.forumDark => AppTheme.fromPalette(
            ResolvedSitePalette.fromJson(const {
              'brightness': 'dark',
              'primary': 0xFFDDDDDD,
              'secondary': 0xFF222222,
              'tertiary': 0xFF099DD7,
              'quaternary': 0xFFC14924,
              'headerBackground': 0xFF111111,
              'headerPrimary': 0xFFDDDDDD,
              'highlight': 0xFFA87137,
              'danger': 0xFFE45735,
              'success': 0xFF1CA551,
              'love': 0xFFFA6C8D,
              'primaryVeryLow': 0xFF282828,
              'primaryLow': 0xFF313131,
              'primaryLowMid': 0xFF7A7A7A,
              'primaryMedium': 0xFF909090,
              'primaryHigh': 0xFFA6A6A6,
              'primaryVeryHigh': 0xFFC7C7C7,
              'metadataColor': 0xFFA6A6A6,
              'contentBorderColor': 0xFF313131,
              'hover': 0xFF313131,
              'secondaryVeryHigh': 0xFF3A3A3A,
            }),
            fontFamily: 'Open Sans',
          ),
        };
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: base,
              home: Scaffold(
                body: TopicPresentationPreferences(
                  child: MainContent(
                    layout: ShellLayout.expanded,
                    registry: shell.plugins.registry,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final recorder = _FrameRecorder(tester, directory);
        await recorder.capture('list');
        shell.openTopicFromList(fixture.rows.first);
        for (var i = 0; i < 4; i++) {
          await recorder.step('loading');
        }
        await recorder.step('loading-500ms', const Duration(milliseconds: 500));
        await recorder.step(
          'loading-1000ms',
          const Duration(milliseconds: 500),
        );
        gate.complete();
        for (var i = 0; i < 12; i++) {
          await recorder.step('response');
        }
        for (var i = 0; i < 20; i++) {
          await recorder.step(
            'after-response',
            const Duration(milliseconds: 16),
          );
        }
        await tester.pumpAndSettle();
        await recorder.capture('settled');
        expect(tester.takeException(), isNull);
        recorder.writeIndex();
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }
}

enum _Scenario { singlePost, unreadLater }

enum _Theme { forumDark, dark, light }

({ShellController shell, List<Topic> rows}) _fixture(
  _Scenario scenario,
  Completer<void> gate,
) {
  const user = DiscourseUser(id: 7, username: 'saj', unifiedNewEnabled: true);
  final site = instance(
    _siteHost,
  ).copyWith(user: user, config: const SiteConfig(taggingEnabled: true));
  final siteUrl = site.url;
  const registry = PluginRegistry([AssignPlugin()]);
  final postCount = scenario == _Scenario.singlePost ? 1 : 12;
  final lastRead = scenario == _Scenario.singlePost ? null : 5;
  final bumped = DateTime.now().subtract(const Duration(days: 13));
  final rows = [
    Topic(
      id: 1,
      title: 'Replace the ISC DHCP server on Debian trixie metal gold servers',
      slug: 'replace-isc-dhcp',
      categoryId: 1,
      postsCount: postCount,
      views: 9,
      likeCount: 0,
      bumpedAt: bumped,
      lastPosterUsername: 'saj',
      lastReadPostNumber: lastRead,
      highestPostNumber: postCount,
      unreadPosts: lastRead == null ? 0 : postCount - lastRead,
      tags: const [TopicTag(name: 'maintenance')],
      excerpt: 'ISC DHCP is no longer practically available as of trixie.',
    ),
    for (var id = 2; id <= 14; id++)
      Topic(
        id: id,
        title: 'Operations topic number $id with a reasonably long title',
        slug: 'operations-$id',
        categoryId: 1,
        postsCount: 3,
        views: 40,
        bumpedAt: bumped,
        lastPosterUsername: 'sam',
        lastReadPostNumber: 3,
        highestPostNumber: 3,
        tags: const [TopicTag(name: 'maintenance')],
      ),
  ];
  const opening =
      '<aside class="quote no-group" data-username="saj" data-post="1" data-topic="9"><div class="title">ISC DHCP is dead, Jim</div><blockquote><p><a href="https://www.isc.org/blogs/isc-dhcp-eol/">ISC DHCP Server has reached EOL - ISC</a><br>RIP.</p></blockquote></aside>'
      '<blockquote><p>The ISC DHCP <strong>server</strong> is used on the metal gold servers. These machines are currently running Debian bullseye.</p></blockquote>'
      '<p>ISC DHCP is no longer practically available as of Debian trixie.</p>'
      '<blockquote><p>isc-dhcp has been marked unsupported in trixie in debian-security-support</p></blockquote>'
      '<p><a href="https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1035972#75">https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1035972#75</a></p>'
      '<p>Find and deploy some replacement for trixie. Simpler would be better.</p>'
      '<p>Existing bullseye machines are to be left as-is on ISC DHCP. An alternative will only be deployed in trixie. The old ISC configuration may be removed upon the future operational withdrawal of bullseye; it does not matter when that happens.</p>';
  final posts = [
    for (var number = 1; number <= postCount; number++)
      Post(
        id: 100 + number,
        postNumber: number,
        username: number.isOdd ? 'saj' : 'maya',
        name: number.isOdd ? 'Saj Goonatilleke' : 'Maya',
        userId: number.isOdd ? 7 : 8,
        canEdit: number.isOdd,
        createdAt: bumped.add(Duration(hours: number)),
        cooked: number == 1
            ? opening
            : '<p>Reply $number. ${List.filled(12, 'We tried kea and dnsmasq on a staging box first.').join(' ')}</p>',
      ),
  ];
  final api = FakeDiscourseApi(
    topicGate: gate,
    user: user,
    feeds: {'/latest.json': rows},
    categoryList: const [
      TopicCategory(
        id: 1,
        name: 'sysadmin',
        slug: 'sysadmin',
        color: 'E45735',
        permission: 1,
      ),
      TopicCategory(
        id: 2,
        parentCategoryId: 1,
        name: 'networking',
        slug: 'networking',
        color: 'E45735',
        permission: 1,
      ),
    ],
    topics: {
      1: (
        detail: TopicDetail(
          id: 1,
          title: rows.first.title,
          categoryId: 1,
          canEdit: true,
          canEditTags: true,
          canCloseTopic: true,
          canCreatePost: true,
          postsCount: postCount,
          views: 9,
          wordCount: 120 * postCount,
          stream: [for (final post in posts) post.id],
          tags: const [TopicTag(name: 'maintenance')],
          participants: [
            const TopicParticipant(
              username: 'saj',
              name: 'Saj Goonatilleke',
              postCount: 6,
            ),
            if (postCount > 1)
              const TopicParticipant(username: 'maya', name: 'Maya'),
          ],
          plugins: registry.readTopic(const {'can_assign': true}, siteUrl),
        ),
        posts: posts,
      ),
    },
  );
  final shell = ShellController(
    plugins: PluginInstaller.install(const PluginManifest([assignModule])),
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator()..keys[siteUrl] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  return (shell: shell, rows: rows);
}

/// Writes a PNG for every frame whose pixels change, and a log of each pump's
/// wall time and component elements mounted and rebuilt (debug-mode costs,
/// comparable between two builds of the same fixture, not absolute).
class _FrameRecorder {
  _FrameRecorder(this.tester, this.directory) {
    // builtOnce is only tracked while rebuilds are printed; track it here.
    debugOnRebuildDirtyWidget = (element, _) {
      if (_built.add(element)) {
        _mounted++;
      } else {
        _rebuilt++;
        final type = element.widget.runtimeType.toString();
        _rebuiltTypes[type] = (_rebuiltTypes[type] ?? 0) + 1;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
  }

  final WidgetTester tester;
  final Directory directory;
  Uint8List? _previous;
  var _index = 0;
  var _pumps = 0;
  final _built = Set<Element>.identity();
  var _mounted = 0;
  var _rebuilt = 0;
  final _rebuiltTypes = <String, int>{};
  final _log = <String>[];

  Future<void> step(String label, [Duration? duration]) async {
    _mounted = 0;
    _rebuilt = 0;
    _rebuiltTypes.clear();
    final watch = Stopwatch()..start();
    await tester.pump(duration);
    watch.stop();
    await capture(
      label,
      cost:
          'mounted ${_mounted.toString().padLeft(5)} '
          'rebuilt ${_rebuilt.toString().padLeft(5)} '
          '${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1).padLeft(7)} ms',
    );
    if (_rebuiltTypes.isNotEmpty) {
      final top = _rebuiltTypes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _log.add(
        '    rebuilt: ${top.take(12).map((e) => '${e.key} ${e.value}').join(', ')}',
      );
    }
  }

  Future<void> capture(String label, {String cost = ''}) async {
    _pumps++;
    final pump = 'p${_pumps.toString().padLeft(2, '0')}';
    await tester.runAsync(() async {
      final layer =
          tester.binding.renderViews.single.debugLayer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize);
      final raw = await image.toByteData();
      final bytes = raw!.buffer.asUint8List();
      if (_previous != null && _sameBytes(_previous!, bytes)) {
        image.dispose();
        _log.add('$pump ${label.padRight(15)} $cost  (unchanged)');
        return;
      }
      _previous = Uint8List.fromList(bytes);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final name = '${(_index++).toString().padLeft(2, '0')}-$pump-$label.png';
      File(
        '${directory.path}/$name',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      _log.add('$pump ${label.padRight(15)} $cost  $name');
      image.dispose();
    });
  }

  void writeIndex() => File(
    '${directory.path}/index.txt',
  ).writeAsStringSync('${_log.join('\n')}\n');

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
