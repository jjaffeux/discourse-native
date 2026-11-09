import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'post_voting_data.dart';
import 'post_voting_services.dart';

Map<String, String> postVotingQuery(String? query) {
  try {
    return Uri(query: query).queryParameters;
  } on FormatException {
    return const {};
  }
}

final class PostVotingController extends FrameSafeNotifier {
  PostVotingController({
    required this.reader,
    required this.services,
    this.beforeRefresh,
  }) {
    _epoch = services.actions.epochFor(reader.siteUrl);
    final query = postVotingQuery(reader.route.topicQuery);
    order = query['filter'] == 'activity'
        ? PostVotingOrder.activity
        : PostVotingOrder.votes;
    final requested = reader.route.postNumber;
    nearPostNumber = requested == TopicLink.lastPostNumber
        ? reader.topic?.highestPostNumber
        : requested;
    if (requested == null && !query.containsKey('post-voting-sort')) {
      final read = reader.topic?.lastReadPostNumber;
      final highest = reader.topic?.highestPostNumber;
      if (read != null && highest != null && highest > read) {
        nearPostNumber = read + 1;
        if (highest - read > 1) order = PostVotingOrder.activity;
      } else if (read != null && highest != null && read >= highest) {
        nearPostNumber = 1;
      }
    }
    _events = reader.topicEvents.listen(_event);
    reader.addListener(_readerChanged);
    services.addListener(_serviceChanged);
  }
  final PluginTopicReader reader;
  final PostVotingServices services;
  final void Function()? beforeRefresh;
  late PostVotingOrder order;
  int? nearPostNumber;
  List<int> orderedIds = const [];
  final Set<int> loadedIds = {};
  final Set<int> _unavailable = {};
  final Set<int> _dirtyComments = {};
  bool loading = false, loadingMore = false, rankDirty = false;
  Object? error;
  int _generation = 0;
  late final int _epoch;
  StreamSubscription<Object?>? _events;
  bool _wasForeground = false;

  bool get current =>
      !isDisposed &&
      services.actions.available(reader) &&
      _epoch == services.actions.epochFor(reader.siteUrl);
  List<int> _missing({bool earlier = false}) {
    final answers = orderedIds
        .where((id) => reader.post(id)?.postNumber != 1)
        .toList();
    final held = answers.where(loadedIds.contains).toList();
    if (held.isEmpty) {
      return earlier
          ? const []
          : answers.where((id) => !_unavailable.contains(id)).toList();
    }
    final boundary = answers.indexOf(held.first);
    final range = earlier ? answers.take(boundary) : answers.skip(boundary);
    final missing = range
        .where((id) => !loadedIds.contains(id) && !_unavailable.contains(id))
        .toList();
    return earlier && missing.length > 20
        ? missing.sublist(missing.length - 20)
        : missing;
  }

  bool get hasMore => _missing().isNotEmpty;
  bool get hasEarlier => _missing(earlier: true).isNotEmpty;
  List<int> get visibleIds => [
    for (final id in orderedIds)
      if (loadedIds.contains(id) && reader.post(id) != null) id,
  ];
  int? get questionId =>
      visibleIds.where((id) => reader.post(id)?.postNumber == 1).firstOrNull;
  List<int> get answerIds =>
      visibleIds.where((id) => id != questionId).toList(growable: false);

  Future<void> initialize() async {
    _wasForeground = reader.foreground;
    final memory = services.memory(reader, order);
    if (memory != null) {
      orderedIds = memory.ids;
      loadedIds.addAll(memory.loadedIds.where((id) => reader.post(id) != null));
      notifySafely();
    }
    await refresh();
  }

  Future<void> refresh({FutureOr<void> Function()? beforeApply}) async {
    if (!current || loading) return;
    beforeRefresh?.call();
    final generation = ++_generation;
    final requestedOrder = order;
    loading = true;
    loadingMore = false;
    error = null;
    notifySafely();
    try {
      final receipt = await reader.ingest((credentials) async {
        final window = await services.api.loadWindow(
          siteUrl: reader.siteUrl,
          topicId: reader.topicId,
          order: requestedOrder,
          credentials: credentials,
          nearPostNumber: nearPostNumber,
          heldTopic: reader.topic,
        );
        if (!current || generation != _generation) {
          throw StateError('Superseded reader request.');
        }
        return TopicContentResult(
          value: window,
          posts: window.posts,
          metadata: window.metadata,
        );
      });
      if (!current || receipt == null || generation != _generation) return;
      await beforeApply?.call();
      if (!current || generation != _generation) return;
      orderedIds = receipt.value.orderedStreamIds;
      loadedIds.removeWhere((id) => !orderedIds.contains(id));
      loadedIds.addAll(receipt.postIds);
      _unavailable.clear();
      rankDirty = false;
      final question = orderedIds.firstOrNull;
      if (question != null && !loadedIds.contains(question)) {
        await _load([question], generation);
      }
      final query = {...postVotingQuery(reader.route.topicQuery)};
      if (order == PostVotingOrder.activity) {
        query['filter'] = 'activity';
      } else {
        query.remove('filter');
      }
      reader.updateQuery(
        query.isEmpty ? null : Uri(queryParameters: query).query,
      );
      if (reader.foreground) unawaited(reader.reconcileVisit());
    } catch (failure) {
      if (current && generation == _generation) error = failure;
    } finally {
      if (!isDisposed && generation == _generation) {
        loading = false;
        notifySafely();
      }
    }
  }

  Future<void> _load(List<int> ids, int generation) async {
    final receipt = await reader.ingest((credentials) async {
      final posts = await services.api.loadPosts(
        siteUrl: reader.siteUrl,
        topicId: reader.topicId,
        postIds: ids,
        order: order,
        credentials: credentials,
      );
      if (!current || generation != _generation) {
        throw StateError('Superseded post batch.');
      }
      return TopicContentResult(value: ids, posts: posts);
    });
    if (!current || receipt == null || generation != _generation) return;
    loadedIds.addAll(receipt.postIds);
    _unavailable.addAll(ids.where((id) => !receipt.postIds.contains(id)));
  }

  Future<void> loadMore({bool earlier = false}) async {
    if (!current ||
        loading ||
        loadingMore ||
        !(earlier ? hasEarlier : hasMore)) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    error = null;
    notifySafely();
    try {
      await _load(_missing(earlier: earlier).take(20).toList(), generation);
    } catch (failure) {
      if (current && generation == _generation) error = failure;
    } finally {
      if (!isDisposed && generation == _generation) {
        loadingMore = false;
        notifySafely();
      }
    }
  }

  Future<void> changeOrder(PostVotingOrder value) async {
    if (!current || order == value) return;
    final heldOrder = order,
        heldQuery = reader.route.topicQuery,
        heldNear = nearPostNumber;
    final heldIds = orderedIds,
        heldLoaded = Set<int>.of(loadedIds),
        heldUnavailable = Set<int>.of(_unavailable);
    ++_generation;
    order = value;
    loading = false;
    loadingMore = false;
    final query = {
      ...postVotingQuery(reader.route.topicQuery),
      'post-voting-sort': value.name,
    };
    if (value == PostVotingOrder.activity) {
      query['filter'] = 'activity';
    } else {
      query.remove('filter');
    }
    if (!reader.updateQuery(Uri(queryParameters: query).query)) return;
    nearPostNumber = 1;
    await refresh();
    if (current && order == value && error != null) {
      order = heldOrder;
      nearPostNumber = heldNear;
      orderedIds = heldIds;
      loadedIds
        ..clear()
        ..addAll(heldLoaded);
      _unavailable
        ..clear()
        ..addAll(heldUnavailable);
      reader.updateQuery(heldQuery);
      notifySafely();
    }
  }

  void _readerChanged() {
    if (!current) {
      notifySafely();
      return;
    }
    if (reader.foreground && !_wasForeground) {
      unawaited(refresh());
      for (final id in visibleIds) {
        if ((services.actions
                .record(reader.siteUrl, id)
                ?.initialComments
                ?.isNotEmpty ??
            false)) {
          _dirtyComments.add(id);
        }
      }
      _drainComments();
    }
    _wasForeground = reader.foreground;
    notifySafely();
  }

  void _serviceChanged() {
    if (current) {
      _drainComments();
      notifySafely();
    }
  }

  void _drainComments() {
    if (!reader.foreground) return;
    for (final id in _dirtyComments.toList()) {
      if (services.actions.commentState(reader.siteUrl, id).pending) continue;
      _dirtyComments.remove(id);
      unawaited(_refreshComments(id));
    }
  }

  Future<void> _refreshComments(int id) async {
    try {
      final batch = await services.actions.loadComments(reader, id);
      if (batch != null) {
        services.actions.publishComments(
          reader,
          id,
          batch.comments,
          total: batch.comments.length,
        );
      }
    } catch (_) {
      if (current) _dirtyComments.add(id);
    }
  }

  void _event(Object? value) {
    if (!current || value is! Map) return;
    final type = value['type'];
    if (type == 'post_voting_post_voted') {
      services.actions.votedEvent(reader, value);
      rankDirty = true;
      notifySafely();
      return;
    }
    const commentChanges = {
      'post_voting_post_commented',
      'post_voting_post_comment_edited',
      'post_voting_post_comment_trashed',
    };
    if (commentChanges.contains(type)) {
      final id = value['id'];
      if (id is int && reader.post(id) != null) {
        services.actions.invalidateComments(reader.siteUrl, id);
        final total = value['comments_count'];
        if (total is int && total >= 0) {
          final held = services.actions.record(reader.siteUrl, id);
          if (held != null) {
            services.actions.publishComments(
              reader,
              id,
              held.initialComments ?? const [],
              total: total,
            );
          }
        }
        _dirtyComments.add(id);
        _drainComments();
      }
      return;
    }
    if (const {
          'created',
          'revised',
          'rebaked',
          'deleted',
          'destroyed',
          'recovered',
          'acted',
          'liked',
          'unliked',
        }.contains(type) ||
        value['reload_topic'] == true) {
      rankDirty = true;
      notifySafely();
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_events?.cancel());
    reader.removeListener(_readerChanged);
    services.removeListener(_serviceChanged);
    super.dispose();
  }
}
