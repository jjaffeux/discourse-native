import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_api.dart';
import 'post_voting_category_controller.dart';

Future<void> showPostVotingCategorySettings(
  BuildContext context, {
  required PluginTopicReader reader,
  required PostVotingApi api,
  required PluginRequestHost requests,
  bool Function()? available,
}) async {
  final controller = PostVotingCategoryController(
    reader: reader,
    api: api,
    requests: requests,
    available: available,
  );
  try {
    if (!controller.current) return;
    unawaited(controller.load());
    await showShellSheet<void>(
      context: context,
      title: context.l10n.postVotingCategorySettings,
      dialogOnDesktop: true,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            if (controller.busy) const DSpinner(),
            if (controller.error != null)
              DAlert(
                variant: DAlertVariant.destructive,
                description: DAlertDescription(
                  child: Text(
                    controller.uncertain
                        ? context.l10n.postVotingUncertain
                        : postVotingError(controller.error!),
                  ),
                ),
                action: DAlertAction(
                  child: DButton(
                    label: Text(context.l10n.postVotingRefreshStatus),
                    onPressed: controller.busy ? null : controller.load,
                  ),
                ),
              ),
            if (controller.current && controller.category != null) ...[
              Text(controller.category!.name),
              DToggle(
                pressed: controller.defaultOn,
                enabled: controller.canEdit,
                onPressedChanged: (value) => unawaited(
                  controller.save(
                    defaultOn: value,
                    requiredOn: controller.requiredOn,
                  ),
                ),
                child: Text(context.l10n.postVotingCategoryDefault),
              ),
              DToggle(
                pressed: controller.requiredOn,
                enabled: controller.canEdit,
                onPressedChanged: (value) => unawaited(
                  controller.save(
                    defaultOn: controller.defaultOn,
                    requiredOn: value,
                  ),
                ),
                child: Text(context.l10n.postVotingCategoryOnly),
              ),
            ],
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
