import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Serves [bytes] to every `NetworkImage` request while installed as
/// `debugNetworkImageHttpClientProvider`, recording the requested URLs.
final class FakeImageHttpClient implements HttpClient {
  FakeImageHttpClient(this.bytes);

  Uint8List bytes;
  final requests = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _ImageHttpRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageHttpRequest implements HttpClientRequest {
  _ImageHttpRequest(this.bytes);

  final Uint8List bytes;

  @override
  Future<HttpClientResponse> close() async => _ImageHttpResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ImageHttpResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
