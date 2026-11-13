import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'nested_replies_api.dart';
import 'nested_replies_data.dart';

enum NestedRepliesAdminProblem { unavailable, failed, uncertain }

final class NestedRepliesAdminController extends ChangeNotifier {
  NestedRepliesAdminController({
    required this.reader,
    required this.api,
    required this.categories,
    required this.settings,
    required this.requests,
    this.available,
  }) : _lease = requests.capture(reader.siteUrl) {
    reader.addListener(_readerChanged);
  }

  final PluginTopicReader reader;
  final NestedRepliesApi api;
  final NestedRepliesSettings settings;
  final PluginRequestHost requests;
  final PluginCategorySettingsApi categories;
  final bool Function()? available;
  final PluginSiteLease _lease;
  bool _disposed = false;
  bool busy = false;
  bool loadingCategory = false;
  bool needsRecheck = false;
  bool saved = false;
  NestedRepliesAdminProblem? problem;
  PluginCategorySettingsSnapshot? category;
  int? convertedCount;

  bool get isCurrent => !_disposed && _lease.isCurrent && reader.isCurrent;
  bool get canOpen =>
      isCurrent &&
      reader.foreground &&
      reader.currentUserStaff &&
      settings.enabled == true &&
      (available?.call() ?? true) &&
      reader.topic?.privateMessage == false;
  bool get canChangeTopic =>
      canOpen && reader.topic?.canEdit == true && !settings.defaultEnabled;
  bool get topicEnabled =>
      reader.topic?.plugins.get(nestedRepliesTopicKey)?.enabled == true;
  bool get categoryDefault =>
      category?.settings['nested_replies_default'] == true;
  bool get categoryConverted =>
      switch (category?.customFields['nested_replies_conversion_completed']) {
        true || 'true' || 't' || '1' => true,
        _ => false,
      };
  bool get canChangeCategory => canOpen && category?.canEdit == true;
  bool get canConvert =>
      canChangeCategory && categoryDefault && !categoryConverted;

  Future<void> loadCategory() => _loadCategory();

  Future<void> _loadCategory({Future<void>? topicRefresh}) async {
    final id = reader.topic?.categoryId;
    if (!canOpen || id == null || loadingCategory) return;
    loadingCategory = true;
    problem = null;
    _notify();
    try {
      final credential = await requests.credentialsFor(reader.siteUrl);
      if (!canOpen) return;
      final result = await categories.read(
        siteUrl: reader.siteUrl,
        categoryId: id,
        credentials: credential,
      );
      await topicRefresh;
      if (!canOpen || reader.topic?.categoryId != id) return;
      category = result;
    } catch (_) {
      if (isCurrent) problem = NestedRepliesAdminProblem.failed;
    } finally {
      if (isCurrent) {
        loadingCategory = false;
        _notify();
      }
    }
  }

  Future<void> recheck() async {
    if (!canOpen || busy) return;
    busy = true;
    problem = null;
    _notify();
    try {
      final initialCategory = reader.topic?.categoryId;
      final topicRefresh = reader.refreshMetadata();
      await Future.wait([
        topicRefresh,
        if (initialCategory != null) _loadCategory(topicRefresh: topicRefresh),
      ]);
      if (!canOpen) return;
      if (reader.topic?.categoryId != initialCategory) {
        await loadCategory();
      }
      if (canOpen && problem == null) needsRecheck = false;
    } catch (_) {
      if (isCurrent) problem = NestedRepliesAdminProblem.failed;
    } finally {
      if (isCurrent) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> setTopicEnabled(bool enabled) => _write(
    allowed: () => canChangeTopic,
    operation: (credential) async {
      await api.toggleTopic(
        siteUrl: reader.siteUrl,
        topicId: reader.topicId,
        slug: reader.route.slug ?? '',
        enabled: enabled,
        credentials: credential,
      );
      if (!isCurrent) return;
      await reader.refreshMetadata();
    },
  );

  Future<bool> setCategoryDefault(bool enabled) => _write(
    allowed: () => canChangeCategory,
    operation: (credential) async {
      final original = category!;
      final result = await categories.save(
        siteUrl: reader.siteUrl,
        snapshot: original,
        settings: {'nested_replies_default': enabled},
        credentials: credential,
      );
      if (isCurrent && reader.topic?.categoryId == original.id) {
        category = result;
      }
    },
  );

  Future<bool> convertExistingTopics() => _write(
    allowed: () => canConvert,
    operation: (credential) async {
      final original = category!;
      final result = await api.convertCategory(
        siteUrl: reader.siteUrl,
        categoryId: original.id,
        credentials: credential,
      );
      if (!isCurrent || reader.topic?.categoryId != original.id) return;
      convertedCount = result.convertedTopicCount;
      category = PluginCategorySettingsSnapshot(
        id: original.id,
        name: original.name,
        canEdit: original.canEdit,
        settings: original.settings,
        customFields: {
          ...original.customFields,
          'nested_replies_conversion_completed': result.completed,
        },
      );
      await reader.refreshMetadata();
    },
  );

  Future<bool> _write({
    required bool Function() allowed,
    required Future<void> Function(PluginRequestCredentials) operation,
  }) async {
    if (busy || needsRecheck || !allowed()) return false;
    busy = true;
    problem = null;
    saved = false;
    _notify();
    var sent = false;
    try {
      final credential = await requests.writeCredentialFor(reader.siteUrl);
      if (!isCurrent || !allowed()) return false;
      if (credential.failure case final failure?) throw failure;
      final request = credential.credentials;
      if (request == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      sent = true;
      await operation(request);
      if (!isCurrent) return false;
      saved = true;
      return true;
    } catch (error) {
      if (!isCurrent) return false;
      final uncertain =
          sent &&
          (error is! WriteException ||
              (error.failure == WriteFailure.unreachable && !error.notSent));
      needsRecheck = uncertain;
      problem = uncertain
          ? NestedRepliesAdminProblem.uncertain
          : NestedRepliesAdminProblem.failed;
      return false;
    } finally {
      if (isCurrent) {
        busy = false;
        _notify();
      }
    }
  }

  void _readerChanged() => _notify();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reader.removeListener(_readerChanged);
    super.dispose();
  }
}

final class NestedRepliesActivityController extends ChangeNotifier {
  NestedRepliesActivityController({
    required this.reader,
    required this.api,
    this.available,
  }) {
    reader.addListener(_readerChanged);
    _subscription = reader.topicEvents.listen(
      (_) => unawaited(load(refresh: true)),
    );
  }

  final PluginTopicReader reader;
  final NestedRepliesApi api;
  final bool Function()? available;
  StreamSubscription<Object?>? _subscription;
  final List<NestedActivityEntry> _entries = [];
  bool _disposed = false;
  bool _refreshPending = false;
  bool _retryRefresh = false;
  bool loading = false;
  bool hasMore = true;
  int _page = -1;
  int _generation = 0;
  Object? error;
  List<NestedActivityEntry> get entries => List.unmodifiable(_entries);
  bool get isCurrent => !_disposed && reader.isCurrent;
  bool get isAvailable =>
      isCurrent &&
      reader.foreground &&
      (available?.call() ?? true) &&
      reader.topic?.plugins.get(nestedRepliesTopicKey)?.enabled == true &&
      reader.topic?.plugins.get(nestedRepliesTopicKey)?.hasActivityLog == true;

  void _readerChanged() {
    if (_disposed) return;
    if (!isAvailable) {
      _generation++;
      _entries.clear();
      error = null;
      loading = false;
      hasMore = true;
      _page = -1;
      _refreshPending = false;
      _retryRefresh = false;
    }
    notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    if (!isAvailable) {
      _readerChanged();
      return;
    }
    refresh = refresh || _retryRefresh;
    if (loading) {
      _refreshPending |= refresh;
      return;
    }
    if (!refresh && !hasMore) return;
    loading = true;
    error = null;
    notifyListeners();
    final page = refresh ? 0 : _page + 1;
    final generation = _generation;
    bool currentRequest() => isAvailable && generation == _generation;
    try {
      final accepted = await reader.ingest((request) async {
        if (!currentRequest()) throw const _ActivityRequestRetired();
        final pageResult = await api.activity(
          siteUrl: reader.siteUrl,
          topicId: reader.topicId,
          slug: reader.route.slug ?? '',
          credentials: request,
          page: page,
        );
        if (!currentRequest()) throw const _ActivityRequestRetired();
        return TopicContentResult(
          value: pageResult,
          posts: [
            for (final entry in pageResult.entries)
              if (entry.post case final post?) TopicContentPost(post),
          ],
        );
      });
      if (!currentRequest() || accepted == null) return;
      if (refresh) _entries.clear();
      final existing = _entries.map((entry) => entry.post?.id).toSet();
      for (final entry in accepted.value.entries) {
        if (entry.synthetic) {
          if (!_entries.any((held) => held.synthetic)) _entries.add(entry);
        } else if (accepted.postIds.contains(entry.post!.id) &&
            existing.add(entry.post!.id)) {
          _entries.add(entry);
        }
      }
      _page = page;
      hasMore = accepted.value.hasMore;
      _retryRefresh = false;
    } catch (caught) {
      if (currentRequest()) {
        error = caught;
        _retryRefresh = refresh;
      }
    } finally {
      if (!isAvailable) {
        _readerChanged();
      } else if (currentRequest()) {
        loading = false;
        notifyListeners();
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(load(refresh: true));
        }
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reader.removeListener(_readerChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final class _ActivityRequestRetired implements Exception {
  const _ActivityRequestRetired();
}
