import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_admin_controller.dart';
import 'nested_replies_api.dart';
import 'nested_replies_data.dart';

Future<void> showNestedRepliesSettings(
  BuildContext context, {
  required PluginTopicReader reader,
  required NestedRepliesApi api,
  required PluginCategorySettingsApi categories,
  required NestedRepliesSettings settings,
  required PluginRequestHost requests,
  bool Function()? available,
}) async {
  final controller = NestedRepliesAdminController(
    reader: reader,
    api: api,
    categories: categories,
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
