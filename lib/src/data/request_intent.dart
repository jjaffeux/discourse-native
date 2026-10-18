import 'dart:async';

/// Scheduling intent for one finite operation, preserved across asynchronous
/// work. Unscoped work is interactive; speculative owners may promote once.
final class RequestIntent {
  RequestIntent.background() : _interactive = false;

  RequestIntent._interactive() : _interactive = true;

  static final _zoneKey = Object();
  static final _default = RequestIntent._interactive();
  static RequestIntent get current =>
      Zone.current[_zoneKey] as RequestIntent? ?? _default;

  bool _interactive;
  bool get isInteractive => _interactive;

  void promote() => _interactive = true;

  T run<T>(T Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});
}

/// A shared operation observes all its callers without promoting their sibling
/// operations. Retaining sources also observes adoption after callers join.
final class RequestIntentGroup extends RequestIntent {
  RequestIntentGroup(RequestIntent source) : super.background() {
    _sources.add(source);
  }

  final Set<RequestIntent> _sources = {};

  void join(RequestIntent source) {
    if (!identical(source, this)) _sources.add(source);
  }

  @override
  bool get isInteractive {
    final visited = <RequestIntent>{};
    final pending = <RequestIntent>[this];
    while (pending.isNotEmpty) {
      final source = pending.removeLast();
      if (!visited.add(source)) continue;
      if (source._interactive) return true;
      if (source is RequestIntentGroup) pending.addAll(source._sources);
    }
    return false;
  }
}

final class RequestIntentOperation<T> {
  RequestIntentOperation(Future<T> Function() operation)
    : intent = RequestIntentGroup(RequestIntent.current) {
    future = intent.run(operation);
  }

  final RequestIntentGroup intent;
  late final Future<T> future;

  Future<T> join() {
    intent.join(RequestIntent.current);
    return future;
  }
}
