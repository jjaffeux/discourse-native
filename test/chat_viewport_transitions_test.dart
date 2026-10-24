import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_viewport_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = (siteUrl: 'https://one.example', target: ChatChannelTarget(9));
const _thread = (
  siteUrl: 'https://one.example',
  target: ChatThreadTarget(channelId: 9, threadId: 3),
);

ChatViewportWindow _window({
  ChatViewportRoute route = _channel,
  List<int> ids = const [1, 2, 3],
  int fetches = 1,
  bool atPresent = true,
  bool canLoadMoreFuture = false,
  Object? revision,
}) => ChatViewportWindow(
  revision: revision ?? Object(),
  route: route,
  fetches: fetches,
  messageIds: ids,
  atPresent: atPresent,
  canLoadMoreFuture: canLoadMoreFuture,
);

void main() {
  test('initial landing prefers explicit navigation to last read', () {
    final owner = ChatViewportTransitions();
    final window = _window();
    expect(owner.needsAnchor(window.anchor), isTrue);
    expect(
      owner.beginAnchor(
        window.anchor,
        anchorMessageId: 2,
        lastReadOnOpen: 1,
        newestId: 3,
      ),
      (messageId: 2, seenId: 2),
    );
    expect(owner.needsAnchor(window.anchor), isFalse);
    expect(owner.anchoring, isTrue);
    final landing = owner.beginLanding();
    expect(owner.settleLanding(landing), isTrue);
    expect(owner.anchoring, isFalse);
    expect(owner.needsAnchor(_window(fetches: 2).anchor), isTrue);
  });

  test('latest and empty windows land at the present without a row target', () {
    final owner = ChatViewportTransitions();
    for (final newest in [3, null]) {
      expect(
        owner.beginAnchor(
          _window().anchor,
          anchorMessageId: null,
          lastReadOnOpen: newest,
          newestId: newest,
        ),
        (messageId: null, seenId: newest),
      );
    }
  });

  test('only same-fetch live growth while away counts unseen arrivals', () {
    final owner = ChatViewportTransitions();
    owner.observePresent(atPresent: true, beyondSlack: true);
    final previous = _window();
    final current = _window(ids: [2, 3, 4, 5]);
    final change = owner.observeWindow(previous, current);
    expect(change.holdArrival, isTrue);
    expect(change.forwardAnchorId, isNull);
    expect(owner.presentState(7), (away: true, pendingCount: 9));
    owner.observePresent(atPresent: true, beyondSlack: false);
    expect(owner.presentState(0), (away: false, pendingCount: 0));
    expect(
      owner.observeWindow(current, _window(ids: [3, 4, 5, 6])).holdArrival,
      isFalse,
    );
  });

  test(
    'bounded windows count arrivals even when the old newest is evicted',
    () {
      final owner = ChatViewportTransitions();
      owner.observePresent(atPresent: true, beyondSlack: true);
      owner.observeWindow(_window(), _window(ids: [4, 5, 6]));
      expect(owner.presentState(0).pendingCount, 3);
    },
  );

  test('forward history pages retain the prior newest without live counts', () {
    final owner = ChatViewportTransitions();
    owner.observePresent(atPresent: false, beyondSlack: false);
    final old = _window(atPresent: false, canLoadMoreFuture: true);
    final page = _window(ids: [1, 2, 3, 4, 5]);
    final change = owner.observeWindow(old, page);
    expect(change.forwardAnchorId, 3);
    expect(change.holdArrival, isFalse);
    expect(owner.presentState(0).pendingCount, 0);
    expect(owner.isCurrentWindow(page), isTrue);
    owner.observeWindow(page, _window(ids: [1, 2, 3, 4, 5]));
    expect(owner.isCurrentWindow(page), isFalse);
  });

  test('replacement fetches neither count live arrivals nor retain a page', () {
    final owner = ChatViewportTransitions();
    owner.observePresent(atPresent: true, beyondSlack: true);
    final change = owner.observeWindow(
      _window(canLoadMoreFuture: true),
      _window(fetches: 2, ids: [40, 41]),
    );
    expect(change.forwardAnchorId, isNull);
    expect(change.holdArrival, isFalse);
    expect(owner.presentState(0).pendingCount, 0);
  });

  test('thread and site transitions retire arrival and day holds', () {
    for (final route in [
      _thread,
      (siteUrl: 'https://two.example', target: const ChatChannelTarget(9)),
    ]) {
      final owner = ChatViewportTransitions();
      owner.observePresent(atPresent: true, beyondSlack: true);
      final old = _window();
      owner.observeWindow(old, _window(ids: [1, 2, 3, 4]));
      final arrival = owner.beginArrivalHold();
      final day = owner.beginDayJump();
      final change = owner.observeWindow(old, _window(route: route));
      expect(change.changedRoute, isTrue);
      expect(owner.isCurrentArrival(arrival), isFalse);
      expect(owner.isCurrentDayJump(day), isFalse);
      expect(owner.presentState(0), (away: false, pendingCount: 0));
      expect(owner.needsAnchor(_window(route: route).anchor), isTrue);
    }
  });

  test(
    'intervening scroll cancels an arrival but day paging keeps its lease',
    () {
      final owner = ChatViewportTransitions();
      final arrival = owner.beginArrivalHold();
      final day = owner.beginDayJump();
      owner.cancelArrivalHold();
      owner.observeWindow(_window(), _window(ids: [0, 1, 2, 3]));
      expect(owner.isCurrentArrival(arrival), isFalse);
      expect(owner.isCurrentDayJump(day), isTrue);
      final nextArrival = owner.beginArrivalHold();
      expect(owner.isCurrentArrival(arrival), isFalse);
      expect(owner.isCurrentArrival(nextArrival), isTrue);
      owner.beginDayJump();
      expect(owner.isCurrentDayJump(day), isFalse);
    },
  );
}
