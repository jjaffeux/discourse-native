import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:flutter_test/flutter_test.dart' show WidgetTesterCallback;

/// [flutter_test.testWidgets] with post thumbnails left loading.
///
/// The test binding answers image requests with an error, and a tile whose
/// thumbnail fails stops being a button. Suites that open images from a tile
/// hide flutter_test's `testWidgets` and import this one. Full-size requests
/// still fail, because a viewer left loading animates forever; a fixture that
/// wants one loading names it `pending`. The hook is reset inside the body
/// because the binding checks it before any tear-down.
void testWidgets(String description, WidgetTesterCallback callback) =>
    flutter_test.testWidgets(description, (tester) async {
      debugNetworkImageHttpClientProvider = _PendingThumbnailHttpClient.new;
      try {
        await callback(tester);
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    });

class _PendingThumbnailHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      RegExp(r'(^|[-/])(t|thumb|pending)\.[a-z]+$').hasMatch(url.path)
      ? Completer<HttpClientRequest>().future
      : Future.error(HttpException('No network in tests', uri: url));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
