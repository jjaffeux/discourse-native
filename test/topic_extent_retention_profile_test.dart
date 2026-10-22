import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

const _site = 'https://extent-profile.example';
const _cookedCharacters = 16 * 1024;
const _settledHeight = 480.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('topic extent identity reachability after canonical eviction', () async {
    final info = await developer.Service.getInfo();
    expect(info.serverWebSocketUri, isNotNull);
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    final service = await vmServiceConnectUri(
      info.serverWebSocketUri!.toString(),
    );
    addTearDown(service.dispose);
    final repeats = int.parse(
      Platform.environment['TOPIC_EXTENT_REPEATS'] ?? '5',
    );
    expect(repeats, greaterThan(0));
    final runs = <Map<String, Object?>>[];
    for (var repeat = 0; repeat < repeats; repeat++) {
      for (final records in [20, 1000]) {
        final workload = _buildWorkload(records);
        final beforeClear = await _collectAndCount(service, isolate, workload);
        _expectPinnedExtent(workload);
        _expectMissingTopicInvalid(workload.orphan);
        final orphanTopicBeforeClear = _orphanTopicReachable(workload.orphan);
        if (Platform.environment['TOPIC_EXTENT_EXPECT_COLLECTIBLE'] == '1') {
          expect(beforeClear.reachability.posts, 0);
          expect(beforeClear.reachability.topics, 0);
          expect(beforeClear.reachability.cookedCharacters, 0);
          expect(orphanTopicBeforeClear, isFalse);
        }
        workload.geometry.clear();
        workload.orphan.geometry.clear();
        final afterClear = await _collectAndCount(service, isolate, workload);
        expect(afterClear.reachability.posts, 0);
        expect(afterClear.reachability.topics, 0);
        expect(afterClear.reachability.cookedCharacters, 0);
        expect(_orphanTopicReachable(workload.orphan), isFalse);
        _expectMissingTopicInvalid(workload.orphan);
        expect(
          workload.geometry.minimumHeightFor(
            workload.pinnedPost.id,
            post: workload.pinnedPost,
            snapshot: workload.pinnedSnapshot,
          ),
          isNull,
        );
        runs.add({
          'repeat': repeat,
          'records': records,
          'unpinned_records': records - 1,
          'cooked_characters_per_post': _cookedCharacters,
          'recorded_cooked_characters': records * _cookedCharacters,
          'successful_extent_remembers': workload.remembered,
          'settled_extent_reads': workload.list.extentReads,
          'window_replacements': workload.windowReplacements,
          'verified_canonical_removals': workload.canonicalRemovals,
          'remaining_store_entries': workload.store.length,
          'pinned_post_and_topic_pairs': 1,
          'pinned_minimum_height_after_gc': _settledHeight,
          'before_geometry_clear': _jsonStage(beforeClear),
          'after_geometry_clear': _jsonStage(afterClear),
          'live_post_with_unpinned_topic': {
            'topic_reachable_before_clear': orphanTopicBeforeClear,
            'topic_reachable_after_clear': false,
            'missing_topic_minimum_height': null,
          },
          'errors': 0,
        });
        workload.list.dispose();
        workload.orphan.list.dispose();
      }
    }
    final revision = Process.runSync('git', ['rev-parse', 'HEAD']);
    expect(revision.exitCode, 0);
    final result = {
      'metric': 'weak probe reachability after forced full GC',
      'scope': 'production TopicReaderGeometry with simulated settled extents',
      'limits': [
        'Isolated model reachability, not rendered scrolling.',
        'Cooked character counts are not retained heap bytes.',
        'VM class bytes are shallow isolate-wide totals, not retained sizes.',
        'No device timing, allocation rate, or GC latency measurement.',
        'The final live Post and TopicDetail are excluded from probe counts.',
      ],
      'source_revision': (revision.stdout as String).trim(),
      'geometry_source': File(
        'lib/src/shell/topic_reader_geometry.dart',
      ).readAsStringSync(),
      'runtime': Platform.version,
      'repeats_per_workload': repeats,
      'runs': runs,
    };
    File(
      Platform.environment['TOPIC_EXTENT_PROFILE']!,
    ).writeAsStringSync('${jsonEncode(result)}\n');
  }, skip: Platform.environment['TOPIC_EXTENT_PROFILE'] == null);
}

typedef _Reachability = ({int posts, int topics, int cookedCharacters});
typedef _CollectionStage = ({
  _Reachability reachability,
  Map<String, Object?> shallowClassTotals,
});
typedef _OrphanTopicExtent = ({
  TopicReaderGeometry geometry,
  _SettledListController list,
  Post post,
  WeakReference<TopicDetail> topic,
});

final class _Probe {
  _Probe(Post post, TopicDetail topic)
    : post = WeakReference(post),
      topic = WeakReference(topic);

  final WeakReference<Post> post;
  final WeakReference<TopicDetail> topic;
}

final class _Workload {
  _Workload({
    required this.geometry,
    required this.list,
    required this.store,
    required this.probes,
    required this.pinnedPost,
    required this.pinnedSnapshot,
    required this.remembered,
    required this.windowReplacements,
    required this.canonicalRemovals,
    required this.orphan,
  });

  final TopicReaderGeometry geometry;
  final _SettledListController list;
  final Store store;
  final List<_Probe> probes;
  final Post pinnedPost;
  final TopicViewportSnapshot pinnedSnapshot;
  final int remembered;
  final int windowReplacements;
  final int canonicalRemovals;
  final _OrphanTopicExtent orphan;
}

final class _SettledListController extends ListController {
  bool attached = true;
  int extentReads = 0;

  @override
  bool get isAttached => attached;

  @override
  int get numberOfItems => 1;

  @override
  (double, bool) extentForIndex(int index) {
    expect(index, 0);
    extentReads++;
    return (_settledHeight, false);
  }
}

@pragma('vm:never-inline')
_Workload _buildWorkload(int records) {
  final list = _SettledListController();
  final geometry = TopicReaderGeometry(
    scrollController: () => null,
    listController: () => list,
    topInset: () => 0,
    startsAtBeginning: () => false,
    postFrame: (_) => fail('The replace action must not enqueue frame work.'),
  )..postWidth = 390;
  final store = Store(maxEntries: 4);
  final probes = <_Probe>[];
  Post? pinnedPost;
  TopicViewportSnapshot? pinnedSnapshot;
  var remembered = 0;
  var windowReplacements = 0;
  var canonicalRemovals = 0;
  for (var index = 1; index <= records; index++) {
    final prefix =
        '<p data-post="$index"><strong>Distinct post $index</strong>';
    const suffix = '</p>';
    final cooked =
        prefix +
        List.filled(
          _cookedCharacters - prefix.length - suffix.length,
          'x',
        ).join() +
        suffix;
    final post = store.put(
      _site,
      Post(id: index, postNumber: index, username: 'reader', cooked: cooked),
    );
    final topic = store.put(
      _site,
      TopicDetail(id: 1, title: 'Topic revision $index', stream: [index]),
    );
    expect(post.cooked.length, _cookedCharacters);
    expect(store.read<Post>(_site, index), same(post));
    expect(store.read<TopicDetail>(_site, 1), same(topic));
    final snapshot = _snapshot(topic, index);
    _replaceWindow(geometry, [index]);
    windowReplacements++;
    expect(
      geometry.rememberPostExtent(index, post: post, snapshot: snapshot),
      isTrue,
      reason: 'Every replacement window must retain a settled extent.',
    );
    remembered++;
    expect(
      geometry.minimumHeightFor(index, post: post, snapshot: snapshot),
      _settledHeight,
    );
    store.remove<Post>(_site, index);
    store.remove<TopicDetail>(_site, 1);
    expect(store.containsRecord<Post>(_site, index), isFalse);
    expect(store.containsRecord<TopicDetail>(_site, 1), isFalse);
    canonicalRemovals += 2;
    if (index == records) {
      pinnedPost = post;
      pinnedSnapshot = snapshot;
    } else {
      probes.add(_Probe(post, topic));
    }
  }
  _replaceWindow(geometry, const []);
  list.attached = false;
  expect(store.length, 0);
  expect(geometry.window.postIds, isEmpty);
  expect(probes, hasLength(records - 1));
  return _Workload(
    geometry: geometry,
    list: list,
    store: store,
    probes: probes,
    pinnedPost: pinnedPost!,
    pinnedSnapshot: pinnedSnapshot!,
    remembered: remembered,
    windowReplacements: windowReplacements,
    canonicalRemovals: canonicalRemovals,
    orphan: _buildOrphanTopicExtent(records + 1),
  );
}

@pragma('vm:never-inline')
_OrphanTopicExtent _buildOrphanTopicExtent(int postId) {
  final list = _SettledListController();
  final geometry = TopicReaderGeometry(
    scrollController: () => null,
    listController: () => list,
    topInset: () => 0,
    startsAtBeginning: () => false,
    postFrame: (_) => fail('The replace action must not enqueue frame work.'),
  )..postWidth = 390;
  final post = Post(
    id: postId,
    postNumber: postId,
    username: 'live-reader',
    cooked: '<p>The post stays live after its topic is released.</p>',
  );
  final topic = TopicDetail(id: 1, title: 'Unpinned topic', stream: [postId]);
  _replaceWindow(geometry, [postId]);
  expect(
    geometry.rememberPostExtent(
      postId,
      post: post,
      snapshot: _snapshot(topic, postId),
    ),
    isTrue,
  );
  _replaceWindow(geometry, const []);
  list.attached = false;
  return (
    geometry: geometry,
    list: list,
    post: post,
    topic: WeakReference(topic),
  );
}

void _replaceWindow(TopicReaderGeometry geometry, List<int> postIds) {
  geometry.applyWindowChange(
    TopicViewportWindowChange(
      extentAction: TopicViewportExtentAction.replace,
      previousPostIds: geometry.window.postIds,
      currentPostIds: postIds,
      previousHasHeader: false,
      hasHeader: false,
      prepended: false,
      appendOnly: false,
    ),
  );
}

TopicViewportSnapshot _snapshot(TopicDetail? topic, int postId) =>
    TopicViewportSnapshot(
      topicId: topic?.id ?? 1,
      topic: topic,
      siteUrl: _site,
      postIds: [postId],
      streamIds: topic?.stream ?? [postId],
      loading: false,
      loadingMore: false,
      loadingEarlier: false,
      hasMore: true,
      hasEarlier: true,
      initialPostIndex: null,
      recommendations: null,
      summary: false,
      summaryLoading: false,
      readTimeWordCount: 200,
      showTimeGapDays: 7,
      navigationRevision: 1,
    );

Future<_CollectionStage> _collectAndCount(
  vm.VmService service,
  String isolate,
  _Workload workload,
) async {
  final profile = await service.getAllocationProfile(isolate, gc: true);
  final shallowClassTotals = <String, Object?>{
    for (final member in profile.members!)
      if (member.classRef?.name == 'Post' ||
          member.classRef?.name == 'TopicDetail')
        member.classRef!.name!: {
          'instances_current': member.instancesCurrent,
          'shallow_bytes_current': member.bytesCurrent,
        },
  };
  expect(shallowClassTotals.keys, containsAll(['Post', 'TopicDetail']));
  return (
    reachability: _countReachability(workload.probes),
    shallowClassTotals: shallowClassTotals,
  );
}

@pragma('vm:never-inline')
_Reachability _countReachability(List<_Probe> probes) {
  var posts = 0;
  var topics = 0;
  var cookedCharacters = 0;
  for (final probe in probes) {
    final post = probe.post.target;
    if (post != null) {
      posts++;
      cookedCharacters += post.cooked.length;
    }
    if (probe.topic.target != null) topics++;
  }
  return (posts: posts, topics: topics, cookedCharacters: cookedCharacters);
}

@pragma('vm:never-inline')
void _expectPinnedExtent(_Workload workload) {
  expect(
    workload.geometry.minimumHeightFor(
      workload.pinnedPost.id,
      post: workload.pinnedPost,
      snapshot: workload.pinnedSnapshot,
    ),
    _settledHeight,
    reason: 'Live identities must keep their settled height through GC.',
  );
  expect(
    workload.geometry.minimumHeightFor(
      workload.pinnedPost.id,
      post: workload.pinnedPost,
      snapshot: _snapshot(null, workload.pinnedPost.id),
    ),
    isNull,
    reason: 'A missing topic must never validate a retained extent.',
  );
}

Map<String, Object?> _jsonStage(_CollectionStage stage) => {
  'reachable_posts': stage.reachability.posts,
  'reachable_topic_details': stage.reachability.topics,
  'reachable_cooked_characters': stage.reachability.cookedCharacters,
  'isolate_wide_shallow_class_totals': stage.shallowClassTotals,
};

@pragma('vm:never-inline')
bool _orphanTopicReachable(_OrphanTopicExtent orphan) =>
    orphan.topic.target != null;

@pragma('vm:never-inline')
void _expectMissingTopicInvalid(_OrphanTopicExtent orphan) {
  expect(
    orphan.geometry.minimumHeightFor(
      orphan.post.id,
      post: orphan.post,
      snapshot: _snapshot(null, orphan.post.id),
    ),
    isNull,
    reason: 'A collected topic must not validate against a missing topic.',
  );
}
