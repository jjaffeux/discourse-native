import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_api.dart';
import 'nested_replies_data.dart';

enum NestedRepliesAdminProblem { unavailable, failed, uncertain }

final class NestedRepliesAdminController extends ChangeNotifier {
  NestedRepliesAdminController({
    required this.reader,
    required this.api,
    required this.settings,
    required this.requests,
    this.available,
  }) : _lease = requests.capture(reader.siteUrl),
       categories = PluginCategorySettingsApi(api.transport) {
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

  Future<void> loadCategory() async {
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
      await reader.refreshMetadata();
      if (!canOpen) return;
      await loadCategory();
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

Future<void> showNestedRepliesSettings(
  BuildContext context, {
  required PluginTopicReader reader,
  required NestedRepliesApi api,
  required NestedRepliesSettings settings,
  required PluginRequestHost requests,
  bool Function()? available,
}) async {
  final controller = NestedRepliesAdminController(
    reader: reader,
    api: api,
    settings: settings,
    requests: requests,
    available: available,
  );
  try {
    if (!controller.canOpen) return;
    unawaited(controller.loadCategory());
    await showShellSheet<void>(
      context: context,
      title: context.l10n.nestedRepliesSettings,
      dialogOnDesktop: true,
      builder: (_) => NestedRepliesSettingsPanel(controller: controller),
    );
  } finally {
    controller.dispose();
  }
}

class NestedRepliesSettingsPanel extends StatelessWidget {
  const NestedRepliesSettingsPanel({super.key, required this.controller});

  final NestedRepliesAdminController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.canOpen) {
        return Text(context.l10n.nestedRepliesModeUnavailable);
      }
      final busy = controller.busy || controller.needsRecheck;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (controller.problem case final problem?)
            DAlert(
              variant: DAlertVariant.destructive,
              description: DAlertDescription(
                child: Text(
                  problem == NestedRepliesAdminProblem.uncertain
                      ? context.l10n.nestedRepliesMutationUncertain
                      : context.l10n.nestedRepliesCouldNotLoad,
                ),
              ),
              action: DAlertAction(
                child: DButton(
                  label: Text(context.l10n.retry),
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(controller.recheck()),
                ),
              ),
            ),
          if (controller.saved) Text(context.l10n.nestedRepliesChangesSaved),
          if (controller.canChangeTopic)
            DToggle(
              key: const ValueKey('nested-topic-mode'),
              pressed: controller.topicEnabled,
              enabled: !busy,
              onPressedChanged: (enabled) =>
                  unawaited(controller.setTopicEnabled(enabled)),
              child: Text(context.l10n.nestedRepliesEnabled),
            ),
          if (controller.loadingCategory) const Center(child: DSpinner()),
          if (controller.category case final category?) ...[
            Text(category.name),
            if (controller.canChangeCategory) ...[
              DToggle(
                key: const ValueKey('nested-category-default'),
                pressed: controller.categoryDefault,
                enabled: !busy,
                onPressedChanged: (enabled) =>
                    unawaited(controller.setCategoryDefault(enabled)),
                child: Text(context.l10n.nestedRepliesCategoryDefault),
              ),
              Text(context.l10n.nestedRepliesCategoryDefaultDescription),
              if (controller.canConvert)
                DButton(
                  key: const ValueKey('nested-convert-category'),
                  label: Text(context.l10n.nestedRepliesConvertExisting),
                  onPressed: busy
                      ? null
                      : () => unawaited(_confirmConversion(context)),
                ),
            ],
          ],
          if (controller.convertedCount case final count?)
            Text(context.l10n.nestedRepliesConversionComplete(count)),
        ],
      );
    },
  );

  Future<void> _confirmConversion(BuildContext context) async {
    final confirmed = await showDiscourseAlertDialog<bool>(
      context: context,
      title: Text(context.l10n.nestedRepliesConvertExisting),
      description: Text(
        context.l10n.nestedRepliesConvertConfirm(
          controller.category?.name ?? '',
        ),
      ),
      cancelLabel: Text(context.l10n.cancel),
      actionLabel: Text(context.l10n.nestedRepliesConvertExisting),
      cancelResult: false,
      actionResult: true,
    );
    if (confirmed == true) await controller.convertExistingTopics();
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

Future<void> showNestedRepliesActivity(
  BuildContext context, {
  required PluginTopicReader reader,
  required NestedRepliesApi api,
  bool Function()? available,
}) async {
  final controller = NestedRepliesActivityController(
    reader: reader,
    api: api,
    available: available,
  );
  try {
    if (!controller.isAvailable) return;
    unawaited(controller.load());
    await showShellSheet<void>(
      context: context,
      title: context.l10n.nestedRepliesActivity,
      dialogOnDesktop: true,
      builder: (_) => NestedRepliesActivityPanel(controller: controller),
    );
  } finally {
    controller.dispose();
  }
}

class NestedRepliesActivityPanel extends StatelessWidget {
  const NestedRepliesActivityPanel({super.key, required this.controller});

  final NestedRepliesActivityController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.isAvailable) {
        return Text(context.l10n.nestedRepliesModeUnavailable);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          for (final entry in controller.entries)
            if (entry.synthetic)
              DAlert(
                liveRegion: false,
                description: DAlertDescription(
                  child: Text(
                    entry.username == null
                        ? context.l10n.nestedRepliesTopicCreated
                        : context.l10n.topicCreatedBy(entry.username!),
                  ),
                ),
              )
            else
              PluginTopicPost(
                reader: controller.reader,
                postId: entry.post!.id,
              ),
          if (controller.error != null)
            DAlert(
              variant: DAlertVariant.destructive,
              description: DAlertDescription(
                child: Text(context.l10n.nestedRepliesCouldNotLoad),
              ),
              action: DAlertAction(
                child: DButton(
                  onPressed: () => unawaited(controller.load()),
                  label: Text(context.l10n.retry),
                ),
              ),
            ),
          if (controller.loading)
            const Center(child: DSpinner())
          else if (controller.entries.isEmpty && controller.error == null)
            Text(context.l10n.nestedRepliesNoActivity)
          else if (controller.hasMore && controller.error == null)
            DButton(
              onPressed: () => unawaited(controller.load()),
              label: Text(context.l10n.loadMore),
            ),
        ],
      );
    },
  );
}
