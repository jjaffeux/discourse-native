import 'package:discourse_native/src/foundation/redacted_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes credentials, query values and fragments', () {
    expect(
      redactUri(
        'https://user:secret@example.com/path?token=private&name=value#private',
      ),
      'https://example.com/path?token&name',
    );
  });

  test('strips credentials before applying the length limit', () {
    final credential = 'private' * 12000;
    final result = redactUri(
      'https://$credential@example.com/path?token=private',
    );

    expect(result, 'https://example.com/path?token');
    expect(result, isNot(contains('private')));
  });

  test('does not retain a malformed authority or invalid query bytes', () {
    for (final uri in [
      'https://private:secret@host:invalid/path?token=private#private',
      '//private:secret@host:invalid/path?token=private#private',
      'https://example.com/?%FF=private',
    ]) {
      final result = redactUri(uri);
      expect(result, isNot(contains('private')));
      expect(result, isNot(contains('secret')));
    }
    expect(
      redactUri('https://example.com/?%FF=private'),
      'https://example.com/?invalid-query-name',
    );
  });
}
