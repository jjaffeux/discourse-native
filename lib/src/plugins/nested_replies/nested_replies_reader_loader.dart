part of 'nested_replies_reader.dart';

final class NestedRepliesReaderLoader
    implements NestedRepliesLoader, NestedRepliesScopedLoader {
  const NestedRepliesReaderLoader({required this.reader, required this.api})
    : _current = null;
  const NestedRepliesReaderLoader._({
    required this.reader,
    required this.api,
    required this._current,
  });
  final PluginTopicReader reader;
  final NestedRepliesApi api;
  final bool Function()? _current;

  @override
  bool get isCurrent => reader.isCurrent && (_current?.call() ?? true);

  @override
  NestedRepliesLoader scoped(bool Function() current) =>
      NestedRepliesReaderLoader._(
        reader: reader,
        api: api,
        current: () => isCurrent && current(),
      );

  Future<NestedPageReceipt<T>?> _ingest<T>(
    Future<T> Function(PluginRequestCredentials request) load,
    Iterable<NestedPostPayload> Function(T page) posts, {
    Map<String, dynamic>? Function(T page)? metadata,
    int? Function(T page)? cursor,
    Map<String, dynamic>? Function(T page)? recommendations,
  }) async {
    if (!isCurrent) return null;
    final result = await reader.ingest((request) async {
      final page = await load(request);
      if (!isCurrent) throw StateError('Reader request was superseded.');
      final held = reader.topic;
      final json = metadata?.call(page);
      final related = recommendations?.call(page);
      final detail = held == null
          ? null
          : json == null
          ? related == null
                ? null
                : held.copyWith(
                    recommendations: reader.models.topicRecommendations(
                      related,
                      reader.siteUrl,
                    ),
                  )
          : reader.models
                .topicMetadata(
                  {...json, ...?related},
                  reader.siteUrl,
                  held: held,
                )
                .copyWith(messageBusLastId: cursor?.call(page));
      return TopicContentResult(
        value: page,
        metadata: detail,
        posts: posts(page).map(
          (payload) => TopicContentPost(
            payload.post,
            disposition: payload.redacted
                ? TopicContentDisposition.redacted
                : TopicContentDisposition.complete,
          ),
        ),
      );
    });
    return result == null
        ? null
        : NestedPageReceipt(
            value: result.value,
            acceptedPostIds: result.postIds,
          );
  }

  @override
  Future<NestedPageReceipt<NestedRootPage>?> roots({
    required NestedRepliesSort sort,
    required int page,
    required bool trackVisit,
  }) => _ingest(
    (request) => api.roots(
      siteUrl: reader.siteUrl,
      topicId: reader.topicId,
      slug: reader.route.slug ?? 'topic',
      credentials: request,
      sort: sort,
      page: page,
      trackVisit: trackVisit && reader.foreground && reader.isConnected,
    ),
    (page) => page.posts,
    metadata: (page) => page.topicMetadata == null
        ? null
        : {...page.topicMetadata!, 'pinned_post_ids': page.pinnedPostIds},
    cursor: (page) => page.messageBusLastId,
    recommendations: (page) => page.recommendations,
  );

  @override
  Future<NestedPageReceipt<NestedContextPage>?> context({
    required NestedRepliesSort sort,
    required int postNumber,
    required int? contextDepth,
    required bool trackVisit,
  }) => _ingest(
    (request) => api.context(
      siteUrl: reader.siteUrl,
      topicId: reader.topicId,
      slug: reader.route.slug ?? 'topic',
      credentials: request,
      sort: sort,
      postNumber: postNumber,
      contextDepth: contextDepth,
      trackVisit: trackVisit && reader.foreground && reader.isConnected,
    ),
    (page) => page.posts,
    metadata: (page) => page.topicMetadata,
    cursor: (page) => page.messageBusLastId,
    recommendations: (page) => page.recommendations,
  );

  @override
  Future<NestedPageReceipt<NestedChildrenPage>?> children({
    required NestedRepliesSort sort,
    required int parentPostNumber,
    required int depth,
    required int page,
  }) => _ingest(
    (request) => api.children(
      siteUrl: reader.siteUrl,
      topicId: reader.topicId,
      slug: reader.route.slug ?? 'topic',
      credentials: request,
      sort: sort,
      parentPostNumber: parentPostNumber,
      depth: depth,
      page: page,
    ),
    (page) => page.posts,
  );
}
