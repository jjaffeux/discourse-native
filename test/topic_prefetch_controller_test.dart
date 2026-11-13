import 'dart:async';

import 'package:discourse_native/src/shell/topic_prefetch_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final session = Object();
  TopicPrefetchKey key(int id, {int? postNumber}) => (
    siteUrl: 'https://example.com',
    session: session,
    topicId: id,
    postNumber: postNumber,
  );
  PrefetchedTopic result(int id) =>
      PrefetchedTopic(topicPayload(id: id), 0, 0, 0, 0);

  testWidgets(
    'a failed prefetch completion capability settles adoption and releases the next candidate',
    (tester) async {
      var failClock = false;
      final controller = TopicPrefetchController(
        clock: () {
          if (failClock) throw StateError('clock unavailable');
          return DateTime.utc(2026);
        },
      );
      addTearDown(controller.clear);
      final first = Completer<PrefetchedTopic?>();
      controller.hover(
        key(1),
        isCurrent: () => true,
        intent: TopicPrefetchIntent.trajectory,
        load: (_) => first.future,
      );
      final adopted = controller.take(key(1))!;
      var settled = false;
      PrefetchedTopic? delivered;
      unawaited(
        adopted.then((value) {
          settled = true;
          delivered = value;
        }),
      );
      var nextLoads = 0;
      controller.hover(
        key(2),
        isCurrent: () => true,
        intent: TopicPrefetchIntent.trajectory,
        load: (_) async {
          nextLoads++;
          return result(2);
        },
      );
      failClock = true;
      first.complete(result(1));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(settled, isTrue);
      expect(delivered, isNull);
      expect(nextLoads, 1);
    },
  );

  testWidgets(
    'an adopted prefetch no longer depends on its former list interest',
    (tester) async {
      final controller = TopicPrefetchController();
      addTearDown(controller.clear);
      var interested = true;
      final response = Completer<PrefetchedTopic?>();
      final release = controller.hover(
        key(1),
        isCurrent: () => interested,
        intent: TopicPrefetchIntent.trajectory,
        load: (_) => response.future,
      );
      final adopted = controller.take(key(1))!;
      interested = false;
      release();
      response.complete(result(1));
      expect((await adopted)?.payload.detail.id, 1);
    },
  );

  testWidgets(
    'failing speculative predicates are silent misses and leave healthy work admissible',
    (tester) async {
      final controller = TopicPrefetchController();
      addTearDown(controller.clear);
      var failedLoads = 0;
      expect(
        () => controller.hover(
          key(2),
          isCurrent: () => throw StateError('retired source'),
          intent: TopicPrefetchIntent.trajectory,
          load: (_) async {
            failedLoads++;
            return result(2);
          },
        ),
        returnsNormally,
      );
      expect(failedLoads, 0);
      controller.hover(
        key(3),
        isCurrent: () => true,
        intent: TopicPrefetchIntent.trajectory,
        load: (_) async => result(3),
      );
      final healthy = controller.take(key(3));
      expect((await healthy)?.payload.detail.id, 3);
    },
  );

  testWidgets(
    'confirmed trajectory skips dwell and stale releases cannot cancel a handoff',
    (tester) async {
      final controller = TopicPrefetchController();
      addTearDown(controller.clear);
      final response = Completer<PrefetchedTopic?>();
      late TopicPrefetchCancellation cancellation;
      var loads = 0;
      Future<PrefetchedTopic?> load(TopicPrefetchCancellation token) {
        loads++;
        cancellation = token;
        return response.future;
      }

      final releasePrediction = controller.hover(
        key(1),
        load: load,
        isCurrent: () => true,
        intent: TopicPrefetchIntent.trajectory,
      );
      await tester.pump();
      expect(loads, 1);
      final releaseHover = controller.hover(
        key(1),
        load: load,
        isCurrent: () => true,
      );
      releasePrediction();
      final adopted = controller.take(key(1));
      releaseHover();
      expect(cancellation.isCancelled, isFalse);
      response.complete(result(1));
      expect((await adopted)?.payload.detail.id, 1);
      expect(loads, 1);
    },
  );

  testWidgets('brief crossings send nothing; the latest row starts at 40 ms', (
    tester,
  ) async {
    final controller = TopicPrefetchController();
    addTearDown(controller.clear);
    final sent = <int>[];
    void hover(int id) => controller.hover(
      key(id),
      isCurrent: () => true,
      load: (_) async {
        sent.add(id);
        return result(id);
      },
    );
    hover(1);
    await tester.pump(const Duration(milliseconds: 39));
    expect(sent, isEmpty);
    hover(2);
    await tester.pump(const Duration(milliseconds: 39));
    expect(sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent, [2]);
    expect((await controller.take(key(2)))?.payload.detail.id, 2);
  });

  testWidgets(
    'cancelled work settles before only the latest pending row starts',
    (tester) async {
      final controller = TopicPrefetchController();
      addTearDown(controller.clear);
      final first = Completer<PrefetchedTopic?>();
      late TopicPrefetchCancellation cancellation;
      final sent = <int>[];
      controller.hover(
        key(1),
        isCurrent: () => true,
        load: (token) {
          cancellation = token;
          sent.add(1);
          return first.future;
        },
      );
      await tester.pump(TopicPrefetchController.hoverDelay);
      controller.hover(
        key(2),
        isCurrent: () => true,
        load: (_) async {
          sent.add(2);
          return result(2);
        },
      );
      await tester.pump(TopicPrefetchController.hoverDelay);
      expect(cancellation.isCancelled, isTrue);
      expect(sent, [1]);
      controller.hover(
        key(3),
        isCurrent: () => true,
        load: (_) async {
          sent.add(3);
          return result(3);
        },
      );
      await tester.pump(TopicPrefetchController.hoverDelay);
      first.complete(
        result(1),
      ); // Even an uncooperative client cannot publish A.
      await tester.pump();
      expect(sent, [1, 3]);
      expect(controller.take(key(1)), isNull);
      expect((await controller.take(key(3)))?.payload.detail.id, 3);
    },
  );

  testWidgets(
    'click owns the active request after pointer exit or another hover',
    (tester) async {
      final controller = TopicPrefetchController();
      addTearDown(controller.clear);
      final response = Completer<PrefetchedTopic?>();
      late TopicPrefetchCancellation cancellation;
      final leave = controller.hover(
        key(1),
        isCurrent: () => true,
        load: (token) {
          cancellation = token;
          return response.future;
        },
      );
      await tester.pump(TopicPrefetchController.hoverDelay);
      final clicked = controller.take(key(1));
      expect(clicked, isNotNull);
      leave();
      controller.hover(
        key(2),
        isCurrent: () => true,
        load: (_) async => result(2),
      );
      await tester.pump(TopicPrefetchController.hoverDelay);
      expect(cancellation.isCancelled, isFalse);
      response.complete(result(1));
      await tester.pump();
      expect((await clicked)?.payload.detail.id, 1);
      expect((await controller.take(key(2)))?.payload.detail.id, 2);
    },
  );

  testWidgets(
    'clearing releases an adopted prefetch before its loader settles',
    (tester) async {
      final controller = TopicPrefetchController();
      final response = Completer<PrefetchedTopic?>();
      controller.hover(
        key(1),
        intent: TopicPrefetchIntent.trajectory,
        isCurrent: () => true,
        load: (_) => response.future,
      );
      var finished = false;
      final adopted = controller.take(key(1))!.then((value) {
        finished = true;
        return value;
      });
      controller.clear();
      await tester.pump();
      final finishedBeforeResponse = finished;
      response.complete(result(1));
      expect(await adopted, isNull);
      expect(finishedBeforeResponse, isTrue);
    },
  );

  testWidgets('click before the dwell lets navigation load immediately', (
    tester,
  ) async {
    final controller = TopicPrefetchController();
    addTearDown(controller.clear);
    var sent = false;
    controller.hover(
      key(1),
      isCurrent: () => true,
      load: (_) async {
        sent = true;
        return result(1);
      },
    );
    expect(controller.take(key(1)), isNull);
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(sent, isFalse);
  });

  testWidgets('completed response is reused briefly and expires', (
    tester,
  ) async {
    final controller = TopicPrefetchController(clock: tester.binding.clock.now);
    addTearDown(controller.clear);
    var sent = 0;
    void Function() hover() => controller.hover(
      key(1),
      isCurrent: () => true,
      load: (_) async {
        sent++;
        return result(1);
      },
    );
    final leave = hover();
    await tester.pump(TopicPrefetchController.hoverDelay);
    leave();
    hover();
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(sent, 1);
    await tester.pump(TopicPrefetchController.lifetime);
    expect(controller.take(key(1)), isNull);
    hover();
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(sent, 2);
  });

  testWidgets('different accounts and post positions cannot consume a result', (
    tester,
  ) async {
    final controller = TopicPrefetchController();
    addTearDown(controller.clear);
    controller.hover(
      key(1, postNumber: 7),
      isCurrent: () => true,
      load: (_) async => result(1),
    );
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(controller.take(key(1, postNumber: 8)), isNull);
    expect(
      controller.take((
        siteUrl: 'https://other.example',
        session: session,
        topicId: 1,
        postNumber: 7,
      )),
      isNull,
    );
    expect(
      controller.take((
        siteUrl: key(1).siteUrl,
        session: Object(),
        topicId: 1,
        postNumber: 7,
      )),
      isNull,
    );
    expect(
      (await controller.take(key(1, postNumber: 7)))?.payload.detail.id,
      1,
    );
  });

  testWidgets('retired context and failures leave no reusable result', (
    tester,
  ) async {
    final controller = TopicPrefetchController();
    addTearDown(controller.clear);
    var current = true;
    var sent = 0;
    controller.hover(
      key(1),
      isCurrent: () => current,
      load: (_) async {
        sent++;
        return result(1);
      },
    );
    current = false;
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(sent, 0);
    controller.hover(
      key(2),
      isCurrent: () => true,
      load: (_) async => throw StateError('offline'),
    );
    await tester.pump(TopicPrefetchController.hoverDelay);
    expect(controller.take(key(2)), isNull);
  });
}
