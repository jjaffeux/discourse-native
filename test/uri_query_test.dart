import 'package:discourse_native/src/foundation/uri_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final query in [
    '',
    'tag=one&tag=two&flag&blank=',
    '=value&=two&key=a=b&&',
    'title=caf%C3%A9&space=one+two&encoded=a%26b%3Dc&plus=%2B',
  ]) {
    test('valid query retains standard decoding for $query', () {
      final uri = Uri.parse('https://example.test/?$query');
      expect(validUriQueryParameters(uri), uri.queryParametersAll);
    });
  }

  for (final invalid in ['%FF', '%C0%AF', '%E2%82', '%ED%A0%80']) {
    test('drops malformed pairs independently for $invalid', () {
      final uri = Uri.parse(
        'https://example.test/?tag=one&bad=$invalid&tag=two&$invalid=bad'
        '&flag&blank=&=value&unicode=caf%C3%A9&space=one+two&encoded=a%26b%3Dc',
      );
      expect(validUriQueryParameters(uri), {
        'tag': ['one', 'two'],
        'flag': [''],
        'blank': [''],
        '': ['value'],
        'unicode': ['café'],
        'space': ['one two'],
        'encoded': ['a&b=c'],
      });
    });
  }
}
