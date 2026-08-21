import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/site_appearance.dart';
import 'discourse_request_coordinator.dart';
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

/// Resolves the active Discourse theme through JSON APIs, then reads its
/// compiled color and common-theme stylesheets without exposing a user API
/// key to a CDN.
///
/// Forum JSON requests can be authenticated and remain same-origin whenever
/// they carry credentials. The compiled stylesheet assets start separate,
/// credential-free request chains and may use a safe CDN. A discovered
/// appearance is returned only after every required stylesheet has arrived and
/// parsed successfully. The theme stylesheet matters because it follows the
/// color definition in the browser cascade and may replace semantic colors.
final class SiteAppearanceLoader {
  SiteAppearanceLoader({
    required http.Client client,
    this.timeout = const Duration(seconds: 10),
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxRedirects = 5,
    DiscourseRequestCoordinator? coordinator,
  }) : assert(timeout > Duration.zero),
       assert(maxResponseBytes > 0),
       assert(maxRedirects >= 0),
       _client = SafeHttpClient.borrowed(client),
       _coordinator = coordinator ?? DiscourseRequestCoordinator();

  final http.Client _client;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxRedirects;
  final DiscourseRequestCoordinator _coordinator;

  static const String _userAgent = 'DiscourseNative/1.0';

  /// Loads the active appearance, or null when the site lacks modern theme
  /// metadata.
  ///
  /// [apiKey] and [clientId] are sent only to forum JSON endpoints and their
  /// same-origin redirects. [username] identifies that key's stored theme
  /// preferences. In particular, an authentication refusal is final: this
  /// never retries anonymously.
  Future<SiteAppearance?> load({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    final Uri siteBase;
    try {
      final parsed = Uri.parse(siteUrl);
      final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
      siteBase = requireSafeHttpUrl(
        parsed.replace(path: path, query: null, fragment: null),
      );
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.unsafeUrl,
        url: Uri.tryParse(siteUrl) ?? Uri(),
        detail: error,
      );
    }

    final forumHeaders = {
      'User-Agent': _userAgent,
      if (apiKey != null) ...{
        'User-Api-Key': apiKey,
        'User-Api-Client-Id': ?clientId,
      },
    };
    final authenticatedOrigin = apiKey == null ? null : siteBase.origin;
    final siteResponse = await _loadJson(
      siteBase.resolve('site.json'),
      headers: forumHeaders,
      redirectOrigin: authenticatedOrigin,
    );
    final apiBase = siteResponse.url.resolve('.');

    Object? userJson;
    if (apiKey != null) {
      if (username == null || username.trim().isEmpty) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.malformed,
          url: apiBase,
          detail: 'authenticated appearance has no username',
        );
      }
      userJson = (await _loadJson(
        apiBase.resolve('u/${Uri.encodeComponent(username.trim())}.json'),
        headers: forumHeaders,
        redirectOrigin: apiBase.origin,
      )).value;
    }

    final selection = resolveSiteAppearanceSelection(
      site: siteResponse.value,
      user: userJson,
    );
    if (selection == null) return null;

    final schemeIds = <int>{
      selection.baseSchemeId,
      ?selection.alternateSchemeId,
    };
    final schemeDetails = Future.wait([
      for (final schemeId in schemeIds)
        _loadJson(
          apiBase.resolve(
            'color-scheme-stylesheet/$schemeId/${selection.themeId}.json',
          ),
          headers: forumHeaders,
          redirectOrigin: apiKey == null ? null : apiBase.origin,
        ),
    ]);
    // The resolver returns only color definitions. Read the forum document as
    // well to discover the selected parent theme's later common stylesheet.
    // This request may carry credentials, but every discovered CSS request
    // starts a separate credential-free chain below.
    //
    // The document depends only on the API base and is the heaviest single
    // response of this refresh, so it must share the wire with the small
    // scheme JSONs rather than queue behind them. It is awaited after them so
    // failure attribution is unchanged; ignore() stops a scheme or href
    // failure from leaving this in-flight future's error unobserved, without
    // consuming the result the later await still needs.
    final documentLoad = _loadText(
      apiBase,
      accept: 'text/html',
      headers: forumHeaders,
      redirectOrigin: apiKey == null ? null : apiBase.origin,
    );
    documentLoad.ignore();
    final details = await schemeDetails;

    final stylesheetUrls = <int, Uri>{};
    for (var index = 0; index < schemeIds.length; index++) {
      final response = details[index];
      final href = _newStylesheetHref(response.value);
      if (href == null) {
        throw SiteAppearanceLoadException(
          SiteAppearanceLoadFailure.malformed,
          url: response.url,
          detail: 'stylesheet JSON has no new_href',
        );
      }
      final url = response.url.resolve(href);
      _requireSafeStylesheetUrl(response.url, url);
      stylesheetUrls[schemeIds.elementAt(index)] = url;
    }

    final document = await documentLoad;
    final themeStylesheetUrls = discoverSiteThemeStylesheets(
      document.source,
      documentUrl: document.url,
      themeId: selection.themeId,
    );
    for (final url in themeStylesheetUrls) {
      _requireSafeStylesheetUrl(document.url, url);
    }

    final uniqueUrls = {...stylesheetUrls.values, ...themeStylesheetUrls};
    final loaded = await Future.wait([
      for (final url in uniqueUrls)
        _loadText(
          url,
          accept: 'text/css',
          headers: const {'User-Agent': _userAgent},
        ),
    ]);
    final sources = {
      for (var index = 0; index < uniqueUrls.length; index++)
        uniqueUrls.elementAt(index): loaded[index].source,
    };

    ResolvedSitePalette parse(int schemeId) {
      final url = stylesheetUrls[schemeId]!;
      return _parseStylesheets([
        sources[url]!,
        for (final url in themeStylesheetUrls) sources[url]!,
      ], url);
    }

    final ResolvedSitePalette base;
    final ResolvedSitePalette? alternate;
    try {
      base = parse(selection.baseSchemeId);
      alternate = selection.alternateSchemeId == null
          ? null
          : parse(selection.alternateSchemeId!);
    } on SiteAppearanceLoadException {
      rethrow;
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.malformed,
        url: stylesheetUrls[selection.baseSchemeId]!,
        detail: error,
      );
    }

    return SiteAppearance(
      base: base,
      alternate: alternate,
      mode: selection.mode,
    );
  }

  String? _newStylesheetHref(Object? value) {
    if (value is! Map) return null;
    final href = value['new_href'];
    return href is String && href.trim().isNotEmpty ? href.trim() : null;
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

  ResolvedSitePalette _parseStylesheets(Iterable<String> sources, Uri url) {
    final palette = parseSiteAppearanceStylesheets(sources);
    if (palette != null) return palette;
    throw SiteAppearanceLoadException(
      SiteAppearanceLoadFailure.malformed,
      url: url,
    );
  }

  Future<_LoadedJson> _loadJson(
    Uri url, {
    required Map<String, String> headers,
    String? redirectOrigin,
  }) async {
    final loaded = await _loadText(
      url,
      accept: 'application/json',
      headers: headers,
      redirectOrigin: redirectOrigin,
    );
    try {
      return (url: loaded.url, value: jsonDecode(loaded.source));
    } on Object catch (error) {
      throw SiteAppearanceLoadException(
        SiteAppearanceLoadFailure.malformed,
        url: loaded.url,
        detail: error,
      );
    }
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
      return await _coordinator.run(
        request.url,
        () => sendBoundedHttpRequest(
          _client,
          request,
          timeout: timeout,
          maxBodyBytes: maxResponseBytes,
        ),
        coalesce: request.method == 'GET'
            ? DiscourseGetRequestKey(
                request.url,
                apiKey: request.headers['User-Api-Key'],
                clientId: request.headers['User-Api-Client-Id'],
              )
            : null,
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
typedef _LoadedJson = ({Uri url, Object? value});
