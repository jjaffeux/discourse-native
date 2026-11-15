import 'package:discourse_native/src/data/link_open_request.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_test/flutter_test.dart';

String _request(String target) =>
    'discourse://open?url=${Uri.encodeQueryComponent(target)}';

void main() {
  test('the open action cannot be mistaken for the sign-in callback', () {
    expect(linkOpenScheme, UserApiKeyProtocol.redirectScheme);
    expect(linkOpenHost, isNot(UserApiKeyProtocol.redirectHost));
    expect(
      parseLinkOpenRequest(
        '${UserApiKeyProtocol.redirectUrl}?url=https%3A%2F%2Fone.example%2Ft%2F42',
      ),
      isNull,
    );
    expect(
      () => const UserApiKeyProtocol().payloadFromCallback(
        _request('https://one.example/t/42'),
      ),
      throwsA(isA<UserApiAuthException>()),
    );
  });

  for (final target in const [
    'https://one.example/t/slug/42/3',
    'https://one.example/forum/t/42?view=first&token=a',
    'https://one.example:8443/c/support/5#heading',
    'http://localhost:4200/t/dev/7',
    'http://127.0.0.1:3000/latest',
  ]) {
    test('accepts $target', () {
      expect(parseLinkOpenRequest(_request(target)), Uri.parse(target));
    });
  }

  test('accepts a trailing slash and an upper-case action', () {
    expect(
      parseLinkOpenRequest('DISCOURSE://OPEN/?url=https%3A%2F%2Fone.example'),
      Uri.parse('https://one.example'),
    );
  });

  final malformed = <String, String>{
    'an empty request': '',
    'another scheme': 'https://open?url=https%3A%2F%2Fone.example',
    'another action': 'discourse://add?url=https%3A%2F%2Fone.example',
    'a path on the action':
        'discourse://open/t/42?url=https%3A%2F%2Fone.example',
    'credentials on the action':
        'discourse://user@open?url=https%3A%2F%2Fone.example',
    'a port on the action': 'discourse://open:1?url=https%3A%2F%2Fone.example',
    'a fragment on the action':
        'discourse://open?url=https%3A%2F%2Fone.example#x',
    'no page': 'discourse://open',
    'an empty page': 'discourse://open?url=',
    'two pages':
        'discourse://open?url=https%3A%2F%2Fone.example&url=https%3A%2F%2Ftwo.example',
    'an extra parameter':
        'discourse://open?url=https%3A%2F%2Fone.example&payload=x',
    'a misnamed parameter': 'discourse://open?URL=https%3A%2F%2Fone.example',
    'a broken escape': 'discourse://open?url=https%3A%2F%2Fone.example%zz',
    'an invalid UTF-8 escape':
        'discourse://open?url=https%3A%2F%2Fone.example%ff',
    'a nested open action': _request(_request('https://one.example/t/42')),
    'a sign-in callback as the page': _request(
      'discourse://auth_redirect?payload=x',
    ),
    'a javascript page': _request('javascript:alert(1)'),
    'a file page': _request('file:///etc/passwd'),
    'a data page': _request('data:text/html,<p>x</p>'),
    'an intent page': _request('intent://one.example#Intent;scheme=https;end'),
    'a relative page': _request('/t/42'),
    'a scheme-relative page': _request('//one.example/t/42'),
    'a page without an authority': _request('https:one.example/t/42'),
    'a page without a host': _request('https:///t/42'),
    'credentials in the page': _request(
      'https://reader:secret@one.example/t/42',
    ),
    'a host disguised as credentials': _request(
      'https://one.example@evil.example/t/42',
    ),
    'a backslash before the real host': _request(
      r'https://one.example\@evil.example/t/42',
    ),
    'whitespace in the page': _request('https://one.example/t/42 '),
    'a line break in the page': _request('https://one.example/t/42\nHost: x'),
    'a control character in the page': _request('https://one.example/\u0000'),
    'a non-ASCII host': _request('https://оne.example/t/42'),
    'plaintext to a remote host': _request('http://one.example/t/42'),
    'plaintext to an ambiguous loopback': _request('http://127.1/t/42'),
    'an out-of-range port': _request('https://one.example:70000/t/42'),
    'a page beyond the length bound': _request(
      'https://one.example/${'a' * maximumLinkOpenTargetLength}',
    ),
    'a request beyond the length bound':
        'discourse://open?url=https%3A%2F%2Fone.example%2F${'%61' * maximumLinkOpenRequestLength}',
  };
  malformed.forEach((name, request) {
    test('rejects $name', () {
      expect(parseLinkOpenRequest(request), isNull);
    });
  });
}
