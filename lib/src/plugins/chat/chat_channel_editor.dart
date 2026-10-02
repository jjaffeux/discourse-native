import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';

Future<void> showChatChannelDetailsEditor({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) {
  final lease = chat.captureSession(siteUrl);
  final dialogKey = GlobalKey<_ChannelDetailsDialogState>();
  return showDDialog<void>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: () => !(dialogKey.currentState?._saving ?? false),
    builder: (context, dialog) => _ChannelDetailsDialog(
      key: dialogKey,
      chat: chat,
      siteUrl: siteUrl,
      channel: channel,
      dialog: dialog,
      lease: lease,
    ),
  );
}

class _ChannelDetailsDialog extends StatefulWidget {
  const _ChannelDetailsDialog({
    super.key,
    required this.chat,
    required this.siteUrl,
    required this.channel,
    required this.dialog,
    required this.lease,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;
  final DDialogController<void> dialog;
  final PluginSiteLease lease;

  @override
  State<_ChannelDetailsDialog> createState() => _ChannelDetailsDialogState();
}

class _ChannelDetailsDialogState extends State<_ChannelDetailsDialog> {
  late final _name = TextEditingController(text: widget.channel.title);
  late final _slug = TextEditingController(text: widget.channel.slug ?? '');
  late final _description = TextEditingController(
    text: widget.channel.description ?? '',
  );
  bool _saving = false;
  String? _error;

  String? get _descriptionError =>
      _description.text.runes.length > ChatChannel.maxDescriptionLength
      ? appL10n.theChannelDescriptionCannotExceed500Characters
      : null;

  bool get _canSave {
    final slug = _slug.text.trim();
    return !_saving &&
        slug.isNotEmpty &&
        slug.length <= 100 &&
        _descriptionError == null &&
        (_name.text.trim() != widget.channel.title ||
            slug != widget.channel.slug ||
            _description.text != (widget.channel.description ?? ''));
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim();
    final slug = _slug.text.trim();
    final titleChanged = name != widget.channel.title;
    final slugChanged = slug != widget.channel.slug;
    final descriptionChanged =
        _description.text != (widget.channel.description ?? '');
    final error = widget.lease.isCurrent
        ? await widget.chat.updateChannelMetadata(
            widget.siteUrl,
            widget.channel.id,
            name: titleChanged ? name : null,
            slug: slugChanged ? slug : null,
            description: descriptionChanged ? _description.text : null,
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
    key: const ValueKey('chat-channel-details-dialog'),
    showCloseButton: false,
    maxWidth: 512,
    semanticLabel: context.l10n.editChannelDetails,
    children: [
      DDialogHeader(
        children: [DDialogTitle(child: Text(context.l10n.editChannelDetails))],
      ),
      DDialogScrollArea(
        maxHeightFactor: .65,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DInput(
              key: const ValueKey('chat-channel-title-input'),
              controller: _name,
              autofocus: true,
              enabled: !_saving,
              onChanged: (_) => setState(() => _error = null),

              labelText: context.l10n.name,
            ),
            const SizedBox(height: 12),
            DInput(
              key: const ValueKey('chat-channel-slug-input'),
              controller: _slug,
              enabled: !_saving,
              maxLength: 100,
              onChanged: (_) => setState(() => _error = null),

              labelText: context.l10n.slug,
              helperText: context.l10n.usedInTheChannelURL,
            ),
            const SizedBox(height: 12),
            DTextarea(
              key: const ValueKey('chat-channel-description-input'),
              controller: _description,
              enabled: !_saving,
              minLines: 3,
              maxLines: 6,
              maxLength: ChatChannel.maxDescriptionLength,
              errorText: _descriptionError,
              onChanged: (_) => setState(() => _error = null),
              labelText: context.l10n.description,
            ),
            if (_error case final error?)
              DAlert(
                key: const ValueKey('chat-channel-details-error'),
                variant: DAlertVariant.destructive,
                description: DAlertDescription(child: Text(error)),
              ),
          ],
        ),
      ),
      DDialogFooter(
        children: [
          DDialogClose<void>(
            builder: (context, close) => DButton(
              label: Text(context.l10n.cancel),
              onPressed: _saving ? null : close,
              variant: DButtonVariant.outline,
            ),
          ),
          DButton(
            key: const ValueKey('chat-channel-details-save'),
            label: Text(context.l10n.save),
            onPressed: _canSave ? () => unawaited(_save()) : null,
            variant: DButtonVariant.primary,
            loading: _saving,
          ),
        ],
      ),
    ],
  );
}
