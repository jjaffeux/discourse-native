import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import 'plugin_data.dart';

/// Constructs core wire models with one explicitly installed extension decoder.
///
/// Keeping this object at the composition boundary lets core-only builds use an
/// empty decoder and prevents model factories from reaching a process-global
/// plugin registry.
final class DiscourseModelCodec {
  const DiscourseModelCodec({required this.extensions});

  const DiscourseModelCodec.core()
    : extensions = const EmptyPluginDataDecoder();

  final PluginDataDecoder extensions;

  Post post(Map<String, dynamic> json, String siteUrl) =>
      Post.fromJson(json, siteUrl, extensions: extensions);

  TopicList topicList(Map<String, dynamic> json, String siteUrl) =>
      TopicList.fromJson(json, siteUrl, extensions: extensions);

  TopicPayload topic(Map<String, dynamic> json, String siteUrl) =>
      TopicDetail.parse(json, siteUrl, extensions: extensions);

  UserCard userCard(Map<String, dynamic> json, String siteUrl) =>
      UserCard.fromJson(json, siteUrl, extensions: extensions);

  PostCreation postCreation(Map<String, dynamic> json, String siteUrl) =>
      PostCreation.fromJson(json, siteUrl, extensions: extensions);

  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) => extensions.mergeAfterPostEdit(held: held, incoming: incoming);
}
