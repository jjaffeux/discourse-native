import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'discourse_api_contracts.dart';
import 'discourse_transport.dart';
import 'http_url_safety.dart';

final class DsaNoticeHttpConnection implements DsaNoticeConnection {
  DsaNoticeHttpConnection(
    this._transport, {
    required String siteUrl,
    required this.apiKey,
    this.clientId,
  }) : _siteUrl = siteUrl,
       _site = requireSafeHttpUrl(
         Uri.parse(siteUrl.endsWith('/') ? siteUrl : '$siteUrl/'),
       );

  final DiscourseTransport _transport;
  final String _siteUrl;
  final Uri _site;
  final String? apiKey;
  final String? clientId;
  final Map<String, Cookie> _cookies = {};
  String? _csrf;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _cookies.clear();
    _csrf = null;
  }

  void _requireCurrent() {
    if (_disposed) throw const WriteException(WriteFailure.forbidden);
  }

  void _acceptCookies(http.Response response) {
    final header = response.headers['set-cookie'];
    if (header == null) return;
    for (final value in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      try {
        final cookie = Cookie.fromSetCookieValue(value.trim());
        final domain = cookie.domain
            ?.replaceFirst(RegExp(r'^\.'), '')
            .toLowerCase();
        final host = _site.host.toLowerCase();
        if (domain != null &&
            domain != host &&
            (InternetAddress.tryParse(host) != null ||
                !host.endsWith('.$domain'))) {
          continue;
        }
        if (cookie.secure && _site.scheme != 'https') continue;
        final maxAge = cookie.maxAge;
        final expired = maxAge != null
            ? maxAge <= 0
            : !(cookie.expires?.isAfter(DateTime.now().toUtc()) ?? true);
        if (expired) {
          _cookies.remove(cookie.name);
        } else {
          _cookies[cookie.name] = cookie;
        }
      } on FormatException {
        // A malformed optional cookie cannot replace the verified session.
      }
    }
  }

  Map<String, String> _headers(Uri url) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
    'X-CSRF-Token': ?_csrf,
    if (_cookies.isNotEmpty)
      'Cookie': [
        for (final cookie in _cookies.values)
          if (url.path.startsWith(cookie.path ?? '/'))
            '${cookie.name}=${cookie.value}',
      ].join('; '),
  };

  Future<void> _prepareAnonymousSession() async {
    if (apiKey != null || _csrf != null) return;
    final url = _site.resolve('session/csrf.json');
    final response = await _transport.send(
      http.Request('GET', url)..headers.addAll(_headers(url)),
    );
    _requireCurrent();
    final json = _decode(response);
    final token = jsonText(json['csrf']);
    if (token == null || token.isEmpty) {
      throw const WriteException(WriteFailure.unreachable);
    }
    _acceptCookies(response);
    _csrf = token;
  }

  Future<Map<String, dynamic>> _post(
    String suffix,
    Map<String, Object?> body,
  ) async {
    _requireCurrent();
    try {
      await _prepareAnonymousSession();
      _requireCurrent();
      final url = _site.resolve('dsa/report-illegal-content$suffix');
      final request = http.Request('POST', url)
        ..headers.addAll(_headers(url))
        ..body = jsonEncode(body);
      final key = apiKey;
      final response = key != null
          ? await _transport.sendAuthenticated(
              request,
              siteUrl: _siteUrl,
              apiKey: key,
              clientId: clientId,
            )
          : await _transport.send(request);
      _requireCurrent();
      final result = _decode(response);
      if (apiKey == null) _acceptCookies(response);
      return result;
    } on WriteException {
      rethrow;
    } catch (error, stackTrace) {
      throw WriteException(
        WriteFailure.unreachable,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final json = DiscourseTransport.decodeObjectOrEmpty(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return json;
    final errors = [
      for (final value in jsonArray(json['errors']))
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
    if (json['error_type'] == 'verification_required') {
      throw DsaVerificationRequired(errors: errors);
    }
    throw WriteException(
      switch (response.statusCode) {
        401 || 403 => WriteFailure.forbidden,
        429 => WriteFailure.rateLimited,
        _ when errors.isNotEmpty => WriteFailure.validation,
        _ => WriteFailure.unreachable,
      },
      statusCode: response.statusCode,
      errors: errors,
    );
  }

  @override
  Future<String> requestVerification(String email) async {
    final json = await _post('/verify-email', {'email': email});
    final token = jsonText(json['token']);
    if (token == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return token;
  }

  @override
  Future<void> verifyEmail(String email, String token, String code) async {
    await _post('/verify-code', {
      'email': email,
      'token': token,
      'verification_code': code,
    });
  }

  @override
  Future<String> submit(Map<String, Object?> notice, {String? token}) async {
    final json = await _post('', {'notice': notice, 'token': ?token});
    final reference = jsonText(json['reference']);
    if (reference == null || reference.isEmpty) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return reference;
  }
}
