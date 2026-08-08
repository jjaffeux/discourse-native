import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/site_appearance.dart';
import 'http_transport.dart';
import 'site_appearance_parser.dart';

/// Why a site's optional appearance could not be loaded safely.
///
/// Appearance never blocks reading a site. Callers absorb this exception and
/// retain the last persisted appearance (or the app default), while the
/// separate cases keep transport and parser failures observable in tests and
/// logs.
enum SiteAppearanceLoadFailure {
  refused,
  unavailable,
  unsafeUrl,
  tooManyRedirects,
  responseTooLarge,
  timedOut,
  malformed,
}

final class SiteAppearanceLoadException implements Exception {
  const SiteAppearanceLoadException(
    this.failure, {
    required this.url,
    this.statusCode,
    this.detail,
  });

  final SiteAppearanceLoadFailure failure;
  final Uri url;
  final int? statusCode;

  /// Diagnostic context only. Appearance loading is deliberately quiet in the
  /// UI, so callers should not present this value directly to a reader.
  final Object? detail;

  @override
  String toString() =>
      'SiteAppearanceLoadException($failure, $url, $statusCode, $detail)';
}

/// Reads the active Discourse color-scheme stylesheets without exposing a user
/// API key to a CDN.
///
/// The forum document is the only request that can be authenticated. When it
/// is, redirects remain on the same origin because every hop carries the same
/// credentials. An anonymous document may follow a safe canonical cross-origin
/// redirect. Stylesheets start a separate credential-free request chain and
/// may use a safe CDN. A discovered appearance is returned only after every
/// referenced stylesheet has arrived and parsed successfully.
final class SiteAppearanceLoader {
  SiteAppearanceLoader({
    required http.Client client,
    this.timeout = const Duration(seconds: 10),
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxRedirects = 5,
  }) : assert(timeout > Duration.zero),
       assert(maxResponseBytes > 0),
       assert(maxRedirects >= 0),
       _client = SafeHttpClient.borrowed(client);

  final http.Client _client;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxRedirects;

  static const String _userAgent = 'DiscourseNative/1.0';

  /// Loads the active appearance, or null when the document advertises none.
  ///
  /// [apiKey] and [clientId] are sent only to the root document and its
  /// same-origin redirects. In particular, an authentication refusal is final:
  /// this never retries the document anonymously.
  Future<SiteAppearance?> load({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final Uri documentUrl;
    try {
      final parsed = Uri.parse(siteUrl);
      final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
      documentUrl = requireSafeHttpUrl(
        parsed.replace(path: path, query: null, fragment: null),
      );
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.unsafeUrl,
        url: Uri.tryParse(siteUrl) ?? Uri(),
        detail: error,
      );
    }

    final document = await _loadText(
      documentUrl,
      accept: 'text/html',
      headers: {
        'User-Agent': _userAgent,
        if (apiKey != null) ...{
          'User-Api-Key': apiKey,
          'User-Api-Client-Id': ?clientId,
        },
      },
      redirectOrigin: apiKey == null ? null : documentUrl.origin,
    );

    final SiteAppearanceStylesheets? discovered;
    try {
      discovered = discoverSiteAppearanceStylesheets(
        document.source,
        documentUrl: document.url,
      );
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.malformed,
        url: document.url,
        detail: error,
      );
    }
    if (discovered == null) return null;

    final urls = <Uri>{discovered.base, ?discovered.alternate};
    for (final url in urls) {
      _requireSafeStylesheetUrl(document.url, url);
    }
    final loaded = await Future.wait([
      for (final url in urls)
        _loadText(
          url,
          accept: 'text/css',
          headers: const {'User-Agent': _userAgent},
        ),
    ]);
    final sources = {
      for (var index = 0; index < urls.length; index++)
        urls.elementAt(index): loaded[index].source,
    };

    final ResolvedSitePalette base;
    final ResolvedSitePalette? alternate;
    try {
      base = _parseStylesheet(sources[discovered.base]!, discovered.base);
      alternate = discovered.alternate == null
          ? null
          : _parseStylesheet(
              sources[discovered.alternate]!,
              discovered.alternate!,
            );
    } on SiteAppearanceLoadException {
      rethrow;
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.malformed,
        url: discovered.base,
        detail: error,
      );
    }

    return SiteAppearance(
      base: base,
      alternate: alternate,
      mode: discovered.mode,
    );
  }

  void _requireSafeStylesheetUrl(Uri documentUrl, Uri stylesheetUrl) {
    try {
      // Apply the same downgrade rule before the first subresource request
      // that redirects already receive at every subsequent hop.
      resolveSafeHttpRedirect(documentUrl, stylesheetUrl.toString());
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.unsafeUrl,
        url: stylesheetUrl,
        detail: error,
      );
    }
  }

  ResolvedSitePalette _parseStylesheet(String source, Uri url) {
    final palette = parseSiteAppearanceStylesheet(source);
    if (palette != null) return palette;
    throw SiteAppearanceLoadException(
      SiteAppearanceLoadFailure.malformed,
      url: url,
    );
  }

  Future<_LoadedText> _loadText(
    Uri initialUrl, {
    required String accept,
    required Map<String, String> headers,
    String? redirectOrigin,
  }) async {
    var current = initialUrl;

    for (var redirects = 0; ; redirects++) {
      final response = await _send(
        http.Request('GET', current)
          ..headers['Accept'] = accept
          ..headers.addAll(headers),
      );

      if (!_isRedirect(response.statusCode)) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw SiteAppearanceLoadException(
            SiteAppearanceLoadFailure.refused,
            url: current,
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode != 200) {
          throw SiteAppearanceLoadException(
            SiteAppearanceLoadFailure.unavailable,
            url: current,
            statusCode: response.statusCode,
          );
        }
        return (url: current, source: response.body);
      }

      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.malformed,
          url: current,
          statusCode: response.statusCode,
          detail: 'redirect without a location',
        );
      }
      if (redirects >= maxRedirects) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.tooManyRedirects,
          url: current,
          statusCode: response.statusCode,
        );
      }

      final Uri target;
      try {
        target = resolveSafeHttpRedirect(current, location);
      } on Object catch (error) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.unsafeUrl,
          url: current,
          statusCode: response.statusCode,
          detail: error,
        );
      }
      if (redirectOrigin != null && target.origin != redirectOrigin) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.unsafeUrl,
          url: target,
          statusCode: response.statusCode,
          detail: 'authenticated redirect crossed origins',
        );
      }
      current = target;
    }
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await sendBoundedHttpRequest(
        _client,
        request,
        timeout: timeout,
        maxBodyBytes: maxResponseBytes,
      );
    } on SiteAppearanceLoadException {
      rethrow;
    } on TimeoutException catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.timedOut,
        url: request.url,
        detail: error,
      );
    } on HttpResponseTooLargeException catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.responseTooLarge,
        url: request.url,
        detail: error,
      );
    } on UnsafeHttpTransportException catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.unsafeUrl,
        url: error.url,
        detail: error,
      );
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.unavailable,
        url: request.url,
        detail: error,
      );
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

typedef _LoadedText = ({Uri url, String source});
