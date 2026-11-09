import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'post_voting_actions.dart';
import 'post_voting_api.dart';
import 'post_voting_data.dart';

const postVotingServicesKey = PluginServiceKey<PostVotingServices>(
  owner: postVotingPluginId,
  name: 'services',
);

typedef _Watch = ({
  PluginSiteLease lease,
  Listenable? settings,
  VoidCallback changed,
});

final class PostVotingViewSnapshot {
  PostVotingViewSnapshot({
    required Iterable<int> ids,
    required Iterable<int> loadedIds,
    required this.order,
    this.anchorId,
    this.anchorOffset = 0,
    this.offset = 0,
  }) : ids = List.unmodifiable(ids),
       loadedIds = Set.unmodifiable(loadedIds);
  final List<int> ids;
  final Set<int> loadedIds;
  final PostVotingOrder order;
  final int? anchorId;
  final double anchorOffset;
  final double offset;
}

final class PostVotingServices extends FrameSafeNotifier
    implements
        PluginSiteActivator,
        PluginCurrentUserObserver,
        PluginCoreLinkProjection,
        PluginLinkHandler {
  PostVotingServices({
    required this.api,
    required this.requests,
    required this.posts,
    required this.siteState,
    required this.readers,
    required this.records,
    required this.topics,
    required this.navigation,
    required this.routeNavigation,
    required this.accounts,
    required this.flagCatalog,
  }) {
    actions = PostVotingActions(
      api: api,
      requests: requests,
      posts: posts,
      settingsFor: settingsFor,
    )..addListener(_actionsChanged);
    records.changes.addListener(_recordsChanged);
  }
  final PostVotingApi api;
  final PluginRequestHost requests;
  final PluginPostHost posts;
  final PluginSiteStateHost siteState;
  final PluginTopicReaderHost readers;
  final PluginTopicRecordsHost records;
  final PluginTopicRefreshHost topics;
  final PluginNavigationHost navigation;
  final PluginRouteNavigationHost routeNavigation;
  final PluginAccountConnectionHost accounts;
  final PluginPostFlagCatalogReader flagCatalog;
  late final PostVotingActions actions;
  final Map<String, _Watch> _sites = {};
  final Map<(String, String, int, PostVotingOrder), PostVotingViewSnapshot>
  _memory = {};
  final Set<String> _connecting = {};
  bool _pruning = false;

  PostVotingSettings settingsFor(String site) =>
      siteState.siteConfigFor(site).plugins.get(postVotingSettingsKey) ??
      const PostVotingSettings();
  bool staffFor(String site) => siteState.currentUserFor(site)?.staff == true;
  bool canFlag(String site) =>
      siteState
          .currentUserFor(site)
          ?.plugins
          .get(postVotingCurrentUserKey)
          ?.canFlagComments ==
      true;
  void _actionsChanged() => notifySafely();
  _Watch _watch(String site) {
    final held = _sites[site];
    if (held != null && held.lease.isCurrent) return held;
    if (held != null) forget(site);
    final settings = siteState.siteConfigListenableFor?.call(site);
    void changed() => _sync(site);
    final value = (
      lease: requests.capture(site),
      settings: settings,
      changed: changed,
    );
    _sites[site] = value;
    settings?.addListener(changed);
    return value;
  }

  void _sync(String site) {
    final watch = _sites[site];
    if (isDisposed || watch == null) return;
    if (!watch.lease.isCurrent) {
      forget(site);
      return;
    }
    if (settingsFor(site).enabled == false && !_pruning) {
      _pruning = true;
      try {
        actions.forget(site);
        _memory.removeWhere((key, _) => key.$1 == site);
        records.invalidate(site, watch.lease);
      } finally {
        _pruning = false;
      }
    }
    notifySafely();
  }

  void _recordsChanged() {
    if (isDisposed || _pruning) return;
    for (final site in _sites.keys.toList()) {
      _sync(site);
    }
  }

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) {
    if (!isDisposed) _watch(siteUrl);
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    if (!isDisposed) {
      _watch(siteUrl);
      _sync(siteUrl);
    }
  }

  PostVotingViewSnapshot? memory(
    PluginTopicReader reader,
    PostVotingOrder order,
  ) {
    if (!reader.isCurrent || !_watch(reader.siteUrl).lease.isCurrent) {
      return null;
    }
    return _memory[(reader.siteUrl, reader.tabId, reader.topicId, order)];
  }

  void remember(PluginTopicReader reader, PostVotingViewSnapshot value) {
    if (!reader.isCurrent ||
        isDisposed ||
        !_watch(reader.siteUrl).lease.isCurrent) {
      return;
    }
    _memory[(reader.siteUrl, reader.tabId, reader.topicId, value.order)] =
        value;
  }

  Future<void> connectAndVote(
    PluginTopicReader source,
    int postId,
    PostVoteDirection direction,
  ) async {
    if (isDisposed || !source.isCurrent || !_connecting.add(source.siteUrl)) {
      return;
    }
    final site = source.siteUrl, topicId = source.topicId, tab = source.tabId;
    try {
      final error = await accounts.connect(site);
      if (error != null ||
          isDisposed ||
          !accounts.isConnected(site) ||
          navigation.currentInstance?.url != site ||
          navigation.activeTabId != tab ||
          navigation.currentContent?.topicId != topicId) {
        return;
      }
      _watch(site);
      await topics.reloadTopic(site, topicId);
      if (isDisposed ||
          navigation.currentInstance?.url != site ||
          navigation.activeTabId != tab ||
          navigation.currentContent?.topicId != topicId) {
        return;
      }
      final reader = readers.forVisibleTopic(site, topicId);
      if (reader == null) return;
      try {
        if (!await actions.reconcilePost(reader, postId)) return;
        if (actions.record(site, postId)?.myVote == direction) return;
        await actions.vote(reader, postId, direction);
      } finally {
        reader.close();
      }
    } finally {
      _connecting.remove(site);
      notifySafely();
    }
  }

  static final _commentFragment = RegExp(
    r'^post-voting-comment-([1-9][0-9]*)$',
  );

  static int? _commentLinkId(Uri uri) =>
      int.tryParse(_commentFragment.firstMatch(uri.fragment)?.group(1) ?? '');

  static String _commentLinkQuery(Uri uri, int commentId) => Uri(
    queryParameters: {
      ...uri.queryParametersAll,
      'post-voting-comment': ['$commentId'],
    },
  ).query;

  @override
  ContentRoute? projectCoreLink({
    required String siteUrl,
    required String url,
    required ContentRoute route,
  }) {
    if (isDisposed ||
        settingsFor(siteUrl).enabled == false ||
        route.topicId == null) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final commentId = _commentLinkId(uri);
    if (commentId == null) return null;
    try {
      return ContentRoute.topic(
        topicId: route.topicId!,
        slug: route.slug ?? '',
        title: route.title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: route.postNumber,
        query: _commentLinkQuery(uri, commentId),
      ).withDisplay(icon: route.icon);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    if (isDisposed || url.length > TopicLink.maximumUrlLength) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return false;
    final commentId = _commentLinkId(uri);
    if (commentId == null) return false;
    final owner = mostSpecificServingForum(
      navigation.instances,
      uri,
      siteUrl: (site) => site.url,
    );
    if (owner == null) return false;
    final index = navigation.instances.indexWhere(
      (site) => site.url == owner.forum.url,
    );
    if (index < 0) return false;
    final site = navigation.instances[index].url;
    if (settingsFor(site).enabled == false) return false;
    final parts = DiscourseInstance.pathSegmentsWithin(site, uri);
    if (parts == null) return false;
    final lease = _watch(site).lease;
    final sourceSite = navigation.currentInstance?.url;
    final sourceLease = sourceSite == null
        ? null
        : requests.capture(sourceSite);
    final sourceTab = navigation.activeTabId;
    final sourceIdentity = navigation.currentContent?.destination.identity;
    bool current() =>
        !isDisposed &&
        lease.isCurrent &&
        sourceLease?.isCurrent != false &&
        navigation.currentInstance?.url == sourceSite &&
        navigation.activeTabId == sourceTab &&
        navigation.currentContent?.destination.identity == sourceIdentity;
    int? topicId, number;
    var slug = 'topic';
    var committed = false;
    try {
      if (parts.length == 2 && parts.first == 'p') {
        final id = int.tryParse(parts.last);
        if (id == null || id <= 0) return false;
        final credentials = await requests.credentialsFor(site);
        if (!current()) return true;
        final location = await api.lookupPost(
          siteUrl: site,
          postId: id,
          credentials: credentials,
        );
        topicId = location.topicId;
        number = location.postNumber;
        slug = location.slug;
      } else if ((parts.length == 3 || parts.length == 4) &&
          parts.first == 't') {
        topicId = int.tryParse(parts[2]);
        slug = parts[1];
        number = parts.length == 4 ? int.tryParse(parts[3]) : 1;
        if (parts.length == 4 && (number == null || number <= 0)) return false;
      } else {
        return false;
      }
      if (!current()) return true;
      if (topicId == null || topicId <= 0) return false;
      committed = routeNavigation.pushContent(
        ContentRoute.topic(
          topicId: topicId,
          slug: slug,
          title: slug,
          postNumber: number,
          query: _commentLinkQuery(uri, commentId),
        ),
        siteUrl: site,
        origin: origin,
        onNavigated: onNavigated,
      );
      if (!committed) return true;
      if (lease.isCurrent && !isDisposed) {
        await topics.reloadTopic(site, topicId);
      }
      return true;
    } catch (_) {
      return committed || !current();
    }
  }

  void forget(String site) {
    final held = _sites.remove(site);
    if (held != null) held.settings?.removeListener(held.changed);
    _memory.removeWhere((key, _) => key.$1 == site);
    actions.forget(site);
    notifySafely();
  }

  @override
  void dispose() {
    records.changes.removeListener(_recordsChanged);
    for (final held in _sites.values) {
      held.settings?.removeListener(held.changed);
    }
    _sites.clear();
    _memory.clear();
    actions.removeListener(_actionsChanged);
    actions.dispose();
    super.dispose();
  }
}
