import 'chat_stream_target.dart';

typedef ChatViewportRoute = ({String siteUrl, ChatStreamTarget target});
typedef ChatViewportAnchor = ({ChatViewportRoute route, int fetches});

/// Borrowed facts from the canonical stream, used only during a transition.
final class ChatViewportWindow {
  const ChatViewportWindow({
    required this.revision,
    required this.route,
    required this.fetches,
    required this.messageIds,
    required this.atPresent,
    required this.canLoadMoreFuture,
  });

  final Object revision;
  final ChatViewportRoute route;
  final int fetches;
  final List<int> messageIds;
  final bool atPresent;
  final bool canLoadMoreFuture;

  int? get newestId => messageIds.lastOrNull;
  ChatViewportAnchor get anchor => (route: route, fetches: fetches);
}

final class ChatViewportChange {
  const ChatViewportChange({
    required this.changedRoute,
    this.holdArrival = false,
    this.forwardAnchorId,
  });

  final bool changedRoute;
  final bool holdArrival;
  final int? forwardAnchorId;
}

/// Owns reading-position policy without holding rows or scheduling frames.
final class ChatViewportTransitions {
  ChatViewportAnchor? _anchored;
  Object? _windowRevision;
  ({Object token, Object? windowRevision})? _landing;
  bool _away = false;
  int _unseen = 0;
  Object? _arrival;
  Object? _dayJump;
  int _boundaryRevision = 0;

  bool get anchoring => _landing != null;

  ChatViewportChange observeWindow(
    ChatViewportWindow previous,
    ChatViewportWindow current,
  ) {
    _windowRevision = current.revision;
    final changedRoute = previous.route != current.route;
    final sameFetch = previous.fetches == current.fetches;
    if (changedRoute || !sameFetch) _cancelDeferred();
    if (_landing?.windowRevision case final revision?) {
      if (!identical(revision, current.revision)) _landing = null;
    }
    if (changedRoute) {
      _anchored = null;
      _away = false;
      _unseen = 0;
      return const ChatViewportChange(changedRoute: true);
    }
    final newestChanged = previous.newestId != current.newestId;
    final holdArrival =
        _away &&
        sameFetch &&
        previous.atPresent &&
        current.atPresent &&
        newestChanged;
    if (holdArrival) {
      _unseen += _messagesAfterHeldNewest(
        previous.messageIds,
        current.messageIds,
      );
    }
    return ChatViewportChange(
      changedRoute: false,
      holdArrival: holdArrival,
      forwardAnchorId: previous.canLoadMoreFuture && sameFetch && newestChanged
          ? previous.newestId
          : null,
    );
  }

  bool needsAnchor(ChatViewportAnchor anchor) => _anchored != anchor;

  ({int? messageId, int? seenId}) beginAnchor(
    ChatViewportAnchor anchor, {
    required int? anchorMessageId,
    required int? lastReadOnOpen,
    required int? newestId,
  }) {
    _anchored = anchor;
    beginLanding();
    final target = anchorMessageId ?? lastReadOnOpen;
    return (
      messageId: target == newestId ? null : target,
      seenId: target ?? newestId,
    );
  }

  Object beginLanding() {
    final token = Object();
    _landing = (token: token, windowRevision: null);
    return token;
  }

  Object beginForwardPage() {
    final token = Object();
    _landing = (token: token, windowRevision: _windowRevision);
    return token;
  }

  bool isCurrentLanding(Object token) => identical(_landing?.token, token);

  bool settleLanding(Object token) {
    if (!isCurrentLanding(token)) return false;
    _landing = null;
    return true;
  }

  void _cancelDeferred() {
    _landing = null;
    _arrival = null;
    _dayJump = null;
    _boundaryRevision++;
  }

  void retire() {
    _cancelDeferred();
    _anchored = null;
    _windowRevision = null;
  }

  Object beginArrivalHold() => _arrival = Object();
  bool isCurrentArrival(Object token) => identical(_arrival, token);
  void cancelArrivalHold() => _arrival = null;

  Object beginDayJump() => _dayJump = Object();
  bool isCurrentDayJump(Object token) => identical(_dayJump, token);

  int beginBoundaryJump() => ++_boundaryRevision;
  bool isCurrentBoundaryJump(int revision) => revision == _boundaryRevision;
  void cancelBoundaryJump() => _boundaryRevision++;

  void observePresent({required bool atPresent, required bool beyondSlack}) {
    _away = !atPresent || beyondSlack;
    if (!_away) _unseen = 0;
  }

  void clearUnseen() => _unseen = 0;

  ({bool away, int pendingCount}) presentState(int pendingNewMessages) =>
      (away: _away, pendingCount: pendingNewMessages + _unseen);

  static int _messagesAfterHeldNewest(List<int> held, List<int> current) {
    final newest = held.lastOrNull;
    if (newest == null) return current.length;
    final seam = current.lastIndexOf(newest);
    if (seam >= 0) return current.length - seam - 1;
    final previouslyHeld = held.toSet();
    return current.where((id) => !previouslyHeld.contains(id)).length;
  }
}
