import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';

Future<void> showChatChannelDetailsEditor({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) => showDDialog<void>(
  context: context,
  dismissOnBarrier: false,
  builder: (context, dialog) => _ChannelDetailsDialog(
    chat: chat,
    siteUrl: siteUrl,
    channel: channel,
    dialog: dialog,
  ),
);

class _ChannelDetailsDialog extends StatefulWidget {
  const _ChannelDetailsDialog({
    required this.chat,
    required this.siteUrl,
    required this.channel,
    required this.dialog,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;
  final DDialogController<void> dialog;

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

  bool get _canSave {
    final slug = _slug.text.trim();
    return !_saving &&
        slug.isNotEmpty &&
        slug.length <= 100 &&
        _description.text.length <= 280 &&
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
    final error = await widget.chat.updateChannelMetadata(
      widget.siteUrl,
      widget.channel.id,
      name: titleChanged || slugChanged ? name : null,
      slug: titleChanged || slugChanged ? slug : null,
      description: descriptionChanged ? _description.text : null,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    widget.dialog.close();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('chat-channel-details-dialog'),
    showCloseButton: false,
    maxWidth: 512,
    semanticLabel: 'Edit channel details',
    children: [
      const DDialogHeader(
        children: [DDialogTitle(child: Text('Edit channel details'))],
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

              labelText: 'Name',
            ),
            const SizedBox(height: 12),
            DInput(
              key: const ValueKey('chat-channel-slug-input'),
              controller: _slug,
              enabled: !_saving,
              maxLength: 100,
              onChanged: (_) => setState(() => _error = null),

              labelText: 'Slug',
              helperText: 'Used in the channel URL',
            ),
            const SizedBox(height: 12),
            DTextarea(
              key: const ValueKey('chat-channel-description-input'),
              controller: _description,
              enabled: !_saving,
              minLines: 3,
              maxLines: 6,
              maxLength: 280,
              showCounter: true,
              onChanged: (_) => setState(() => _error = null),
              labelText: 'Description',
            ),
            if (_error case final error?)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  key: const ValueKey('chat-channel-details-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      DDialogFooter(
        children: [
          DDialogClose<void>(
            builder: (context, close) => DButton(
              label: const Text('Cancel'),
              onPressed: _saving ? null : close,
              variant: DButtonVariant.outline,
            ),
          ),
          DButton(
            key: const ValueKey('chat-channel-details-save'),
            label: const Text('Save'),
            onPressed: _canSave ? () => unawaited(_save()) : null,
            variant: DButtonVariant.primary,
            loading: _saving,
          ),
        ],
      ),
    ],
  );
}
