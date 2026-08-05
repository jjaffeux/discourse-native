@Tags(['live'])
library;

import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => HttpOverrides.global = null);

  test('resolves meta.discourse.org for real', () async {
    final site = await DiscourseApi().lookup('meta.discourse.org');
    // ignore: avoid_print
    print('RESOLVED: ${site.toJson()}');
    expect(site.url, 'https://meta.discourse.org');
    expect(site.apiVersion, greaterThanOrEqualTo(2));
  });

  test('follows the http -> https redirect', () async {
    final site = await DiscourseApi().lookup('http://meta.discourse.org');
    // ignore: avoid_print
    print('REDIRECTED TO: ${site.url}');
    expect(site.url, 'https://meta.discourse.org');
  });

  liveAuthUrl();

  test('rejects a non-Discourse host', () async {
    await expectLater(
      DiscourseApi().lookup('example.com'),
      throwsA(isA<SiteLookupException>()),
    );
  });
}

/// Confirms a real Discourse accepts the handshake parameters we send —
/// notably that our PEM encoding and scope list are ones it will parse.
void liveAuthUrl() {
  test('meta accepts our user-api-key request', () async {
    final pair = AuthKeyPair.generate();
    final url = const UserApiKeyProtocol().authUrl(
      siteUrl: 'https://meta.discourse.org',
      publicKeyPem: pair.publicPem,
      nonce: SecureStore.randomToken(),
      clientId: SecureStore.randomToken(),
      applicationName: 'Discourse Native (test)',
    );

    final client = HttpClient();
    final request = await client.getUrl(url);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    // Signed out, Discourse stashes the destination and sends us to /login.
    // A 400/403 would mean it rejected our parameters.
    // ignore: avoid_print
    print('AUTH URL STATUS: ${response.statusCode} -> '
        '${response.headers.value('location')}');
    expect(response.statusCode, anyOf(200, 302));
    expect(response.statusCode, isNot(403));
  });
}
