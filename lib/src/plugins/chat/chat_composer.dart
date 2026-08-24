import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/emoji_picker_store.dart';
import '../../shell/composer_autocomplete.dart';
import '../../shell/composer_controller.dart';
import '../../shell/composer_panel.dart';
import '../../shell/emoji_composer.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../gifs/gif.dart';
import '../gifs/gif_picker.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_stream_target.dart';

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
    this.threadId,
    this.focusRequest = 0,
  });

  final String siteUrl;
  final int channelId;
  final int? threadId;

  /// A monotonically increasing request to focus this composer.
  ///
  /// A counter, rather than a boolean, lets repeatedly choosing Reply on an
  /// already-open thread focus it again without rebuilding the route.
  final int focusRequest;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  ShellController? _shell;
  ChatController? _chat;
  ComposerController? _composer;
  String? _sourceKey;
  bool _pickingGif = false;
  bool _pickingEmoji = false;

  void _closeDisabledEmojiAutocomplete(bool emojiEnabled) {
    final composer = _composer;
    if (emojiEnabled || composer == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !(_shell?.siteConfigFor(widget.siteUrl).emojiEnabled ?? true)) {
        composer.closeEmojiAutocomplete();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _useComposer(
      ShellScope.read(context),
      PluginScope.require(context, chatControllerService),
    );
  }

  void _useComposer(ShellController shell, ChatController chat) {
    final sourceKey =
        '${widget.siteUrl}~${widget.channelId}~${widget.threadId ?? 'channel'}';
    if (identical(_shell, shell) &&
        identical(_chat, chat) &&
        _sourceKey == sourceKey) {
      return;
    }

    _composer?.dispose();
    final channel = chat.channel(widget.siteUrl, widget.channelId);
    _shell = shell;
    _chat = chat;
    _sourceKey = sourceKey;
    _composer = shell.buildChatComposer(
      siteUrl: widget.siteUrl,
      channelId: widget.channelId,
      channelTitle: channel?.title ?? 'Chat',
      threadId: widget.threadId,
    );
    if (widget.focusRequest > 0) _requestFocus(sourceKey);
  }

  void _requestFocus(String sourceKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sourceKey == sourceKey) {
        _composer?.focus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameTarget =
        oldWidget.siteUrl == widget.siteUrl &&
        oldWidget.channelId == widget.channelId &&
        oldWidget.threadId == widget.threadId;
    if (sameTarget) {
      if (oldWidget.focusRequest != widget.focusRequest &&
          widget.focusRequest > 0) {
        _requestFocus(_sourceKey!);
      }
      return;
    }
    _useComposer(
      _shell ?? ShellScope.read(context),
      _chat ?? PluginScope.require(context, chatControllerService),
    );
  }

  @override
  void dispose() {
    _composer?.dispose();
    super.dispose();
  }

  void _send(ComposerController composer) {
    final shell = _shell;
    final chat = _chat;
    if (shell == null ||
        chat == null ||
        _pickingGif ||
        _pickingEmoji ||
        composer.raw.trim().isEmpty ||
        composer.hasActiveUploads) {
      return;
    }
    final accepted = chat.sendMessageTo(
      widget.siteUrl,
      _target,
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
        _pickingEmoji ||
        !shell.siteConfigFor(widget.siteUrl).gifsEnabled ||
        !(_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false)) {
      return;
    }

    setState(() => _pickingGif = true);
    try {
      final result = await showGifPicker(
        context: context,
        siteUrl: widget.siteUrl,
        api: shell.gifsApi,
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

  Future<void> _pickEmoji({
    required BuildContext pickerContext,
    String initialQuery = '',
    Rect? anchor,
  }) async {
    final shell = _shell;
    final composer = _composer;
    final sourceKey = _sourceKey;
    if (shell == null ||
        composer == null ||
        sourceKey == null ||
        _pickingGif ||
        _pickingEmoji ||
        !shell.siteConfigFor(widget.siteUrl).emojiEnabled ||
        !(_chat?.canSendMessage(widget.siteUrl, widget.channelId) ?? false)) {
      return;
    }

    setState(() => _pickingEmoji = true);
    try {
      await openEmojiPickerForComposer(
        context: pickerContext,
        shell: shell,
        composer: composer,
        pickerContext: EmojiPickerContext.chat,
        stillOwns: () => _ownsComposer(shell, composer, sourceKey),
        initialQuery: initialQuery,
        anchor: anchor,
      );
    } finally {
      if (mounted) setState(() => _pickingEmoji = false);
    }
  }

  void _sendGif(
    ShellController shell,
    ComposerController composer,
    String sourceKey,
    GifResult result,
  ) {
    if (!_ownsComposer(shell, composer, sourceKey) ||
        !(_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false)) {
      return;
    }

    _chat!.sendMessageTo(
      widget.siteUrl,
      _target,
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

  ChatStreamTarget get _target => switch (widget.threadId) {
    final threadId? => ChatThreadTarget(
      channelId: widget.channelId,
      threadId: threadId,
    ),
    null => ChatChannelTarget(widget.channelId),
  };

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

    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: PluginScope.require(
        context,
        chatControllerService,
      ).channelRef(widget.siteUrl, widget.channelId),
      builder: (context, channel, _) {
        if (channel != null &&
            !(_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false)) {
          return SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Container(
              key: const ValueKey('chat-composer-read-only'),
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).shell.divider),
              ),
              child: Text(
                channel.userSilenced
                    ? 'You cannot send chat messages.'
                    : 'This chat is read-only.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
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
      },
    );
  }

  Widget _bar(BuildContext context, ComposerController composer) {
    final theme = Theme.of(context);
    final channel = _chat?.channel(widget.siteUrl, widget.channelId);
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
                    onSuggestionAction:
                        ({
                          required context,
                          required composer,
                          required suggestion,
                          anchor,
                        }) async {
                          if (suggestion.action !=
                              ComposerSuggestionAction.openEmojiPicker) {
                            return;
                          }
                          await _pickEmoji(
                            pickerContext: context,
                            initialQuery:
                                composer.autocomplete.trigger?.query ??
                                suggestion.value,
                            anchor: anchor,
                          );
                        },
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
                  shell.siteConfigFor(composer.target.siteUrl).emojiEnabled,
              builder: (context, emojiEnabled, _) {
                _closeDisabledEmojiAutocomplete(emojiEnabled);
                return emojiEnabled
                    ? EmojiPickerAnchor(
                        child: Center(
                          child: Builder(
                            builder: (buttonContext) => IconButton(
                              key: const ValueKey('chat-composer-emoji'),
                              onPressed:
                                  _pickingGif ||
                                      _pickingEmoji ||
                                      !(_chat?.canSendMessage(
                                            widget.siteUrl,
                                            widget.channelId,
                                          ) ??
                                          false)
                                  ? null
                                  : () => unawaited(
                                      _pickEmoji(pickerContext: buttonContext),
                                    ),
                              icon: const DIcon(
                                DIcons.discourseEmojis,
                                size: 18,
                              ),
                              tooltip: 'Add emoji',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
            ShellSelector<bool>(
              select: (shell) =>
                  shell.siteConfigFor(composer.target.siteUrl).gifsEnabled,
              builder: (context, gifsEnabled, _) => gifsEnabled
                  ? Center(
                      child: IconButton(
                        key: const ValueKey('chat-composer-gif'),
                        onPressed:
                            _pickingGif ||
                                _pickingEmoji ||
                                !(_chat?.canSendMessage(
                                      widget.siteUrl,
                                      widget.channelId,
                                    ) ??
                                    false)
                            ? null
                            : () => unawaited(_pickGif()),
                        icon: const DIcon(DIcons.gif, size: 18),
                        tooltip: 'Send GIF',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: composer.text,
              builder: (context, value, _) => Center(
                child: IconButton(
                  key: const ValueKey('chat-composer-send'),
                  onPressed:
                      _pickingGif ||
                          _pickingEmoji ||
                          value.text.trim().isEmpty ||
                          composer.hasActiveUploads ||
                          !(_chat?.canSendMessageTo(widget.siteUrl, _target) ??
                              false)
                      ? null
                      : () => _send(composer),
                  icon: const DIcon(DIcons.paperPlane, size: 18),
                  tooltip: 'Send message',
                  color: theme.colorScheme.primary,
                ),
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
