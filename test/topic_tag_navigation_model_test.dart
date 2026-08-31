import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/tag_sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  group('topic tag destinations', () {
    test('keeps public route identities and encodes slugs once', () {
      final identified = buildTopicTagDestination(
        const TopicTag(
          id: 7,
          name: 'quality / 100%',
          slug: 'quality%20%2F%20100%25',
        ),
      )!;
      final idless = buildTopicTagDestination(
        const TopicTag(name: 'quality / 100%', slug: 'quality%20%2F%20100%25'),
      )!;

      expect(identified.id, 'tag-7');
      expect(identified.feedPath, '/tag/quality%20%2F%20100%25/7.json');
      expect(idless.id, 'list-/tag/quality%20%2F%20100%25.json');
      expect(idless.feedPath, '/tag/quality%20%2F%20100%25.json');
    });

    test('uses the private-message tag endpoint for either PM signal', () {
      final fromTopic = buildTopicTagDestination(
        const TopicTag(id: 8, name: 'priority / private'),
        username: 'sam name',
        privateMessage: true,
      )!;
      final pmOnly = buildTopicTagDestination(
        const TopicTag(id: 8, name: 'priority / private', pmOnly: true),
        username: 'sam name',
      )!;
      final public = buildTopicTagDestination(
        const TopicTag(id: 8, name: 'priority / private'),
      )!;

      expect(fromTopic.id, 'pm-tag-8');
      expect(pmOnly.id, 'pm-tag-8');
      expect(public.id, 'tag-8');
      expect(fromTopic.id, isNot(public.id));
      expect(
        fromTopic.feedPath,
        '/topics/private-messages-tags/'
        'sam%20name/priority%20%2F%20private.json',
      );
      expect(pmOnly.feedPath, fromTopic.feedPath);
      expect(
        buildTopicTagDestination(const TopicTag(name: 'private', pmOnly: true)),
        isNull,
      );
    });
  });

  group('private-message topic state', () {
    test('parses and preserves the topic-list archetype', () {
      final topic = Topic.fromJson(
        const {
          'id': 7,
          'title': 'A private topic',
          'slug': 'a-private-topic',
          'archetype': 'private_message',
        },
        const {},
        _siteUrl,
      );

      expect(topic.privateMessage, isTrue);
      expect(topic.copyWith(title: 'Renamed').privateMessage, isTrue);
      expect(
        topic,
        isNot(
          const Topic(id: 7, title: 'A private topic', slug: 'a-private-topic'),
        ),
      );
    });

    test('parses and preserves the topic-detail archetype', () {
      final topic = TopicDetail.parse(const {
        'id': 7,
        'title': 'A private topic',
        'archetype': 'private_message',
        'post_stream': {'stream': <int>[], 'posts': <Object>[]},
      }, _siteUrl).detail;

      expect(topic.privateMessage, isTrue);
      expect(topic.copyWith(title: 'Renamed').privateMessage, isTrue);
      expect(
        topic,
        isNot(const TopicDetail(id: 7, title: 'A private topic', stream: [])),
      );
    });

    test('parses a PM-only topic tag without serializing routing metadata', () {
      final tag = TopicTag.parse(const {
        'id': 8,
        'name': 'priority',
        'slug': 'priority',
        'pm_only': true,
      })!;

      expect(tag.pmOnly, isTrue);
      expect(tag.toJson(), {'id': 8, 'name': 'priority'});
    });
  });
}
