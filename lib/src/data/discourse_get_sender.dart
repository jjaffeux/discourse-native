import 'package:http/http.dart' as http;

import 'account_request_session.dart';
import 'discourse_request_coordinator.dart';
import 'http_transport.dart';
import 'request_intent.dart';

final class DiscourseGetSender {
  DiscourseGetSender(
    this._client,
    this._coordinator,
    this._timeout,
    this._maxResponseBytes,
  );

  final http.Client _client;
  final DiscourseRequestCoordinator _coordinator;
  final Duration _timeout;
  final int _maxResponseBytes;

  Future<http.Response> send(
    http.Request request, {
    required AccountRequestScope? scope,
    required Future<void>? cancellation,
    Duration? timeout,
    RequestIntent? intent,
  }) {
    assert(request.method == 'GET');
    final effectiveTimeout = timeout ?? _timeout;
    assert(effectiveTimeout > Duration.zero);
    return _coordinator.runGet(
      request.url,
      (sharedAbort) {
        if (scope != null && !scope.isCurrent) {
          throw DiscourseQueuedRequestCancelledException(request.url);
        }
        final outgoing =
            http.AbortableRequest('GET', request.url, abortTrigger: sharedAbort)
              ..headers.addAll(request.headers)
              ..followRedirects = request.followRedirects
              ..maxRedirects = request.maxRedirects
              ..persistentConnection = request.persistentConnection;
        return sendBoundedHttpRequest(
          _client,
          outgoing,
          timeout: effectiveTimeout,
          maxBodyBytes: _maxResponseBytes,
        );
      },
      abortTrigger: cancellation,
      coalesce: DiscourseGetRequestKey(
        request.url,
        headers: request.headers,
        timeout: effectiveTimeout,
        maxResponseBytes: _maxResponseBytes,
        session: scope?.session,
      ),
      intent: intent,
    );
  }
}
