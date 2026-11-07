import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_admin.dart';
import 'nested_replies_api.dart';
import 'nested_replies_bulk.dart';
import 'nested_replies_data.dart';
import 'nested_replies_notifications.dart';
import 'nested_replies_reader.dart';

const nestedRepliesServiceKey = PluginServiceKey<NestedRepliesServices>(
  owner: nestedRepliesPluginId,
  name: 'services',
);

typedef _SiteWatch = ({
  PluginSiteLease lease,
  Listenable? settings,
  VoidCallback changed,
});

final class NestedRepliesServices extends ChangeNotifier
    implements
        PluginSiteActivator,
        PluginCurrentUserObserver,
        PluginNotificationPresentationStrategy,
        PluginLinkHandler {
  NestedRepliesServices({
    required this.api,
    required this.requests,
    required this.siteState,
    required this.readers,
    required this.records,
    required this.topics,
    required this.targets,
    required this.navigation,
    required this.accounts,
  }) {
    records.changes.addListener(_changedRecords);
  }

  final NestedRepliesApi api;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final PluginTopicReaderHost readers;
  final PluginTopicRecordsHost records;
  final PluginTopicRefreshHost topics;
  final PluginTargetHost targets;
  final PluginRouteNavigationHost navigation;
  final PluginFreshAccountHost accounts;

  bool staffFor(String site) => accounts.profileFor(site)?.staff == true;
  final memory = NestedRepliesReaderMemory();
  final Map<String, _SiteWatch> _sites = {};
  final Map<String, NestedRepliesSettings> _observedSettings = {};
  final Map<(String, int), Object> _pinOperations = {};
  final Set<(String, int)> _uncertainPins = {};
  bool _disposed = false;
  bool _pruning = false;
  NestedRepliesBulkController? _bulk;

  NestedRepliesBulkController get bulk => _bulk ??= NestedRepliesBulkController(
    api: api,
    requests: requests,
    siteState: siteState,
    staffFor: staffFor,
    onChanged: (site, ids) async {
      final lease = _watch(site).lease;
      for (final id in ids) {
        if (!lease.isCurrent || _disposed) return;
        await topics.reloadTopic(site, id);
        if (!lease.isCurrent || _disposed) return;
        memory.invalidateTopic(site, id);
      }
    },
  );

  NestedRepliesSettings settingsFor(String site) =>
      siteState.siteConfigFor(site).plugins.get(nestedRepliesSettingsKey) ??
      const NestedRepliesSettings();

  _SiteWatch _watch(String site) {
    final held = _sites[site];
    if (held != null && held.lease.isCurrent) return held;
    if (held != null) forget(site);
    final listenable = siteState.siteConfigListenableFor?.call(site);
    final lease = requests.capture(site);
    void changed() => _sync(site);
    final watch = (lease: lease, settings: listenable, changed: changed);
    _sites[site] = watch;
    listenable?.addListener(changed);
    _sync(site);
    return watch;
  }

  void _changedRecords() {
    if (_disposed || _pruning) return;
    for (final site in _sites.keys.toList()) {
      _sync(site);
    }
  }

  void _sync(String site) {
    final watch = _sites[site];
    if (_disposed || watch == null) return;
    if (!watch.lease.isCurrent) {
      forget(site);
      return;
    }
    final settings = settingsFor(site);
    final changed = _observedSettings[site] != settings;
    _observedSettings[site] = settings;
    if (settings.enabled == false && !_pruning) {
      _pruning = true;
      try {
        records.invalidate(site, watch.lease);
        memory.forgetSite(site);
        _bulk?.forget(site);
      } finally {
        _pruning = false;
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) {
    if (!_disposed) _watch(siteUrl);
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    if (!_disposed) {
      if (!staffFor(siteUrl)) _bulk?.forget(siteUrl);
      _watch(siteUrl);
      notifyListeners();
    }
  }

  @override
  ResolvedNotification? resolveNotification(
    PluginNotificationPresentationContext context,
  ) {
    if (_disposed) return null;
    final watch = _watch(context.siteUrl);
    final settings = settingsFor(context.siteUrl);
    final topicId = context.notification.topicId;
    final record = topicId == null
        ? null
        : targets.recordFor(
            context.siteUrl,
            PluginTarget.topic(topicId),
            nestedRepliesTopicKey,
          );
    final available =
        watch.lease.isCurrent &&
        settings.enabled != false &&
        (settings.enabled == true ||
            (record?.valid == true && record?.value?.enabled == true));
    return nestedReplyNotification(context, available: available);
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    if (_disposed || url.length > TopicLink.maximumUrlLength) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return false;
    final owner = mostSpecificServingForum(
      navigation.sites,
      uri,
      siteUrl: (site) => site.url,
    );
    if (owner == null) return false;
    final site = owner.forum.url;
    final segments = DiscourseInstance.pathSegmentsWithin(site, uri);
    if (segments == null || segments.length < 3 || segments.first != 'n') {
      return false;
    }
    final topicId = int.tryParse(segments[2]);
    if (topicId == null || topicId <= 0 || settingsFor(site).enabled != true) {
      return false;
    }
    int? number;
    if (segments.length == 4) {
      number = int.tryParse(segments[3]);
    } else if (segments.length == 5 && segments[3] == 'context') {
      number = int.tryParse(segments[4]);
    } else if (segments.length != 3) {
      return false;
    }
    if (segments.length > 3 && (number == null || number <= 0)) return false;
    final query = <String, String>{};
    final supplied = nestedRepliesQuery(uri.query);
    final sort = NestedRepliesSort.parse(supplied['sort']);
    if (sort != null) query['sort'] = sort.wireValue;
    if (supplied['collapse_replies'] == 'true') {
      query['collapse_replies'] = 'true';
    }
    final context = int.tryParse(supplied['context'] ?? '');
    if (context != null && context >= 0 && context <= 100) {
      query['context'] = '$context';
    }
    final lease = _watch(site).lease;
    if (!lease.isCurrent || _disposed) return false;
    final committed = navigation.pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: segments[1],
        title: segments[1],
        postNumber: number,
        query: query.isEmpty ? null : Uri(queryParameters: query).query,
      ),
      siteUrl: site,
      origin: origin,
      onNavigated: onNavigated,
    );
    if (committed && lease.isCurrent && !_disposed) {
      await topics.reloadTopic(site, topicId);
    }
    return true;
  }

  Future<void> showSettings(
    BuildContext context,
    String site,
    int topicId,
  ) async {
    if (_disposed || settingsFor(site).enabled != true) return;
    _watch(site);
    final settings = settingsFor(site);
    final reader = readers.forVisibleTopic(site, topicId);
    if (reader == null) return;
    try {
      await showNestedRepliesSettings(
        context,
        reader: reader,
        api: api,
        settings: settings,
        requests: requests,
        available: () => !_disposed && settingsFor(site) == settings,
      );
      if (reader.isCurrent) memory.invalidateTopic(site, topicId);
    } finally {
      reader.close();
    }
  }

  Future<void> showActivity(
    BuildContext context,
    String site,
    int topicId,
  ) async {
    if (_disposed || settingsFor(site).enabled == false) return;
    final reader = readers.forVisibleTopic(site, topicId);
    if (reader == null) return;
    try {
      await showNestedRepliesActivity(
        context,
        reader: reader,
        api: api,
        available: () => !_disposed && settingsFor(site).enabled != false,
      );
    } finally {
      reader.close();
    }
  }

  bool pinBusy(String site, int topicId) =>
      _pinOperations.containsKey((site, topicId));

  Future<void> togglePin(
    BuildContext context,
    String site,
    int topicId,
    int postId,
  ) async {
    if (_disposed || pinBusy(site, topicId)) return;
    final reader = readers.forVisibleTopic(site, topicId);
    if (reader == null) return;
    final watch = _watch(site);
    final key = (site, topicId);
    final operation = Object();
    _pinOperations[key] = operation;
    notifyListeners();
    bool current() =>
        !_disposed &&
        watch.lease.isCurrent &&
        reader.isCurrent &&
        reader.foreground &&
        settingsFor(site).enabled != false &&
        reader.topic?.plugins.get(nestedRepliesTopicKey)?.enabled == true &&
        reader.currentUserStaff &&
        reader.topic?.canEdit == true;
    try {
      if (!current()) return;
      final credential = await requests.credentialsFor(site);
      if (!current()) return;
      final List<int> pins;
      if (_uncertainPins.contains(key)) {
        final page = await api.roots(
          siteUrl: site,
          topicId: topicId,
          slug: reader.route.slug ?? '',
          credentials: credential,
          sort: settingsFor(site).defaultSort,
        );
        if (!current()) return;
        pins = page.pinnedPostIds;
      } else {
        pins = await api.togglePin(
          siteUrl: site,
          topicId: topicId,
          slug: reader.route.slug ?? '',
          postId: postId,
          credentials: credential,
        );
      }
      if (!current()) return;
      final accepted = await reader.ingest((_) async {
        final topic = reader.topic!;
        final held =
            topic.plugins.get(nestedRepliesTopicKey) ?? const NestedTopicData();
        final next = held.merge(NestedTopicData(pinnedPostIds: pins));
        return TopicContentResult(
          value: pins,
          metadata: topic.withPlugins(
            topic.plugins.withValue(nestedRepliesTopicKey, next),
          ),
        );
      });
      if (current() && accepted != null) {
        _uncertainPins.remove(key);
        memory.invalidateTopic(site, topicId);
      }
    } catch (error) {
      if (current()) {
        final uncertain =
            error is! WriteException ||
            (error.failure == WriteFailure.unreachable && !error.notSent);
        if (uncertain) _uncertainPins.add(key);
        memory.invalidateTopic(site, topicId);
        if (context.mounted) {
          await showShellSheet<void>(
            context: context,
            title: appL10n.nestedRepliesSettings,
            builder: (_) => Text(
              uncertain
                  ? appL10n.nestedRepliesMutationUncertain
                  : error.message,
            ),
          );
        }
      }
    } finally {
      if (identical(_pinOperations[key], operation)) _pinOperations.remove(key);
      reader.close();
      if (!_disposed) notifyListeners();
    }
  }

  void forget(String site) {
    _observedSettings.remove(site);
    final watch = _sites.remove(site);
    if (watch != null) watch.settings?.removeListener(watch.changed);
    memory.forgetSite(site);
    _bulk?.forget(site);
    _pinOperations.removeWhere((key, _) => key.$1 == site);
    _uncertainPins.removeWhere((key) => key.$1 == site);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    records.changes.removeListener(_changedRecords);
    for (final site in _sites.keys.toList()) {
      forget(site);
    }
    _bulk?.dispose();
    memory.dispose();
    super.dispose();
  }
}
