import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing IDs require the selected name, ignoring case', () {
    const unrelated = TopicTag(name: 'unrelated');
    const allowed = TopicTag(name: 'Selected');
    const result = TopicTagSearch(tags: [unrelated, allowed]);
    expect(
      result.allowedMatch(const TopicTag(name: 'SELECTED')),
      same(allowed),
    );
    expect(result.allowedMatch(const TopicTag(name: 'absent')), isNull);
  });

  test('an explicit ID retains identity across a rename', () {
    const renamed = TopicTag(id: 7, name: 'renamed');
    const result = TopicTagSearch(tags: [renamed]);
    expect(
      result.allowedMatch(const TopicTag(id: 7, name: 'old')),
      same(renamed),
    );
  });

  test('route matching accepts a slug alias and explicit renamed identity', () {
    const unrelated = TopicTag(name: 'unrelated');
    const alias = TopicTag(id: 7, name: 'Display name', slug: 'route-name');
    const result = TopicTagSearch(tags: [unrelated, alias]);
    expect(result.allowedRouteMatch(slug: 'ROUTE-NAME'), same(alias));
    expect(result.allowedRouteMatch(id: 7, slug: 'old-name'), same(alias));
    expect(result.allowedRouteMatch(slug: 'absent'), isNull);
    const blocked = TopicTagSearch(tags: [alias], forbidden: true);
    expect(blocked.allowedRouteMatch(slug: 'route-name'), isNull);
    const disabled = TopicTagSearch(
      tags: [
        TopicTag(name: 'Display name', slug: 'route-name', disabled: true),
        alias,
      ],
    );
    expect(disabled.allowedRouteMatch(slug: 'route-name'), isNull);
  });

  test('forbidden and disabled first matches cannot become eligible', () {
    const selected = TopicTag(id: 7, name: 'selected');
    const forbidden = TopicTagSearch(tags: [selected], forbidden: true);
    expect(forbidden.allowedMatch(selected), isNull);
    const disabled = TopicTagSearch(
      tags: [
        TopicTag(id: 7, name: 'selected', disabled: true),
        TopicTag(name: 'selected'),
      ],
    );
    expect(disabled.allowedMatch(selected), isNull);
  });
}
