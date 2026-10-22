import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';

class _CountingStore extends Store {
  _CountingStore({super.maxEntries});
  int postReads = 0;
  int coldOpenReads = 0;
  int coldOpenUs = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) {
      postReads++;
    }
    return super.read<T>(siteUrl, id);
  }
}

Future<ShellController> _open(
  WidgetTester tester,
  _CountingStore store, {
  required int size,
  bool mega = true,
  FakeDiscourseApi? api,
}) async {
  final shell = ShellController(
    store: store,
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: api ?? FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  store.put(
    _site,
    TopicDetail(
      id: 1,
      title: 'Preview',
      stream: [for (var i = 1; i <= size; i++) i],
      postsCount: size,
      isMegaTopic: mega,
      hasSummary: true,
      highestPostNumber: size * 2 + 1,
    ),
  );
  for (var i = 1; i <= size; i++) {
    if (!mega && i == size - 1) {
      continue;
    }
    store.put(
      _site,
      Post(id: i, postNumber: i * 2, username: 'user$i', cooked: ''),
    );
  }
  shell.pushContent(
    ContentRoute.topic(topicId: 1, slug: 'preview', title: 'Preview'),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: TopicProgressPopover(
            controller: shell,
            position: 2,
            total: mega ? size * 2 + 1 : size,
          ),
        ),
      ),
    ),
  );
  store.postReads = 0;
  final watch = Stopwatch()..start();
  await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
  await tester.pumpAndSettle();
  watch.stop();
  store.coldOpenReads = store.postReads;
  store.coldOpenUs = watch.elapsedMicroseconds;
  return shell;
}

void main() {
  testWidgets(
    'repeated mega previews read only their selected canonical posts',
    (tester) async {
      final store = _CountingStore();
      await _open(tester, store, size: 200);
      final lookup = tester
          .widget<TopicProgressPanel>(find.byType(TopicProgressPanel))
          .postAt!;
      expect(lookup(400)?.id, 200);
      expect(lookup(399), isNull);
      store.postReads = 0;
      for (var i = 0; i < 50; i++) {
        expect(lookup(400)?.id, 200);
        expect(lookup(399), isNull);
      }
      expect(store.postReads, 50);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'summary previews keep ordinal positions when opened from a mega topic',
    (tester) async {
      final store = _CountingStore();
      final posts = [
        const Post(
          id: 11,
          postNumber: 100,
          username: 'summary-first',
          cooked: '',
        ),
        const Post(
          id: 12,
          postNumber: 800,
          username: 'summary-second',
          cooked: '',
        ),
      ];
      final api = FakeDiscourseApi(
        summaryTopics: {
          1: (
            detail: const TopicDetail(
              id: 1,
              title: 'Summary',
              stream: [11, 12],
            ),
            posts: posts,
          ),
        },
      );
      final shell = await _open(tester, store, size: 3, api: api);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await shell.toggleTopicSummary();
      expect(shell.currentTopicSummary, isTrue);
      await tester.tap(find.byKey(const ValueKey('topic-progress-button')));
      await tester.pumpAndSettle();
      final lookup = tester
          .widget<TopicProgressPanel>(find.byType(TopicProgressPanel))
          .postAt!;
      expect(lookup(1)?.username, 'summary-first');
      expect(lookup(2)?.username, 'summary-second');
      expect(lookup(100), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'mega previews follow canonical edits, structure and stream replacements',
    (tester) async {
      final store = _CountingStore();
      final shell = await _open(tester, store, size: 3);
      final lookup = tester
          .widget<TopicProgressPanel>(find.byType(TopicProgressPanel))
          .postAt!;
      expect(lookup(6)?.username, 'user3');
      expect(lookup(5), isNull);
      final token = store.structureGenerationOf<Post>(_site);
      store.put(
        _site,
        const Post(id: 3, postNumber: 6, username: 'edited', cooked: 'fresh'),
      );
      expect(store.structureGenerationOf<Post>(_site), same(token));
      expect(lookup(6)?.username, 'edited');
      store.put(
        _site,
        const Post(id: 3, postNumber: 5, username: 'renumbered', cooked: ''),
      );
      expect(lookup(6), isNull);
      expect(lookup(5)?.username, 'renumbered');
      store.remove<Post>(_site, 3);
      expect(lookup(5), isNull);
      store.put(
        _site,
        const Post(id: 3, postNumber: 5, username: 'reloaded', cooked: ''),
      );
      expect(lookup(5)?.username, 'reloaded');
      store.put(
        _site,
        const Post(id: 4, postNumber: 7, username: 'new-window', cooked: ''),
      );
      final detail = shell.currentTopic!;
      store.update<TopicDetail>(_site, 1, (_) => detail.copyWith(stream: [4]));
      expect(lookup(5), isNull);
      expect(lookup(7)?.username, 'new-window');
      store.update<TopicDetail>(
        _site,
        1,
        (held) => held.copyWith(stream: [2, 4]),
      );
      store.put(
        _site,
        const Post(id: 4, postNumber: 4, username: 'duplicate', cooked: ''),
      );
      expect(lookup(4)?.id, 2);
      final beforeReorder = store.structureGenerationOf<Post>(_site);
      store.update<TopicDetail>(
        _site,
        1,
        (held) => held.copyWith(stream: [4, 2]),
      );
      expect(store.structureGenerationOf<Post>(_site), same(beforeReorder));
      expect(lookup(4)?.id, 4);
      expect(lookup(1), isNull);
      expect(lookup(100000), isNull);
      final retainedDetail = shell.currentTopic!;
      store.forget(_site);
      store.put(_site, retainedDetail);
      store.put(
        _site,
        const Post(id: 4, postNumber: 6, username: 'new-account', cooked: ''),
      );
      expect(lookup(4), isNull);
      expect(lookup(6)?.username, 'new-account');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'mega preview reads refresh selected LRU entries without pinning posts',
    (tester) async {
      final store = _CountingStore(maxEntries: 4);
      await _open(tester, store, size: 3);
      final detailRef = store.ref<TopicDetail>(_site, 1);
      void keepTopic() {}
      detailRef.addListener(keepTopic);
      addTearDown(() => detailRef.removeListener(keepTopic));
      final lookup = tester
          .widget<TopicProgressPanel>(find.byType(TopicProgressPanel))
          .postAt!;
      expect(lookup(5), isNull);
      expect(lookup(2)?.id, 1);
      store.put(
        _site,
        const Post(id: 4, postNumber: 8, username: 'extra', cooked: ''),
      );
      expect(store.containsRecord<Post>(_site, 2), isFalse);
      expect(store.containsRecord<Post>(_site, 1), isTrue);
      expect(lookup(4), isNull);
      store.remove<Post>(_site, 1);
      expect(lookup(2), isNull);
      store.put(
        _site,
        const Post(id: 1, postNumber: 2, username: 'back', cooked: ''),
      );
      expect(lookup(2)?.username, 'back');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mega in [false, true]) {
    for (final size in [20, 200, 1000]) {
      testWidgets('preview workload mega=$mega size=$size', (tester) async {
        final store = _CountingStore();
        await _open(tester, store, size: size, mega: mega);
        final lookup = tester
            .widget<TopicProgressPanel>(find.byType(TopicProgressPanel))
            .postAt!;
        final loaded = mega ? size * 2 : size;
        final missing = mega ? size * 2 + 1 : size - 1;
        final records = <Map<String, Object>>[];
        for (var run = 0; run < 5; run++) {
          store.postReads = 0;
          var found = 0;
          final watch = Stopwatch()..start();
          for (var i = 0; i < 400; i++) {
            final post = lookup(i.isEven ? loaded : missing);
            if (post != null) {
              found++;
            }
          }
          watch.stop();
          expect(found, 200);
          records.add({
            'run': run,
            'endpointUs': watch.elapsedMicroseconds,
            'postReads': store.postReads,
          });
        }
        store.postReads = 0;
        final watch = Stopwatch()..start();
        for (var i = 0; i < 12; i++) {
          tester
              .widget<TopicPositionSlider>(find.byType(TopicPositionSlider))
              .onChanged!(i.isEven ? loaded : missing);
          await tester.pump();
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('topic-progress-author')),
                )
                .data
                ?.trim(),
            i.isEven ? 'user$size' : 'Post $missing',
          );
        }
        watch.stop();
        final report = {
          'mega': mega,
          'size': size,
          'endpoint': records,
          'widget12Us': watch.elapsedMicroseconds,
          'widgetPostReads': store.postReads,
          'coldOpenReads': store.coldOpenReads,
          'coldOpenUs': store.coldOpenUs,
        };
        stdout.writeln('PREVIEW_METRIC ${jsonEncode(report)}');
        final output = Platform.environment['PREVIEW_METRIC_PATH'];
        if (output != null) {
          File(
            output,
          ).writeAsStringSync('${jsonEncode(report)}\n', mode: FileMode.append);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
