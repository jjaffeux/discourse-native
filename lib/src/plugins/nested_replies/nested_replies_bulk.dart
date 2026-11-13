import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'nested_replies_bulk_controller.dart';

export 'nested_replies_bulk_controller.dart';

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
