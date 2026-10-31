import 'package:discourse_native/discourse_plugin_sdk.dart';

const activityPolicyKey = PluginDataKey<ActivityPolicyFixture>(
  owner: 'activity-fixture',
  name: 'topic',
);

PluginData activityTopicData([
  TopicActivityState activity = TopicActivityState.unread,
]) => PluginData.none.withValue(
  activityPolicyKey,
  ActivityPolicyFixture(activity),
);

final class ActivityPolicyFixture implements TopicReadingPolicyRecord {
  const ActivityPolicyFixture(this.activity);

  final TopicActivityState activity;

  @override
  TopicReadingPolicy get topicReadingPolicy =>
      ActivityTopicReadingPolicy(activity: activity);

  @override
  Object markTopicRead() =>
      const ActivityPolicyFixture(TopicActivityState.caughtUp);
}
