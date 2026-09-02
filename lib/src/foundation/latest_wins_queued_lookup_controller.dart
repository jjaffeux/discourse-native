import 'dart:async';

/// Serializes lookups while retaining only the newest request waiting to run.
///
/// A result or error is delivered only when its request is still the newest
/// submitted request. Disposing the controller drops queued work and ignores
/// the completion of any lookup already in flight.
final class LatestWinsQueuedLookupController<Request, Result> {
  LatestWinsQueuedLookupController({
    required Future<Result> Function(Request request) lookup,
    required void Function(Result result) onResult,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) : this._(lookup, onResult, onError);

  LatestWinsQueuedLookupController._(
    this._lookup,
    this._onResult,
    this._onError,
  );

  final Future<Result> Function(Request request) _lookup;
  final void Function(Result result) _onResult;
  final void Function(Object error, StackTrace stackTrace) _onError;

  int _revision = 0;
  bool _running = false;
  bool _disposed = false;
  ({int revision, Request value})? _queued;

  void request(Request value) {
    if (_disposed) return;
    final request = (revision: ++_revision, value: value);
    if (_running) {
      _queued = request;
      return;
    }
    unawaited(_run(request));
  }

  Future<void> _run(({int revision, Request value}) request) async {
    _running = true;
    try {
      await _complete(request);
    } finally {
      _running = false;
      final queued = _queued;
      _queued = null;
      if (queued != null && _isCurrent(queued)) unawaited(_run(queued));
    }
  }

  Future<void> _complete(({int revision, Request value}) request) async {
    late final Result result;
    try {
      result = await _lookup(request.value);
    } catch (error, stackTrace) {
      if (_isCurrent(request)) _onError(error, stackTrace);
      return;
    }
    if (_isCurrent(request)) _onResult(result);
  }

  bool _isCurrent(({int revision, Request value}) request) =>
      !_disposed && request.revision == _revision;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    _queued = null;
  }
}
