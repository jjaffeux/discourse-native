import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shell/composer_controller.dart';
import '../../shell/composer_panel.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../gifs/gif.dart';
import '../gifs/gif_picker.dart';
import 'chat_message.dart';

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
  bool _pickingGif = false;

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

  void _send(ComposerController composer) {
    final shell = _shell;
    if (shell == null ||
        _pickingGif ||
        composer.raw.trim().isEmpty ||
        composer.hasActiveUploads) {
      return;
    }
    final accepted = shell.chat.sendMessage(
      widget.siteUrl,
      widget.channelId,
      OutgoingChatMessage.text(composer.raw),
    );
    if (accepted == null) return;

    // Acceptance is the UI boundary: the row already exists and owns every
    // later delivery outcome. Start a clean document without waiting for
    // credentials, FIFO queueing, or the network.
    composer.focus.unfocus();
    composer.clearDocument();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_composer, composer)) {
        composer.focus.requestFocus();
      }
    });
  }

  Future<void> _pickGif() async {
    final shell = _shell;
    final composer = _composer;
    final sourceKey = _sourceKey;
    if (shell == null ||
        composer == null ||
        sourceKey == null ||
        _pickingGif ||
        !shell.siteConfigFor(widget.siteUrl).gifsEnabled ||
        !shell.chat.canSendMessage(widget.siteUrl, widget.channelId)) {
      return;
    }

    setState(() => _pickingGif = true);
    try {
      final result = await showGifPicker(
        context: context,
        siteUrl: widget.siteUrl,
        api: shell.api,
        credentials: shell.authenticator,
        lifecycle: shell.lifecycle,
        config: shell.siteConfigFor(widget.siteUrl),
      );
      if (result == null || !_ownsComposer(shell, composer, sourceKey)) {
        return;
      }
      _sendGif(shell, composer, sourceKey, result);
    } finally {
      if (mounted) setState(() => _pickingGif = false);
      _refocus(shell, composer, sourceKey);
    }
  }

  void _sendGif(
    ShellController shell,
    ComposerController composer,
    String sourceKey,
    GifResult result,
  ) {
    if (!_ownsComposer(shell, composer, sourceKey) ||
        !shell.chat.canSendMessage(widget.siteUrl, widget.channelId)) {
      return;
    }

    shell.chat.sendMessage(
      widget.siteUrl,
      widget.channelId,
      OutgoingChatMessage.trustedGif(
        raw: result.markdown,
        url: result.url,
        title: result.title,
        width: result.width,
        height: result.height,
      ),
    );
    // A picked GIF is its own outgoing message. Text already in the composer
    // is unrelated and remains untouched on both success and failure.
  }

  bool _ownsComposer(
    ShellController shell,
    ComposerController composer,
    String sourceKey,
  ) =>
      mounted &&
      identical(_shell, shell) &&
      identical(_composer, composer) &&
      _sourceKey == sourceKey;

  void _refocus(
    ShellController shell,
    ComposerController composer,
    String sourceKey,
  ) {
    if (!_ownsComposer(shell, composer, sourceKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownsComposer(shell, composer, sourceKey)) {
        composer.focus.requestFocus();
      }
    });
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
            if (composer.notice case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        const SingleActivator(LogicalKeyboardKey.enter): () => _send(composer),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _send(composer),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: composer.focus.requestFocus,
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
            ),
            ShellSelector<bool>(
              select: (shell) =>
                  shell.siteConfigFor(composer.target.siteUrl).gifsEnabled,
              builder: (context, gifsEnabled, _) => gifsEnabled
                  ? IconButton(
                      key: const ValueKey('chat-composer-gif'),
                      onPressed:
                          _pickingGif ||
                              !(_shell?.chat.canSendMessage(
                                    widget.siteUrl,
                                    widget.channelId,
                                  ) ??
                                  false)
                          ? null
                          : () => unawaited(_pickGif()),
                      icon: const DIcon(DIcons.gif, size: 18),
                      tooltip: 'Send GIF',
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: composer.text,
              builder: (context, value, _) => IconButton(
                key: const ValueKey('chat-composer-send'),
                onPressed:
                    _pickingGif ||
                        value.text.trim().isEmpty ||
                        composer.hasActiveUploads
                    ? null
                    : () => _send(composer),
                icon: const DIcon(DIcons.paperPlane, size: 18),
                tooltip: 'Send message',
                color: theme.colorScheme.primary,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: composer.focus.requestFocus,
              child: const SizedBox(width: 4),
            ),
          ],
        ),
      ),
    );
  }
}
