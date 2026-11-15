import '../foundation/private_file_document.dart';
import 'site_outbox.dart';
import 'topic_reads_api.dart';

/// The post numbers of each topic whose read timings a site has not confirmed.
typedef PendingTopicReads = Map<int, List<int>>;

typedef TopicReadOutbox = SiteOutbox<PendingTopicReads>;

TopicReadOutbox createTopicReadOutbox(PrivateFileResolver file) =>
    TopicReadOutbox(
      file: file,
      codec: SiteOutboxCodec(
        encode: (pending) => {
          for (final entry in pending.entries) '${entry.key}': entry.value,
        },
        decode: (json) {
          if (json is! Map) return null;
          final pending = boundTopicReads({
            for (final entry in json.entries)
              if (int.tryParse('${entry.key}') case final topicId?
                  when topicId > 0 && entry.value is List)
                topicId: (entry.value as List).whereType<int>().where(
                  (post) => post > 0,
                ),
          });
          return pending.isEmpty ? null : pending;
        },
      ),
    );

/// The most topics one site keeps waiting. A reader this far behind an
/// unreachable site loses the read state of the topics read first.
const int maximumPendingTopics = 200;

/// Keeps the newest [maximumPendingTopics] topics, and of each the highest
/// post numbers one request can carry: the site moves a read position to the
/// highest post it is given, so those are the ones that restore it.
PendingTopicReads boundTopicReads(Map<int, Iterable<int>> pending) {
  final bounded = <int, List<int>>{};
  for (final entry in pending.entries) {
    final posts = entry.value.toSet().toList()..sort();
    if (posts.isEmpty) continue;
    bounded[entry.key] = List.unmodifiable(
      posts.length > TopicReadsApi.maximumPostsPerRequest
          ? posts.sublist(posts.length - TopicReadsApi.maximumPostsPerRequest)
          : posts,
    );
  }
  while (bounded.length > maximumPendingTopics) {
    bounded.remove(bounded.keys.first);
  }
  return bounded;
}
