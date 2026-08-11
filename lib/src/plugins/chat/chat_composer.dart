import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/discourse_api_contracts.dart';
import '../../shell/composer_controller.dart';
import '../../shell/composer_panel.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';

/// A compact composer pinned underneath one chat stream.
///
/// It deliberately owns no scrolling or floating geometry. [ChatChannelView]
/// puts it after the expanded message viewport, so the messages move behind a
/// stable input at the bottom of the page. The field itself is the same
/// [ComposerEditor] topics use.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  ShellController? _shell;
  ComposerController? _composer;
  String? _sourceKey;
  bool _sending = false;
  String? _sendError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _useComposer(ShellScope.read(context));
  }

  void _useComposer(ShellController shell) {
    final sourceKey = '${widget.siteUrl}~${widget.channelId}';
    if (identical(_shell, shell) && _sourceKey == sourceKey) return;

    _composer?.dispose();
    final channel = shell.chat.channel(widget.siteUrl, widget.channelId);
    _shell = shell;
    _sourceKey = sourceKey;
    _composer = shell.buildChatComposer(
      siteUrl: widget.siteUrl,
      channelId: widget.channelId,
      channelTitle: channel?.title ?? 'Chat',
    );
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl == widget.siteUrl &&
        oldWidget.channelId == widget.channelId) {
      return;
    }
    _useComposer(_shell ?? ShellScope.read(context));
  }

  @override
  void dispose() {
    _composer?.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final shell = _shell;
    final composer = _composer;
    if (shell == null ||
        composer == null ||
        _sending ||
        composer.raw.isEmpty ||
        composer.hasActiveUploads) {
      return;
    }

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final sent = await shell.chat.sendMessage(
        widget.siteUrl,
        widget.channelId,
        composer.raw,
      );
      if (!mounted) return;
      if (sent) composer.clearDocument();
    } on WriteException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _sendError = const WriteException(
            WriteFailure.unreachable,
          ).message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        composer.focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final composer = _composer;
    if (composer == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (composer.uploads.isNotEmpty)
              ComposerUploadQueue(composer: composer),
            if (_sendError ?? composer.notice case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _sendError == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            _bar(context, composer),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, ComposerController composer) {
    final theme = Theme.of(context);
    final channel = _shell?.chat.channel(widget.siteUrl, widget.channelId);
    final hint = channel == null
        ? 'Message chat'
        : channel.isDirectMessage
        ? 'Message @${channel.title}'
        : 'Message #${channel.title}';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            unawaited(_send()),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            unawaited(_send()),
      },
      child: Container(
        key: const ValueKey('chat-composer'),
        height: 58,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.shell.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 0, 15),
                child: ComposerEditor(
                  composer: composer,
                  hintText: hint,
                  textStyle: theme.textTheme.bodyMedium,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: composer.text,
              builder: (context, value, _) => IconButton(
                key: const ValueKey('chat-composer-send'),
                onPressed:
                    _sending ||
                        value.text.trim().isEmpty ||
                        composer.hasActiveUploads
                    ? null
                    : () => unawaited(_send()),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const DIcon(DIcons.paperPlane, size: 18),
                tooltip: 'Send message',
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
