import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import '../models/site_appearance.dart';
import 'discourse_api_contracts.dart';
import 'discourse_request_coordinator.dart';
import 'http_transport.dart';
import 'json_decode.dart';
import 'site_appearance_loader.dart';

final class DiscourseHeadResponse {
  const DiscourseHeadResponse(this.url, this.statusCode, this.headers);

  final Uri url;
  final int statusCode;
  final Map<String, String> headers;
}

final class DiscourseTransport {
  factory DiscourseTransport.create({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
    int maxResponseBytes = 16 * 1024 * 1024,
  }) => DiscourseTransport(
    client == null ? SafeHttpClient.create() : SafeHttpClient.owned(client),
    timeout,
    maxResponseBytes,
  );

  DiscourseTransport(
    this._client,
    this.timeout,
    this._maxResponseBytes, {
    DiscourseRequestCoordinator? coordinator,
    int maxConcurrentPerOrigin = 4,
    int maxQueuedPerOrigin = 64,
    Duration defaultRateLimitCooldown = const Duration(seconds: 15),
  }) : coordinator =
           coordinator ??
           DiscourseRequestCoordinator(
             maxConcurrentPerOrigin: maxConcurrentPerOrigin,
             maxQueuedPerOrigin: maxQueuedPerOrigin,
             defaultRateLimitCooldown: defaultRateLimitCooldown,
           );

  final SafeHttpClient _client;
  final Duration timeout;
  final int _maxResponseBytes;
  final DiscourseRequestCoordinator coordinator;

  late final SiteAppearanceLoader _siteAppearanceLoader = SiteAppearanceLoader(
    client: _client,
    coordinator: coordinator,
    timeout: timeout,
    maxResponseBytes: _maxResponseBytes < 2 * 1024 * 1024
        ? _maxResponseBytes
        : 2 * 1024 * 1024,
  );

  static const String userAgent = 'DiscourseNative/1.0';

  Future<http.Response> request(String method, Uri url) =>
      send(http.Request(method, url));

  Future<http.Response> requestAuthenticated(
    String method,
    Uri url, {
    required String siteUrl,
    required String apiKey,
    String? clientId,
    Object? jsonBody,
  }) {
    final request = http.Request(method, url);
    if (jsonBody != null) request.body = jsonEncode(jsonBody);
    return sendAuthenticated(
      request,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  Future<DiscourseHeadResponse> head(Uri url, {int maxRedirects = 5}) async {
    var current = url;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final response = await request('HEAD', current);
      final location = response.headers['location'];
      final isRedirect = const {
        301,
        302,
        303,
        307,
        308,
      }.contains(response.statusCode);

      if (!isRedirect || location == null) {
        return DiscourseHeadResponse(
          current,
          response.statusCode,
          response.headers,
        );
      }

      current = resolveSafeHttpRedirect(current, location);
    }

    throw SiteLookupException(SiteLookupFailure.unreachable, url.toString());
  }

  Future<http.Response> upload({
    required Uri url,
    required String siteUrl,
    required String apiKey,
    required String uploadType,
    required String filename,
    required int fileLength,
    required Stream<List<int>> fileBytes,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    String? clientId,
    Duration requestTimeout = const Duration(minutes: 5),
  }) async {
    var sent = 0;
    final timeoutAbort = Completer<void>();
    final timer = Timer(requestTimeout, timeoutAbort.complete);
    final request =
        http.AbortableMultipartRequest(
            'POST',
            url,
            abortTrigger: Future.any<void>([abortTrigger, timeoutAbort.future]),
          )
          ..fields['upload_type'] = uploadType
          ..files.add(
            http.MultipartFile(
              'file',
              fileBytes.map((chunk) {
                sent += chunk.length;
                onProgress(
                  fileLength == 0 ? 0 : (sent / fileLength).clamp(0, 1),
                );
                return chunk;
              }),
              fileLength,
              filename: filename,
            ),
          );

    try {
      return await sendAuthenticated(
        request,
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        requestTimeout: requestTimeout,
      );
    } finally {
      timer.cancel();
    }
  }

  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) => _siteAppearanceLoader.load(
    siteUrl: siteUrl,
    username: username,
    apiKey: apiKey,
    clientId: clientId,
  );

  Future<http.Response> send(
    http.BaseRequest request, {
    Duration? requestTimeout,
  }) async {
    try {
      requireSafeHttpUrl(request.url);
      return await coordinator.run(
        request.url,
        () => sendBoundedHttpRequest(
          _client,
          request,
          timeout: requestTimeout ?? timeout,
          maxBodyBytes: _maxResponseBytes,
        ),
      );
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        error.url.toString(),
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Attaches user API credentials to a specialized request only after its
  /// destination has been proven to belong to the connected site.
  Future<http.Response> sendAuthenticated(
    http.BaseRequest request, {
    required String siteUrl,
    required String apiKey,
    String? clientId,
    Duration? requestTimeout,
  }) async {
    try {
      _requireCredentialOrigin(request.url, siteUrl);
      request.headers.addAll(authHeaders(apiKey, clientId: clientId));
      return await send(request, requestTimeout: requestTimeout);
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      // Match [send]'s public failure shape when the earlier credential-origin
      // gate, rather than SafeHttpClient, is the check that refused the URL.
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        error.url.toString(),
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<http.Response> get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      requireSafeHttpUrl(url);
      if (apiKey != null) _requireCredentialOrigin(url, siteUrl);
      response = await coordinator.run(
        url,
        () {
          final request = http.Request('GET', url);
          if (apiKey != null) {
            request.headers.addAll(authHeaders(apiKey, clientId: clientId));
          }
          return sendBoundedHttpRequest(
            _client,
            request,
            timeout: timeout,
            maxBodyBytes: _maxResponseBytes,
          );
        },
        coalesce: DiscourseGetRequestKey(
          url,
          apiKey: apiKey,
          clientId: clientId,
        ),
      );
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> getObject(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await get(
      url,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Expected a JSON object');
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Core uses POST here to keep a potentially private search term out of URLs.
  Future<Map<String, dynamic>> postObject(
    Uri url, {
    required String siteUrl,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      final request = http.Request('POST', url)
        ..body = jsonEncode({
          for (final entry in body.entries)
            if (entry.value != null) entry.key: entry.value,
        });
      response = await sendAuthenticated(
        request,
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Expected a JSON object');
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Deliberately never retries. A user API key receives no idempotency from
  /// Discourse, so retrying an ambiguous timeout can publish twice.
  Future<Map<String, dynamic>> write(
    Uri url, {
    required String siteUrl,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      final request = http.Request(method, url)
        // Rails reads a missing optional parameter and explicit null
        // differently. Null here means that the server should choose.
        ..body = jsonEncode({
          for (final entry in body.entries)
            if (entry.value != null) entry.key: entry.value,
        });
      response = await sendAuthenticated(
        request,
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
    } catch (error, stackTrace) {
      throw WriteException(
        WriteFailure.unreachable,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    final decoded = decodeObjectOrEmpty(response.body);
    // A delete may return any empty 2xx success status.
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final errors = [
      for (final error in jsonArray(decoded['errors']))
        if (error is String && error.trim().isNotEmpty) error.trim(),
      // Some plugin controllers, including discourse-assign, return a single
      // localized business-rule refusal under `error` rather than core's
      // usual `errors` array. Preserve it at the shared boundary so callers
      // can show what the site actually refused.
      if (jsonText(decoded['error'])?.trim() case final error?
          when error.isNotEmpty)
        error,
    ];

    throw WriteException(
      switch (response.statusCode) {
        401 || 403 => WriteFailure.forbidden,
        409 => WriteFailure.conflict,
        429 => WriteFailure.rateLimited,
        _ when errors.isNotEmpty => WriteFailure.validation,
        _ => WriteFailure.unreachable,
      },
      errors: errors,
      statusCode: response.statusCode,
      retryAfter: DiscourseRequestCoordinator.explicitRetryAfter(response),
    );
  }

  /// Error bodies can be HTML or empty. A failed decode is response metadata,
  /// not another transport failure, so writes fall back to an empty object.
  static Map<String, dynamic> decodeObjectOrEmpty(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// User API credentials belong to the connected site's origin. Checking
  /// before request construction makes it impossible for a future route typo
  /// or absolute URL to attach them to another host, even though HTTPS itself
  /// would otherwise be a valid transport.
  static void _requireCredentialOrigin(Uri url, String siteUrl) {
    final site = requireSafeHttpUrl(Uri.parse(siteUrl));
    final target = requireSafeHttpUrl(url);
    if (target.origin != site.origin) {
      throw UnsafeHttpTransportException(target);
    }
  }

  static Map<String, String> authHeaders(String apiKey, {String? clientId}) => {
    'User-Api-Key': apiKey,
    'User-Api-Client-Id': ?clientId,
    'User-Agent': userAgent,
    'Content-Type': 'application/json',
    'Dont-Chunk': 'true',
  };

  void close() {
    coordinator.close();
    _client.close();
  }
}
