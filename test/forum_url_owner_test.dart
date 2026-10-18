import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({int index, String forum})? owner(List<String> sites, String url) =>
      mostSpecificServingForum(sites, Uri.parse(url), siteUrl: (site) => site);

  test('chooses the deepest forum independently of rail order', () {
    const root = 'https://example.com';
    const forum = '$root/forum';
    const nested = '$forum/nested';
    for (final sites in [
      [root, forum, nested],
      [nested, root, forum],
      [forum, nested, root],
    ]) {
      final before = List.of(sites);
      final found = owner(sites, '$nested/t/topic/42');
      expect(found?.forum, nested);
      expect(found?.index, sites.indexOf(nested));
      expect(sites, before);
      expect(owner(sites, nested)?.forum, nested);
      expect(owner(sites, '$forum/t/topic/42')?.forum, forum);
      expect(owner(sites, '$root/t/topic/42')?.forum, root);
    }
  });

  test('matches decoded segments without merging encoded slashes', () {
    const root = 'https://example.com';
    const sites = [root, '$root/my%20forum', '$root/a/b', '$root/a%2Fb'];
    expect(owner(sites, '$root/my%20forum/t/topic/42')?.index, 1);
    expect(owner(sites, '$root/a%2Fb/t/topic/42')?.index, 3);
    expect(owner(sites, '$root/a/b/t/topic/42')?.index, 2);
    expect(owner(sites, '$root/my%20forums/t/topic/42')?.index, 0);
  });

  test('keeps the first equally specific decoded spelling', () {
    const encoded = 'https://example.com/f%6Frum';
    const plain = 'https://example.com/forum/';
    for (final sites in [
      [encoded, plain],
      [plain, encoded],
    ]) {
      expect(owner(sites, 'https://example.com/forum/t/topic/42')?.index, 0);
    }
  });

  test('keeps serving authority, port and scheme semantics', () {
    const sites = [
      'https://example.com',
      'https://example.com:8443/forum',
      'https://other.example/forum',
    ];
    expect(owner(sites, 'https://example.com:8443/forum/t/topic/42')?.index, 1);
    expect(owner(sites, 'https://other.example/forum/t/topic/42')?.index, 2);
    expect(owner(sites, 'http://example.com/t/topic/42')?.index, 0);
    expect(owner(sites, 'https://example.com:8444/forum/t/topic/42'), isNull);
    expect(owner(sites, '/forum/t/topic/42'), isNull);
  });

  test('refuses unreadable UTF-8 in target and candidate paths', () {
    const root = 'https://example.com';
    expect(owner([root, '$root/%FF'], '$root/%FF/t/topic/42'), isNull);
    expect(owner(['$root/%FF', root], '$root/forum/t/topic/42')?.index, 1);
    expect(owner([root], '$root/forum/%FF'), isNull);
  });

  test('has no owner without a serving forum', () {
    expect(owner([], 'https://example.com/t/topic/42'), isNull);
    expect(owner(['https://other.example'], 'https://example.com'), isNull);
    expect(
      owner(['https://example.com/forum'], 'https://example.com/forums'),
      isNull,
    );
  });
}
