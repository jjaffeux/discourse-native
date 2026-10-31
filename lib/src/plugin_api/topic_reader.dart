import 'package:flutter/widgets.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/site_config.dart';
import 'core_plugin_host.dart';
import 'discourse_model_codec.dart';
import 'plugin_manifest.dart';

abstract interface class PluginTopicReaderHost {
  PluginTopicReader? forVisibleTopic(String siteUrl, int topicId);
}

const corePluginTopicReaderPort = PluginHostPortKey<PluginTopicReaderHost>(
  owner: PluginId('core'),
  name: 'topic-reader',
);

@immutable
final class TopicReaderProbe {
  const TopicReaderProbe({
    required this.siteUrl,
    required this.topic,
    required this.config,
  });

  final String siteUrl;
  final TopicDetail topic;
  final SiteConfig config;
}

/// Selection is synchronous and has no network or presentation side effects.
abstract interface class TopicReaderPlugin {
  bool readsTopic(TopicReaderProbe probe);
  Widget buildTopicReader(BuildContext context, PluginTopicReader reader);
}

enum TopicPostLayout { standard, compact, headerOnly }

enum TopicContentDisposition { complete, redacted }

@immutable
final class TopicContentPost {
  const TopicContentPost(
    this.post, {
    this.disposition = TopicContentDisposition.complete,
  });

  final Post post;
  final TopicContentDisposition disposition;
}

/// Metadata never establishes chronological stream membership.
@immutable
final class TopicContentResult<T> {
  TopicContentResult({
    required this.value,
    Iterable<TopicContentPost> posts = const [],
    this.metadata,
  }) : posts = List.unmodifiable(posts);

  final T value;
  final List<TopicContentPost> posts;
  final TopicDetail? metadata;
}

@immutable
final class AcceptedTopicContent<T> {
  AcceptedTopicContent({
    required this.value,
    required Iterable<int> postIds,
    required this.revision,
  }) : postIds = Set.unmodifiable(postIds);

  final T value;
  final Set<int> postIds;
  final int revision;
}

/// An original-account, original-tab handle. It cannot acquire another lease.
abstract interface class PluginTopicReader implements Listenable {
  void close();
  String get siteUrl;
  String get tabId;
  int get topicId;
  ContentRoute get route;
  bool get isCurrent;
  bool get foreground;
  bool get isConnected;
  TopicDetail? get topic;
  int? get currentUserId;
  bool get currentUserStaff;
  DiscourseModelCodec get models;
  Post? post(int postId);

  Future<AcceptedTopicContent<T>?> ingest<T>(
    Future<TopicContentResult<T>> Function(PluginRequestCredentials request)
    read,
  );

  void reply({int? parentPostNumber, String? username});
  void edit(int postId);
  void navigate({int? postNumber, String? query, bool replace = false});
  Future<void> observeVisible(Iterable<int> postNumbers);
  Future<void> reconcileVisit();
  Future<void> refreshMetadata();
  void setVisiblePostIds(Iterable<int> postIds);

  /// Events belong to this topic. The transport and reserved channel stay core-owned.
  Stream<Object?> get topicEvents;
}
