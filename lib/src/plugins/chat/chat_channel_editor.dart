import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/d_button.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';

Future<void> showChatChannelTitleEditor({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _ChannelTitleDialog(chat: chat, siteUrl: siteUrl, channel: channel),
);

Future<void> showChatChannelDescriptionEditor({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatChannel channel,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _ChannelDescriptionDialog(chat: chat, siteUrl: siteUrl, channel: channel),
);

class _ChannelTitleDialog extends StatefulWidget {
  const _ChannelTitleDialog({
    required this.chat,
    required this.siteUrl,
    required this.channel,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;

  @override
  State<_ChannelTitleDialog> createState() => _ChannelTitleDialogState();
}

class _ChannelTitleDialogState extends State<_ChannelTitleDialog> {
  late final _name = TextEditingController(text: widget.channel.title);
  late final _slug = TextEditingController(text: widget.channel.slug ?? '');
  bool _saving = false;
  String? _error;

  bool get _canSave {
    final slug = _slug.text.trim();
    return !_saving &&
        slug.isNotEmpty &&
        slug.length <= 100 &&
        (_name.text.trim() != widget.channel.title ||
            slug != widget.channel.slug);
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.chat.updateChannelMetadata(
      widget.siteUrl,
      widget.channel.id,
      name: _name.text,
      slug: _slug.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('chat-channel-title-dialog'),
    title: const Text('Edit channel title'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('chat-channel-title-input'),
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('chat-channel-slug-input'),
            controller: _slug,
            enabled: !_saving,
            maxLength: 100,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Slug',
              helperText: 'Used in the channel URL',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error case final error?)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                key: const ValueKey('chat-channel-title-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('chat-channel-title-save'),
        label: const Text('Save'),
        onPressed: _canSave ? () => unawaited(_save()) : null,
        variant: DButtonVariant.primary,
        loading: _saving,
      ),
    ],
  );
}

class _ChannelDescriptionDialog extends StatefulWidget {
  const _ChannelDescriptionDialog({
    required this.chat,
    required this.siteUrl,
    required this.channel,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatChannel channel;

  @override
  State<_ChannelDescriptionDialog> createState() =>
      _ChannelDescriptionDialogState();
}

class _ChannelDescriptionDialogState extends State<_ChannelDescriptionDialog> {
  late final _description = TextEditingController(
    text: widget.channel.description ?? '',
  );
  bool _saving = false;
  String? _error;

  bool get _canSave =>
      !_saving &&
      _description.text.length <= 280 &&
      _description.text != (widget.channel.description ?? '');

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.chat.updateChannelMetadata(
      widget.siteUrl,
      widget.channel.id,
      description: _description.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('chat-channel-description-dialog'),
    title: const Text('Edit channel description'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('chat-channel-description-input'),
            controller: _description,
            autofocus: true,
            enabled: !_saving,
            minLines: 4,
            maxLines: 8,
            maxLength: 280,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error case final error?)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                key: const ValueKey('chat-channel-description-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('chat-channel-description-save'),
        label: const Text('Save'),
        onPressed: _canSave ? () => unawaited(_save()) : null,
        variant: DButtonVariant.primary,
        loading: _saving,
      ),
    ],
  );
}
