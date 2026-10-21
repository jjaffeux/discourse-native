import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'shell_scope.dart';

class MessageCreateButton extends StatelessWidget {
  const MessageCreateButton({
    super.key,
    required this.showLabel,
    this.pill = false,
    this.dockAction = false,
  });

  final bool showLabel;
  final bool pill;

  /// Presents the button as the mobile dock's primary action.
  final bool dockAction;

  void _compose(BuildContext context) {
    final controller = ShellScope.read(context);
    final tab = ForumTabScope.tabOf(context);
    final instance = controller.currentInstance;
    final source = tab.topicListContent ?? tab.currentContent;
    if (!tab.isCurrent || controller.activeTabId != tab.tabId) return;
    if (instance == null || source?.isMessages != true) return;
    controller.openPrivateMessage(
      siteUrl: instance.url,
      targetRecipients: source!.messageGroupName ?? '',
    );
  }

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    select: (controller) =>
        controller.currentInstance?.isConnected == true &&
        controller.currentInstance?.user?.canSendPrivateMessages == true,
    builder: (context, permitted, _) {
      if (!permitted) return const SizedBox.shrink();
      if (dockAction) {
        return DMobileDockAction(
          buttonKey: const ValueKey('new-message-button'),
          icon: const DIcon(DIcons.penToSquare),
          label: context.l10n.newMessage,
          tinted: true,
          onPressed: () => _compose(context),
        );
      }
      final header = pill && !dockAction && !DControlStyle.isTouch(context);
      if (header && !showLabel) {
        return DButton(
          key: const ValueKey('new-message-button'),
          label: const DIcon(DIcons.penToSquare, size: 14),
          tooltip: context.l10n.newMessage,
          semanticLabel: context.l10n.newMessage,
          variant: DButtonVariant.primary,
          shape: DButtonShape.pill,
          size: DButtonSize.chrome,
          density: DButtonDensity.chrome,
          onPressed: () => _compose(context),
        );
      }
      final density = dockAction
          ? DButtonDensity.mobileDockAction
          : DButtonDensity.standard;
      final button = showLabel
          ? DButton(
              key: const ValueKey('new-message-button'),
              label: Text(context.l10n.newMessage, softWrap: true, maxLines: 2),
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: context.l10n.newMessage,
              variant: DButtonVariant.primary,
              size: DButtonSize.action,
              density: density,
              onPressed: () => _compose(context),
            )
          : DButton.iconOnly(
              shape: pill ? DButtonShape.pill : DButtonShape.rounded,
              key: const ValueKey('new-message-button'),
              icon: DIcon(pill ? DIcons.plus : DIcons.farPenToSquare),
              tooltip: context.l10n.newMessage,
              variant: DButtonVariant.primary,
              size: DButtonSize.action,
              density: density,
              onPressed: () => _compose(context),
            );
      return button;
    },
  );
}
