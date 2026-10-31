import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_api.dart';
import 'nested_replies_data.dart';

enum NestedRepliesBulkProblem { failed, partial, uncertain }

final class _BulkSelection {
  _BulkSelection(this.lease);

  final PluginSiteLease lease;
  final Set<int> topicIds = {};
  List<int> uncertainTopicIds = const [];
  bool selecting = false;
  bool busy = false;
  bool needsRecheck = false;
  NestedRepliesBulkProblem? problem;
  VoidCallback? detach;
}

final class NestedRepliesBulkController extends ChangeNotifier {
  NestedRepliesBulkController({
    required this.api,
    required this.requests,
    required this.siteState,
    required this.onChanged,
    this.staffFor,
  });

  final NestedRepliesApi api;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final bool Function(String siteUrl)? staffFor;
  final Future<void> Function(String siteUrl, List<int> topicIds) onChanged;
  final Map<String, _BulkSelection> _sites = {};
  bool _disposed = false;

  bool available(String siteUrl) {
    final settings = siteState
        .siteConfigFor(siteUrl)
        .plugins
        .get(nestedRepliesSettingsKey);
    return !_disposed &&
        (staffFor?.call(siteUrl) ??
            siteState.currentUserFor(siteUrl)?.staff == true) &&
        settings?.enabled == true &&
        settings?.defaultEnabled == false;
  }

  _BulkSelection? _current(String siteUrl) {
    final state = _sites[siteUrl];
    return state?.lease.isCurrent == true ? state : null;
  }

  bool selecting(String siteUrl) =>
      available(siteUrl) && _current(siteUrl)?.selecting == true;
  bool busy(String siteUrl) => _current(siteUrl)?.busy == true;
  bool needsRecheck(String siteUrl) => _current(siteUrl)?.needsRecheck == true;
  NestedRepliesBulkProblem? problem(String siteUrl) =>
      _current(siteUrl)?.problem;
  Set<int> selectedTopicIds(String siteUrl) =>
      Set.unmodifiable(_current(siteUrl)?.topicIds ?? const <int>[]);

  _BulkSelection _create(String siteUrl) {
    final held = _current(siteUrl);
    if (held != null) return held;
    _sites.remove(siteUrl)?.detach?.call();
    final state = _BulkSelection(requests.capture(siteUrl));
    _sites[siteUrl] = state;
    final config = siteState.siteConfigListenableFor?.call(siteUrl);
    if (config != null) {
      void changed() {
        if (!_owns(siteUrl, state)) return;
        if (!available(siteUrl)) {
          state.selecting = false;
          state.topicIds.clear();
        }
        notifyListeners();
      }

      config.addListener(changed);
      state.detach = () => config.removeListener(changed);
    }
    return state;
  }

  bool _owns(String siteUrl, _BulkSelection state) =>
      !_disposed && state.lease.isCurrent && identical(_sites[siteUrl], state);

  bool _canComplete(String siteUrl, _BulkSelection state) =>
      _owns(siteUrl, state) && available(siteUrl);

  void start(String siteUrl) {
    if (!available(siteUrl)) return;
    final state = _create(siteUrl);
    if (state.busy) return;
    state.selecting = true;
    state.problem = state.needsRecheck
        ? NestedRepliesBulkProblem.uncertain
        : null;
    notifyListeners();
  }

  void cancel(String siteUrl) {
    final state = _current(siteUrl);
    if (state == null || state.busy) return;
    state.selecting = false;
    state.topicIds.clear();
    state.problem = null;
    notifyListeners();
  }

  void toggle(String siteUrl, Topic topic) {
    final state = _current(siteUrl);
    if (!selecting(siteUrl) ||
        state == null ||
        state.busy ||
        state.needsRecheck ||
        topic.privateMessage) {
      return;
    }
    if (!state.topicIds.remove(topic.id)) state.topicIds.add(topic.id);
    state.problem = null;
    notifyListeners();
  }

  Future<bool> submit(String siteUrl, {required bool enabled}) async {
    final state = _current(siteUrl);
    if (state == null ||
        !selecting(siteUrl) ||
        state.busy ||
        state.needsRecheck ||
        state.topicIds.isEmpty) {
      return false;
    }
    final selected = state.topicIds.toList(growable: false);
    state.busy = true;
    state.problem = null;
    notifyListeners();
    var sent = false;
    try {
      final credential = await requests.writeCredentialFor(siteUrl);
      if (!_canComplete(siteUrl, state)) return false;
      if (credential.failure case final failure?) throw failure;
      final request = credential.credentials;
      if (request == null) return false;
      final result = await request.run(() {
        if (!_canComplete(siteUrl, state)) {
          throw StateError('The selection was retired.');
        }
        sent = true;
        return api.bulkTopicMode(
          siteUrl: siteUrl,
          topicIds: selected,
          enabled: enabled,
          credentials: request,
        );
      });
      if (!_canComplete(siteUrl, state)) return false;
      if (result.changedTopicIds.any((id) => !selected.contains(id))) {
        throw const FormatException('Unrelated topic in bulk response.');
      }
      if (result.changedTopicIds.isNotEmpty) {
        await onChanged(siteUrl, result.changedTopicIds);
      }
      if (!_canComplete(siteUrl, state)) return false;
      for (final id in result.changedTopicIds) {
        state.topicIds.remove(id);
      }
      final partial = state.topicIds.isNotEmpty || _hasErrors(result.errors);
      state.problem = partial ? NestedRepliesBulkProblem.partial : null;
      state.selecting = partial;
      return !partial;
    } catch (error) {
      if (_canComplete(siteUrl, state)) {
        final uncertain =
            sent &&
            (error is! WriteException ||
                (error.failure == WriteFailure.unreachable && !error.notSent));
        state.needsRecheck = uncertain;
        if (uncertain) state.uncertainTopicIds = selected;
        state.problem = uncertain
            ? NestedRepliesBulkProblem.uncertain
            : NestedRepliesBulkProblem.failed;
      }
      return false;
    } finally {
      if (_owns(siteUrl, state)) {
        state.busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> recheck(String siteUrl) async {
    final state = _current(siteUrl);
    if (state == null ||
        !_canComplete(siteUrl, state) ||
        state.busy ||
        !state.needsRecheck) {
      return;
    }
    state.busy = true;
    notifyListeners();
    try {
      await onChanged(siteUrl, state.uncertainTopicIds);
      if (!_canComplete(siteUrl, state)) return;
      state.needsRecheck = false;
      state.uncertainTopicIds = const [];
      state.problem = null;
    } catch (_) {
      if (_canComplete(siteUrl, state)) {
        state.problem = NestedRepliesBulkProblem.uncertain;
      }
    } finally {
      if (_owns(siteUrl, state)) {
        state.busy = false;
        notifyListeners();
      }
    }
  }

  void forget(String siteUrl) {
    _sites.remove(siteUrl)?.detach?.call();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final state in _sites.values) {
      state.detach?.call();
    }
    _sites.clear();
    super.dispose();
  }

  static bool _hasErrors(Object? errors) => switch (errors) {
    null => false,
    final List<Object?> values => values.isNotEmpty,
    final Map<Object?, Object?> values => values.isNotEmpty,
    final String value => value.isNotEmpty,
    _ => true,
  };
}

class NestedRepliesBulkActions extends StatelessWidget {
  const NestedRepliesBulkActions({
    super.key,
    required this.controller,
    required this.siteUrl,
  });

  final NestedRepliesBulkController controller;
  final String siteUrl;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.available(siteUrl)) return const SizedBox.shrink();
      if (!controller.selecting(siteUrl)) {
        return DButton(
          key: const ValueKey('nested-bulk-start'),
          variant: DButtonVariant.tool,
          label: Text(context.l10n.nestedRepliesBulkSelect),
          onPressed: () => controller.start(siteUrl),
        );
      }
      final count = controller.selectedTopicIds(siteUrl).length;
      final busy = controller.busy(siteUrl);
      final needsRecheck = controller.needsRecheck(siteUrl);
      final problem = controller.problem(siteUrl);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DDropdownMenu(
            sheetOnMobile: true,
            content: DDropdownMenuContent(
              children: [
                if (problem != null)
                  DDropdownMenuLabel(
                    child: Text(
                      problem == NestedRepliesBulkProblem.uncertain
                          ? context.l10n.nestedRepliesMutationUncertain
                          : context.l10n.nestedRepliesBulkPartial,
                    ),
                  ),
                if (needsRecheck)
                  DDropdownMenuItem(
                    onPressed: busy
                        ? null
                        : () => unawaited(controller.recheck(siteUrl)),
                    child: Text(context.l10n.retry),
                  )
                else ...[
                  DDropdownMenuItem(
                    onPressed: busy || count == 0
                        ? null
                        : () => unawaited(
                            controller.submit(siteUrl, enabled: true),
                          ),
                    child: Text(context.l10n.nestedRepliesBulkEnable),
                  ),
                  DDropdownMenuItem(
                    onPressed: busy || count == 0
                        ? null
                        : () => unawaited(
                            controller.submit(siteUrl, enabled: false),
                          ),
                    child: Text(context.l10n.nestedRepliesBulkDisable),
                  ),
                ],
              ],
            ),
            child: DDropdownMenuTrigger.button(
              label: Text('${context.l10n.nestedRepliesSettings} ($count)'),
            ),
          ),
          DButton(
            key: const ValueKey('nested-bulk-cancel'),
            variant: DButtonVariant.tool,
            label: Text(context.l10n.cancel),
            onPressed: busy ? null : () => controller.cancel(siteUrl),
          ),
        ],
      );
    },
  );
}

class NestedRepliesBulkTitle extends StatelessWidget {
  const NestedRepliesBulkTitle({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.topic,
    required this.title,
  });

  final NestedRepliesBulkController controller;
  final String siteUrl;
  final Topic topic;
  final Widget title;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) =>
        !controller.selecting(siteUrl) || topic.privateMessage
        ? title
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DCheckbox(
                key: ValueKey('nested-bulk-select-${topic.id}'),
                value: controller.selectedTopicIds(siteUrl).contains(topic.id),
                enabled:
                    !controller.busy(siteUrl) &&
                    !controller.needsRecheck(siteUrl),
                semanticLabel:
                    '${context.l10n.nestedRepliesBulkSelect} ${topic.title}',
                onChanged: (_) => controller.toggle(siteUrl, topic),
              ),
              const SizedBox(width: 8),
              Expanded(child: title),
            ],
          ),
  );
}
