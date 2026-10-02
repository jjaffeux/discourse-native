import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';

Future<void> showChatChannelStatusDialog({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) {
  final lease = chat.captureSession(siteUrl);
  final dialogKey = GlobalKey<_ChannelStatusDialogState>();
  return showDDialog<void>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: () => !(dialogKey.currentState?._saving ?? false),
    builder: (context, dialog) => _ChannelStatusDialog(
      key: dialogKey,
      chat: chat,
      siteUrl: siteUrl,
      channel: channel,
      lease: lease,
      dialog: dialog,
    ),
  );
}

class _ChannelStatusDialog extends StatefulWidget {
  const _ChannelStatusDialog({
    super.key,
    required this.chat,
    required this.siteUrl,
    required this.channel,
    required this.lease,
    required this.dialog,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;
  final PluginSiteLease lease;
  final DDialogController<void> dialog;

  @override
  State<_ChannelStatusDialog> createState() => _ChannelStatusDialogState();
}

class _ChannelStatusDialogState extends State<_ChannelStatusDialog> {
  bool _saving = false;
  String? _error;

  bool get _closing => widget.channel.status == ChatChannelStatus.open;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = widget.lease.isCurrent
        ? await widget.chat.setChannelClosed(
            widget.siteUrl,
            widget.channel.id,
            closed: _closing,
          )
        : appL10n.yourConnectionChangedReopenTheActionAndTryAgain;
    if (!mounted) return;
    final refusal = widget.lease.isCurrent
        ? error
        : appL10n.yourConnectionChangedReopenTheActionAndTryAgain;
    if (refusal != null) {
      setState(() {
        _saving = false;
        _error = refusal;
      });
      return;
    }
    _saving = false;
    widget.dialog.close();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('chat-channel-status-dialog'),
    showCloseButton: false,
    maxWidth: 512,
    semanticLabel: _closing
        ? context.l10n.closeChannel
        : context.l10n.openChannel,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(
              _closing ? context.l10n.closeChannel : context.l10n.openChannel,
            ),
          ),
        ],
      ),
      DDialogScrollArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DSpacing.md,
          children: [
            DDialogDescription(
              child: Text(
                _closing
                    ? context
                          .l10n
                          .closingTheChannelPreventsNonStaffUsersFromSendingNewMessages
                    : context
                          .l10n
                          .reopeningTheChannelLetsAllMembersSendMessagesAndEditTheir,
              ),
            ),
            if (_error case final error?)
              DAlert(
                key: const ValueKey('chat-channel-status-error'),
                variant: DAlertVariant.destructive,
                description: DAlertDescription(child: Text(error)),
              ),
          ],
        ),
      ),
      DDialogFooter(
        children: [
          DButton(
            label: Text(context.l10n.cancel),
            onPressed: _saving ? null : widget.dialog.close,
            variant: DButtonVariant.outline,
          ),
          DButton(
            key: const ValueKey('chat-channel-status-confirm'),
            label: Text(
              _closing ? context.l10n.closeChannel : context.l10n.openChannel,
            ),
            onPressed: _saving ? null : () => unawaited(_save()),
            variant: _closing
                ? DButtonVariant.destructive
                : DButtonVariant.primary,
            loading: _saving,
          ),
        ],
      ),
    ],
  );
}
