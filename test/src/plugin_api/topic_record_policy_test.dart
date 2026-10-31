import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = PluginDataKey<_Record>(owner: 'reader-fixture', name: 'topic');
const _site = 'https://forum.example';

void main() {
  const registry = PluginRegistry([_Plugin()]);
  const models = DiscourseModelCodec(extensions: registry);

  test('detail mode changes do not erase authoritative list activity', () {
    final held = models
        .topicList({
          'topic_list': {
            'topics': [
              {'id': 1, 'alternate_reader': true, 'activity_pending': true},
            ],
          },
        }, _site)
        .topics
        .single;
    final detail = models.topicSummary({
      'id': 1,
      'alternate_reader': true,
    }, _site);
    final merged = held.merge(detail);

    expect(merged.readingPolicy.allowsChronologicalResume, isFalse);
    expect(merged.showNewRepliesDot, isTrue);
    expect(merged.showUnreadCount, isFalse);
    expect(merged.plugins.get(_key)!.activity, TopicActivityState.unread);
  });

  test('fresh detail omission can revoke a cached reader', () {
    final held = models.topicSummary({
      'id': 1,
      'alternate_reader': true,
    }, _site);
    final fresh = models.topicSummary({'id': 1}, _site);

    expect(held.readingPolicy.allowsChronologicalResume, isFalse);
    expect(held.merge(fresh).readingPolicy.allowsChronologicalResume, isTrue);
  });

  test('partial records neither revoke mode nor clear activity', () {
    final held = registry.readTopic(
      {'alternate_reader': true, 'activity_pending': true},
      _site,
      context: const TopicRecordDecodeContext.list(),
    );
    final partial = registry.readTopic({}, _site);
    final merged = partial.mergeTopicRecordsFrom(held);

    expect(merged.get(_key)!.enabled, isTrue);
    expect(merged.topicReadingPolicy.showsActivityDot, isTrue);
    expect(merged.markTopicRead().topicReadingPolicy.explicitReadState, isTrue);
  });

  test('list omission settles activity without erasing explicit mode', () {
    final held = registry.readTopic(
      {'alternate_reader': true, 'activity_pending': true},
      _site,
      context: const TopicRecordDecodeContext.list(),
    );
    final fresh = registry
        .readTopic(
          {'alternate_reader': true},
          _site,
          context: const TopicRecordDecodeContext.list(),
        )
        .mergeTopicRecordsFrom(held);

    expect(fresh.topicReadingPolicy.explicitReadState, isTrue);
    expect(fresh.topicReadingPolicy.showsActivityDot, isFalse);
  });

  test('declined policies do not conflict with a selected reader', () {
    const other = PluginDataKey<_Record>(owner: 'other', name: 'topic');
    final records = PluginData.none
        .withValue(_key, const _Record(false, TopicActivityState.unknown))
        .withValue(other, const _Record(true, TopicActivityState.unread));

    expect(records.topicReadingPolicy.showsActivityDot, isTrue);
  });

  test('conflicting reader policies cannot depend on record order', () {
    const other = PluginDataKey<_Record>(owner: 'other', name: 'topic');
    final records = PluginData.none
        .withValue(_key, const _Record(true, TopicActivityState.unread))
        .withValue(other, const _Record(true, TopicActivityState.caughtUp));

    expect(() => records.topicReadingPolicy, throwsStateError);
  });

  test('core-only decoding ignores another reader schema', () {
    const core = DiscourseModelCodec.core();
    final topic = core.topicSummary({
      'id': 1,
      'alternate_reader': true,
      'activity_pending': true,
      'last_read_post_number': 4,
    }, _site);
    expect(topic.plugins.isEmpty, isTrue);
    expect(topic.readingPolicy.allowsChronologicalResume, isTrue);
  });
}

final class _Plugin implements SitePlugin, TopicRecordPlugin<_Record> {
  const _Plugin();

  @override
  String get name => 'reader-fixture';
  @override
  PluginDataKey<_Record> get record => _key;

  @override
  _Record readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) => _Record(
    context.source == TopicRecordSource.partial
        ? null
        : json['alternate_reader'] == true,
    context.source == TopicRecordSource.list
        ? json['activity_pending'] == true
              ? TopicActivityState.unread
              : TopicActivityState.caughtUp
        : TopicActivityState.unknown,
  );
}

final class _Record implements TopicRecordValue, TopicReadingPolicyRecord {
  const _Record(this.enabled, this.activity);

  final bool? enabled;
  final TopicActivityState activity;

  @override
  Object mergeTopicRecord(Object? held) {
    final previous = held is _Record ? held : null;
    return _Record(
      enabled ?? previous?.enabled,
      activity == TopicActivityState.unknown
          ? previous?.activity ?? activity
          : activity,
    );
  }

  @override
  TopicReadingPolicy? get topicReadingPolicy =>
      enabled == true ? ActivityTopicReadingPolicy(activity: activity) : null;

  @override
  Object markTopicRead() => _Record(enabled, TopicActivityState.caughtUp);
}
