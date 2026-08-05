import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';

/// Why a site lookup did not produce an instance.
enum SiteLookupFailure {
  /// Reachable, but not a Discourse — or one too old to talk to an app.
  notDiscourse,

  /// Nothing answered: bad host, no network, timeout, or a non-200 status.
  unreachable,
}

class SiteLookupException implements Exception {
  const SiteLookupException(this.failure, this.term);

  final SiteLookupFailure failure;
  final String term;

  String get message => switch (failure) {
    SiteLookupFailure.notDiscourse =>
      '$term is not a Discourse forum, or is running a version too old to '
          'support apps.',
    SiteLookupFailure.unreachable => "Couldn't reach $term.",
  };

  @override
  String toString() => 'SiteLookupException($failure, $term)';
}

/// Talks to a Discourse site.
///
/// The lookup mirrors DiscourseMobile's `Site.fromTerm`: probe
/// `/user-api-key/new` to confirm it is a Discourse new enough to expose the
/// user API, then read `/site/basic-info.json` for the details we display.
class DiscourseApi {
  DiscourseApi({http.Client? client, this.timeout = const Duration(seconds: 10)})
    : _client = client ?? http.Client();

  static const int minimumApiVersion = 2;
  static const int _maxRedirects = 5;

  final http.Client _client;
  final Duration timeout;

  /// Turns whatever the user typed into a URL to probe.
  ///
  /// Bare hosts get https, since that is what any site worth connecting to
  /// serves; typing an explicit `http://` is the escape hatch for local
  /// development.
  static Uri normalize(String term) {
    var trimmed = term.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    return Uri.parse(trimmed);
  }

  Future<DiscourseInstance> lookup(String term) async {
    final probe = normalize(term).resolve('/user-api-key/new');

    final _HeadResult head;
    try {
      head = await _head(probe);
    } on SiteLookupException {
      rethrow;
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }

    // A Discourse always has this route; a 404 means we are talking to
    // something else, or to a version that predates the user API.
    if (head.statusCode == 404) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, term);
    }
    if (head.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }

    final apiVersion = int.tryParse(head.headers['auth-api-version'] ?? '') ?? 0;
    if (apiVersion < minimumApiVersion) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, term);
    }

    // Redirects may have moved us; keep where we landed, not where we started.
    //
    // Unlike DiscourseMobile we keep any port, which it strips — that would
    // break connecting to a site on localhost during development.
    final baseUrl = head.url
        .toString()
        .replaceFirst(RegExp(r'/user-api-key/new/*$'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    final Map<String, dynamic> info;
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/site/basic-info.json'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw SiteLookupException(SiteLookupFailure.unreachable, term);
      }
      info = jsonDecode(response.body) as Map<String, dynamic>;
    } on SiteLookupException {
      rethrow;
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }

    final title = (info['title'] as String?)?.trim();

    return DiscourseInstance(
      url: baseUrl,
      title: title == null || title.isEmpty ? Uri.parse(baseUrl).host : title,
      description: info['description'] as String?,
      iconUrl: _absoluteIcon(info['apple_touch_icon_url'] as String?, baseUrl),
      apiVersion: apiVersion,
      loginRequired: info['login_required'] as bool? ?? false,
    );
  }

  /// HEAD, following redirects by hand so the final URL is observable —
  /// `package:http` reports the originally requested one.
  Future<_HeadResult> _head(Uri url) async {
    var current = url;

    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('HEAD', current)..followRedirects = false;
      final response = await _client.send(request).timeout(timeout);
      await response.stream.drain<void>();

      final location = response.headers['location'];
      final isRedirect = const {301, 302, 303, 307, 308} //
          .contains(response.statusCode);

      if (!isRedirect || location == null) {
        return _HeadResult(current, response.statusCode, response.headers);
      }
      current = current.resolve(location);
    }

    throw SiteLookupException(SiteLookupFailure.unreachable, url.toString());
  }

  /// Who the stored API key belongs to.
  ///
  /// Needs the `session_info` scope. Throws [SiteLookupFailure.unreachable] on
  /// a network problem and [SiteLookupFailure.notDiscourse] if the key was
  /// rejected — the caller treats the latter as "reconnect".
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$siteUrl/session/current.json'),
            headers: authHeaders(apiKey, clientId: clientId),
          )
          .timeout(timeout);
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['current_user'] as Map<String, dynamic>?;
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }

    return DiscourseUser(
      username: user['username'] as String,
      name: user['name'] as String?,
      avatarUrl: _avatarUrl(user['avatar_template'] as String?, siteUrl),
    );
  }

  /// Headers every authenticated request carries, matching DiscourseMobile.
  static Map<String, String> authHeaders(String apiKey, {String? clientId}) => {
    'User-Api-Key': apiKey,
    'User-Api-Client-Id': ?clientId,
    'User-Agent': 'DiscourseNative/1.0',
    'Content-Type': 'application/json',
    'Dont-Chunk': 'true',
  };

  /// Avatar templates carry a `{size}` placeholder and may be site-relative.
  static String? _avatarUrl(String? template, String baseUrl) {
    if (template == null || template.isEmpty) return null;
    final sized = template.replaceAll('{size}', '120');
    return _absoluteIcon(sized, baseUrl);
  }

  /// Icons come back protocol-relative or site-relative depending on the site's
  /// CDN setup.
  static String? _absoluteIcon(String? icon, String baseUrl) {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('//')) return 'https:$icon';
    if (icon.startsWith('http://') || icon.startsWith('https://')) return icon;
    return '$baseUrl${icon.startsWith('/') ? '' : '/'}$icon';
  }

  void close() => _client.close();
}

class _HeadResult {
  const _HeadResult(this.url, this.statusCode, this.headers);

  final Uri url;
  final int statusCode;
  final Map<String, String> headers;
}
