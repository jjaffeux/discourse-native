import 'package:discourse_native/src/diagnostics/diagnostics_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Distinctive, and made only of characters every pattern's value class
/// accepts, so a shape that keeps it kept a credential rather than tripping
/// over the sentinel's own punctuation.
const _secret = 'Zt7SecretZz9';

/// The names the redactor's own patterns enumerate, in the spellings the wire
/// and this app's logs actually produce.
const _keys = [
  'authorization',
  'Authorization',
  'proxy-authorization',
  'cookie',
  'Set-Cookie',
  'x-api-key',
  'X-Api-Key',
  'api_key',
  'apiKey',
  'api-key',
  'access_token',
  'refresh_token',
  'auth_token',
  'token',
  'password',
  'passwd',
  'secret',
  'credential',
  'client_id',
  'client-secret',
  'ice-pwd',
  'ice_ufrag',
  'livekit_token',
  'turn-credential',
];

const _hosts = ['example.com', 'meta.discourse.org', 'localhost:4200'];

/// URLs, which [DiagnosticsRedactor.uri] must strip whether or not they parse.
List<String> _uriShapes({required String key, required String host}) {
  return [
    'https://$host/t/1?$key=$_secret',
    'https://$host/t/1?a=b&$key=$_secret&c=d',
    'https://$host/t/1#$key=$_secret',
    'https://user:$_secret@$host/latest.json',
    'https://$_secret@$host/latest.json',
    '//user:$_secret@$host/avatar.png',
    // A malformed escape: `Uri.parse` normalizes `%ZZ`, so a name validated
    // after normalization would be a different name than the one sent.
    'https://$host/t/1?%ZZ=$_secret',
    // A percent-encoded `=` inside what looks like a bare query name.
    'https://$host/t/1?a%3D$_secret=b',
    // Unparseable authorities: no part of one can be trusted to be a host.
    'https://user:$_secret@[::1]:99999/x',
    'https://user:$_secret@$host:not-a-port/x',
    // The terminating `@` past the retention limit, and a secret past it.
    'https://${'u' * 70000}:$_secret@$host/x',
    'https://$host/${'p' * 70000}?$key=$_secret',
    // Scheme case, a non-HTTP scheme, and a nested encoded URL.
    'HTTP://USER:$_secret@$host/X',
    'wss://user:$_secret@$host/message-bus',
    'https://$host/redirect?url=https%3A%2F%2Fuser%3A$_secret%40evil',
  ];
}

/// Prose: exception messages and stack frames, which is what actually reaches
/// [DiagnosticsRedactor.scrub].
List<String> _proseShapes({required String key, required String host}) {
  return [
    'GET /t/1.json?$key=$_secret HTTP/1.1',
    '$key: $_secret',
    '$key:$_secret',
    'Bearer $_secret',
    'Basic $_secret',
    'headers: {$key: $_secret}',
    '$key=$_secret',
    '"$key": "$_secret"',
    "'$key' : '$_secret'",
    '$key = $_secret;',
    'Set-Cookie: _t=$_secret; path=/; HttpOnly',
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIx$_secret.abcdefgh12345678',
    'connecting to $host with $key=$_secret and $key=$_secret',
  ];
}

void main() {
  // Diagnostics are exportable, and what makes that safe is that the strings
  // they retain have had credentials taken out of them. The suite has an
  // example per pattern; what it did not have is the statement those examples
  // are examples of — that across every name the patterns enumerate, in every
  // position they claim, nothing gets through. An alternation reordered or an
  // anchor tightened can lose one spelling while every example still passes.
  test('no shape the redactor claims lets a credential through', () {
    final survived = <String>{};
    var run = 0;

    for (final key in _keys) {
      for (final host in _hosts) {
        // Credentials arrive inside a sentence, not on their own.
        final prefix = run.isEven ? 'ClientException while sending ' : '';
        final suffix = run.isEven ? ' (attempt $run)' : '';

        for (final shape in _proseShapes(key: key, host: host)) {
          final scrubbed = DiagnosticsRedactor.scrub(
            '$prefix$shape$suffix',
            homeDirectory: '/Users/nobody',
          );
          if (scrubbed.contains(_secret)) survived.add(shape);
        }

        for (final shape in _uriShapes(key: key, host: host)) {
          if (DiagnosticsRedactor.uri(shape).contains(_secret)) {
            survived.add('uri: $shape');
          }
          final scrubbed = DiagnosticsRedactor.scrub(
            '$prefix$shape$suffix',
            homeDirectory: '/Users/nobody',
          );
          if (scrubbed.contains(_secret)) survived.add('scrub: $shape');
        }
        run++;
      }
    }

    expect(survived, isEmpty);
  });

  test('what is kept is still enough to tell two endpoints apart', () {
    final safe = DiagnosticsRedactor.uri(
      'https://user:$_secret@example.com/t/topic/1.json?page=2&api_key=$_secret',
    );

    expect(safe, 'https://example.com/t/topic/1.json?page&api_key');
  });
}
