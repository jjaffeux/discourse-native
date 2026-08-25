import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shell/shell_sheet.dart';
import 'chat_controller.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

/// Opens core's thread-title setting without leaving the conversation.
Future<void> showChatThreadSettings({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatThreadTarget target,
  required ChatThread thread,
}) => showShellSheet<void>(
  context: context,
  title: 'Thread settings',
  dialogOnDesktop: true,
  builder: (context) => _ChatThreadSettingsEditor(
    chat: chat,
    siteUrl: siteUrl,
    target: target,
    thread: thread,
  ),
);

class _ChatThreadSettingsEditor extends StatefulWidget {
  const _ChatThreadSettingsEditor({
    required this.chat,
    required this.siteUrl,
    required this.target,
    required this.thread,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatThreadTarget target;
  final ChatThread thread;

  @override
  State<_ChatThreadSettingsEditor> createState() =>
      _ChatThreadSettingsEditorState();
}

class _ChatThreadSettingsEditorState extends State<_ChatThreadSettingsEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.thread.title ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.chat.updateThreadTitle(
      widget.siteUrl,
      widget.target,
      _title.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = 'Could not save the thread title. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('chat-thread-title-field'),
          controller: _title,
          autofocus: true,
          enabled: !_saving,
          maxLength: 100,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_save()),
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Give this thread a title',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('chat-thread-title-save'),
            onPressed: _saving ? null : () => unawaited(_save()),
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}
