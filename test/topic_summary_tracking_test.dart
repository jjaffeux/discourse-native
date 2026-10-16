import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _row = Topic(
  id: 7,
  title: 'A new topic',
  slug: 'a-new-topic',
  highestPostNumber: 1,
  seen: false,
);

final class _SummaryApi extends FakeDiscourseApi {
  _SummaryApi({this.visited = false, Topic row = _row})
    : super(
        feeds: {
          '/latest.json': [row],
        },
        trackingState: TopicTrackingState([
          const TrackedTopicState(
            topicId: 7,
            highestPostNumber: 1,
            createdInNewPeriod: true,
          ),
        ]),
      );

  final bool visited;

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async => const DiscourseModelCodec.core().topicSummary({
    'id': id,
    'title': 'A new topic',
    'slug': 'a-new-topic',
    'highest_post_number': 1,
    if (visited) 'last_read_post_number': 1,
  }, siteUrl);
}

Future<ShellController> _loadShell(_SummaryApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  expect(api.topicTrackingRequests, [_siteUrl]);
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final visited in [false, true]) {
    test(
      'summary hydration ${visited ? 'preserves a fresh visit' : 'restores the tracked new-topic marker'}',
      () async {
        final shell = await _loadShell(_SummaryApi(visited: visited));
        expect(shell.store.read<Topic>(_siteUrl, 7)?.showNewTopicDot, isTrue);
        shell.store.remove<Topic>(_siteUrl, 7);
        await shell.topicFeeds.ensureRange(
          instance: shell.currentInstance!,
          destinationId: shell.currentFeedId!,
          firstRow: 0,
          lastRow: 0,
        );
        final restored = shell.store.read<Topic>(_siteUrl, 7);
        expect(restored, isNotNull);
        expect(restored!.showNewTopicDot, !visited);
        expect(restored.lastReadPostNumber, visited ? 1 : null);
      },
    );
  }

  test('complete list responses retain their seen state', () async {
    final shell = await _loadShell(_SummaryApi(row: _row.copyWith(seen: true)));
    expect(shell.store.read<Topic>(_siteUrl, 7)?.showNewTopicDot, isFalse);
  });

  test(
    'a remote dismissal still clears the restored new-topic marker',
    () async {
      final shell = await _loadShell(_SummaryApi());
      shell.store.remove<Topic>(_siteUrl, 7);
      await shell.topicFeeds.ensureRange(
        instance: shell.currentInstance!,
        destinationId: shell.currentFeedId!,
        firstRow: 0,
        lastRow: 0,
      );
      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'message_type': 'dismiss_new',
        'payload': {
          'topic_ids': [7],
        },
      });
      await pumpEventQueue();
      expect(shell.store.read<Topic>(_siteUrl, 7)?.showNewTopicDot, isFalse);
    },
  );
}
