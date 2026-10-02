import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_controller.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

Future<void> showChatThreadSettings({
  required BuildContext context,
  required ChatController chat,
  required String siteUrl,
  required ChatThreadTarget target,
  required ChatThread thread,
}) async {
  if (!chat.canEditThreadTitle(
    siteUrl,
    chat.thread(siteUrl, target.threadId),
  )) {
    return;
  }
  final session = chat.captureSession(siteUrl);
  await showShellSheet<void>(
    context: context,
    title: appL10n.threadSettings,
    dialogOnDesktop: true,
    builder: (context) => _ChatThreadSettingsEditor(
      chat: chat,
      siteUrl: siteUrl,
      target: target,
      thread: thread,
      session: session,
    ),
  );
}

class _ChatThreadSettingsEditor extends StatefulWidget {
  const _ChatThreadSettingsEditor({
    required this.chat,
    required this.siteUrl,
    required this.target,
    required this.thread,
    required this.session,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatThreadTarget target;
  final ChatThread thread;
  final PluginSiteLease session;

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
    if (_saving || !_canEdit) return;
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
      _error = appL10n.couldNotSaveTheThreadTitleTryAgain;
    });
  }

  bool get _canEdit =>
      widget.session.isCurrent &&
      widget.chat.canEditThreadTitle(
        widget.siteUrl,
        widget.chat.thread(widget.siteUrl, widget.target.threadId),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.chat.threadRef(widget.siteUrl, widget.target.threadId),
      widget.chat.channelRef(widget.siteUrl, widget.target.channelId),
    ]),
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DInput(
          key: const ValueKey('chat-thread-title-field'),
          controller: _title,
          autofocus: true,
          enabled: !_saving && _canEdit,
          maxLength: 100,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_save()),
          labelText: context.l10n.title,
          hintText: context.l10n.giveThisThreadATitle,
        ),
        if (!_canEdit) ...[
          const SizedBox(height: 8),
          Text(context.l10n.youCanNoLongerEditThisThreadTitle),
        ],
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
          child: DButton(
            key: const ValueKey('chat-thread-title-save'),
            label: Text(context.l10n.save),
            onPressed: _canEdit && !_saving ? () => unawaited(_save()) : null,
            variant: DButtonVariant.primary,
            loading: _saving,
          ),
        ),
      ],
    ),
  );
}
