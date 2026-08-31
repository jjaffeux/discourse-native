import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/composer_upload.dart';
import '../../models/site_config.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/composer_autocomplete.dart';
import '../../shell/composer_controller.dart';
import '../../shell/composer_drop.dart';
import '../../shell/composer_link.dart';
import '../../shell/composer_panel.dart';
import '../../shell/emoji_composer.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/platform.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../gifs/gifs_contract.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_emoji_usage.dart';
import 'chat_message.dart';
import 'chat_plugin.dart';
import 'chat_services.dart';
import 'chat_stream_target.dart';

class ChatUploadDropController {
  ComposerController? _composer;
  bool Function()? _canAccept;

  bool get canAccept =>
      _composer?.imageUploader != null && (_canAccept?.call() ?? false);

  void attach(
    ComposerController composer, {
    required bool Function() canAccept,
  }) {
    _composer = composer;
    _canAccept = canAccept;
  }

  void detach(ComposerController? composer) {
    if (!identical(_composer, composer)) return;
    _composer = null;
    _canAccept = null;
  }

  void addDroppedItems(Iterable<DropItem> items) {
    final composer = _composer;
    if (composer == null || !canAccept) return;
    if (dropContainsDirectory(items)) {
      composer.showNotice('Folders cannot be uploaded here.');
    }
    final selection = composer.text.selection;
    final offset = selection.isValid
        ? selection.extentOffset
        : composer.text.text.length;
    composer.addImages(composerUploadFilesFromDrop(items), offset);
    composer.focus.requestFocus();
  }
}

/// The web app binds chat uploads to the channel/thread root, not its textarea.
class ChatUploadDropRegion extends StatefulWidget {
  const ChatUploadDropRegion({
    super.key,
    required this.controller,
    required this.title,
    required this.child,
  });

  final ChatUploadDropController controller;
  final String title;
  final Widget child;

  @override
  State<ChatUploadDropRegion> createState() => _ChatUploadDropRegionState();
}

class _ChatUploadDropRegionState extends State<ChatUploadDropRegion> {
  bool _dragging = false;

  void _entered(DropEventDetails _) {
    if (widget.controller.canAccept && !_dragging) {
      setState(() => _dragging = true);
    }
  }

  void _exited(DropEventDetails _) {
    if (_dragging) setState(() => _dragging = false);
  }

  void _dropped(DropDoneDetails details) {
    if (_dragging) setState(() => _dragging = false);
    widget.controller.addDroppedItems(details.files);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    key: const ValueKey('chat-upload-drop-target'),
    enable: !context.isTouch,
    onDragEntered: _entered,
    onDragExited: _exited,
    onDragDone: _dropped,
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                label: widget.title,
                child: DecoratedBox(
                  key: const ValueKey('chat-upload-drop-overlay'),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.94),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.siteUrl,
    required this.channelId,
    this.threadId,
    this.focusRequest = 0,
    this.uploadDropController,
    this.editingMessage,
    this.onEditFinished,
  });

  final String siteUrl;
  final int channelId;
  final int? threadId;
  final ChatUploadDropController? uploadDropController;
  final ChatMessage? editingMessage;
  final VoidCallback? onEditFinished;

  /// A counter lets repeated Reply actions refocus an already-open thread.
  final int focusRequest;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  PluginComposerHost? _host;
  PluginEmojiHost? _emoji;
  ChatController? _chat;
  ComposerController? _composer;
  String? _sourceKey;
  bool _pickingGif = false;
  bool _pickingEmoji = false;
  bool _savingEdit = false;

  void _closeDisabledEmojiAutocomplete(bool emojiEnabled) {
    final composer = _composer;
    if (emojiEnabled || composer == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !(_host?.siteConfigFor(widget.siteUrl).emojiEnabled ?? true)) {
        composer.closeEmojiAutocomplete();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _useComposer(
      PluginUiScope.require(context, chatComposerHostService),
      PluginUiScope.require(context, chatEmojiHostService),
      PluginUiScope.require(context, chatControllerService),
    );
  }

  void _useComposer(
    PluginComposerHost host,
    PluginEmojiHost emoji,
    ChatController chat,
  ) {
    final sourceKey =
        '${widget.siteUrl}~${widget.channelId}~${widget.threadId ?? 'channel'}';
    if (identical(_host, host) &&
        identical(_emoji, emoji) &&
        identical(_chat, chat) &&
        _sourceKey == sourceKey) {
      return;
    }

    widget.uploadDropController?.detach(_composer);
    _composer?.dispose();
    final channel = chat.channel(widget.siteUrl, widget.channelId);
    _host = host;
    _emoji = emoji;
    _chat = chat;
    _sourceKey = sourceKey;
    _composer = host.buildComposer(
      ComposerTargetRequest(
        kind: ChatPlugin.messageComposerTarget,
        siteUrl: widget.siteUrl,
        title: channel?.title ?? 'Chat',
        data: {
          ChatPlugin.composerChannelId: widget.channelId,
          ChatPlugin.composerThreadId: ?widget.threadId,
        },
      ),
    );
    final composer = _composer;
    if (composer == null) return;
    widget.uploadDropController?.attach(
      composer,
      canAccept: () =>
          mounted &&
          !_savingEdit &&
          (_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false),
    );
    if (widget.editingMessage case final message?) {
      _replaceWithMessage(composer, message, sourceKey);
    }
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
    if (!identical(
      oldWidget.uploadDropController,
      widget.uploadDropController,
    )) {
      oldWidget.uploadDropController?.detach(_composer);
      if (_composer case final composer?) {
        widget.uploadDropController?.attach(
          composer,
          canAccept: () =>
              mounted &&
              !_savingEdit &&
              (_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false),
        );
      }
    }
    final sameTarget =
        oldWidget.siteUrl == widget.siteUrl &&
        oldWidget.channelId == widget.channelId &&
        oldWidget.threadId == widget.threadId;
    if (sameTarget) {
      if (oldWidget.editingMessage?.id != widget.editingMessage?.id) {
        if (widget.editingMessage case final message?) {
          _replaceWithMessage(_composer!, message, _sourceKey!);
        } else {
          _composer?.clearDocument();
        }
      }
      if (oldWidget.focusRequest != widget.focusRequest &&
          widget.focusRequest > 0) {
        _requestFocus(_sourceKey!);
      }
      return;
    }
    _useComposer(
      _host ?? PluginUiScope.require(context, chatComposerHostService),
      _emoji ?? PluginUiScope.require(context, chatEmojiHostService),
      _chat ?? PluginUiScope.require(context, chatControllerService),
    );
  }

  @override
  void dispose() {
    widget.uploadDropController?.detach(_composer);
    _composer?.dispose();
    super.dispose();
  }

  void _send(ComposerController composer) {
    final host = _host;
    final chat = _chat;
    if (host == null ||
        chat == null ||
        _savingEdit ||
        _pickingGif ||
        _pickingEmoji ||
        !composer.canSubmit ||
        composer.hasActiveUploads) {
      return;
    }
    if (widget.editingMessage case final message?) {
      unawaited(_saveEdit(composer, chat, message));
      return;
    }
    final accepted = chat.sendMessageTo(
      widget.siteUrl,
      _target,
      OutgoingChatMessage.text(
        composer.raw,
        uploads: composer.completedUploads,
      ),
    );
    if (accepted == null) return;

    // Once a row exists, it owns delivery; clear the document before queued I/O.
    composer.focus.unfocus();
    composer.clearDocument();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_composer, composer)) {
        composer.focus.requestFocus();
      }
    });
  }

  void _replaceWithMessage(
    ComposerController composer,
    ChatMessage message,
    String sourceKey,
  ) {
    composer.replacePluginDocument(
      raw: message.raw,
      uploads: [for (final upload in message.uploads) _composerUpload(upload)],
    );
    _requestFocus(sourceKey);
  }

  Future<void> _saveEdit(
    ComposerController composer,
    ChatController chat,
    ChatMessage message,
  ) async {
    if (_savingEdit) return;
    setState(() => _savingEdit = true);
    composer.showNotice(null);
    final originalUploads = {
      for (final upload in message.uploads) upload.id: upload,
    };
    final error = await chat.editMessage(
      widget.siteUrl,
      message.id,
      composer.raw,
      uploads: [
        for (final upload in composer.completedUploads)
          originalUploads[upload.id] ?? ChatUpload.fromComposerUpload(upload),
      ],
    );
    if (!mounted || !identical(_composer, composer)) return;
    setState(() => _savingEdit = false);
    if (error != null) {
      composer.showNotice(error);
      return;
    }
    final finish = widget.onEditFinished;
    if (finish != null) {
      finish();
    } else {
      composer.clearDocument();
    }
  }

  static ComposerUploadResult _composerUpload(ChatUpload upload) =>
      ComposerUploadResult(
        id: upload.id,
        originalFilename: upload.originalFilename,
        shortUrl: upload.url,
        url: upload.url,
        width: upload.width,
        height: upload.height,
        thumbnailUrl: upload.thumbnailUrl,
      );

  void _cancelEdit() {
    if (_savingEdit) return;
    final finish = widget.onEditFinished;
    if (finish != null) {
      finish();
    } else {
      _composer?.clearDocument();
    }
  }

  Future<void> _pickGif() async {
    final host = _host;
    final composer = _composer;
    final sourceKey = _sourceKey;
    final gifs = PluginUiScope.maybe(context, chatGifsService);
    if (host == null ||
        composer == null ||
        sourceKey == null ||
        gifs == null ||
        _pickingGif ||
        _pickingEmoji ||
        _savingEdit ||
        widget.editingMessage != null ||
        !gifs.isAvailable(widget.siteUrl) ||
        !(_chat?.canSendMessageTo(widget.siteUrl, _target) ?? false)) {
      return;
    }

    setState(() => _pickingGif = true);
    try {
      final result = await gifs.showPicker(
        context: context,
        siteUrl: widget.siteUrl,
      );
      if (result == null || !_ownsComposer(host, composer, sourceKey)) {
        return;
      }
      _sendGif(host, composer, sourceKey, result);
    } finally {
      if (mounted) setState(() => _pickingGif = false);
      _refocus(host, composer, sourceKey);
    }
  }

  Future<void> _pickEmoji({
    required BuildContext pickerContext,
    String initialQuery = '',
    Rect? anchor,
  }) async {
    final host = _host;
    final emoji = _emoji;
    final composer = _composer;
    final sourceKey = _sourceKey;
    if (host == null ||
        emoji == null ||
        composer == null ||
        sourceKey == null ||
        _pickingGif ||
        _pickingEmoji ||
        _savingEdit ||
        !host.siteConfigFor(widget.siteUrl).emojiEnabled ||
        !(_chat?.canSendMessage(widget.siteUrl, widget.channelId) ?? false)) {
      return;
    }

    setState(() => _pickingEmoji = true);
    try {
      await openEmojiPickerForComposer(
        context: pickerContext,
        emoji: emoji,
        composer: composer,
        pickerContext: chatEmojiUsageContext,
        stillOwns: () => _ownsComposer(host, composer, sourceKey),
        initialQuery: initialQuery,
        anchor: anchor,
      );
    } finally {
      if (mounted) setState(() => _pickingEmoji = false);
    }
  }

  void _sendGif(
    PluginComposerHost host,
    ComposerController composer,
    String sourceKey,
    GifResult result,
  ) {
    if (!_ownsComposer(host, composer, sourceKey) ||
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
    // A picked GIF is a separate message and never consumes draft text.
  }

  ChatStreamTarget get _target => switch (widget.threadId) {
    final threadId? => ChatThreadTarget(
      channelId: widget.channelId,
      threadId: threadId,
    ),
    null => ChatChannelTarget(widget.channelId),
  };

  bool _ownsComposer(
    PluginComposerHost host,
    ComposerController composer,
    String sourceKey,
  ) =>
      mounted &&
      identical(_host, host) &&
      identical(_composer, composer) &&
      _sourceKey == sourceKey;

  void _refocus(
    PluginComposerHost host,
    ComposerController composer,
    String sourceKey,
  ) {
    if (!_ownsComposer(host, composer, sourceKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownsComposer(host, composer, sourceKey)) {
        composer.focus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final composer = _composer;
    final host = _host;
    if (composer == null || host == null) return const SizedBox.shrink();

    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: PluginUiScope.require(
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
                if (widget.editingMessage case final message?)
                  _ChatComposerEditDetails(
                    message: message,
                    saving: _savingEdit,
                    onCancel: _cancelEdit,
                  ),
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
                _bar(context, composer, host),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    ComposerController composer,
    PluginComposerHost host,
  ) {
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
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            composer.toggleSelectedInlineCode,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
            unawaited(
              showComposerLinkDialog(context: context, composer: composer),
            ),
        if (widget.editingMessage != null)
          const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
      },
      child: Container(
        key: const ValueKey('chat-composer'),
        constraints: const BoxConstraints(minHeight: 58),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.shell.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: composer.focus.requestFocus,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 0, 15),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                      ),
                      child: ComposerEditor(
                        composer: composer,
                        expands: false,
                        enableDropTarget: widget.uploadDropController == null,
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
              ),
            ),
            ValueListenableBuilder<SiteConfig>(
              valueListenable: host.siteConfigListenableFor(
                composer.target.siteUrl,
              ),
              builder: (context, config, _) {
                final emojiEnabled = config.emojiEnabled;
                _closeDisabledEmojiAutocomplete(emojiEnabled);
                return emojiEnabled
                    ? EmojiPickerAnchor(
                        child: Center(
                          heightFactor: 1,
                          child: Builder(
                            builder: (buttonContext) => DButton.iconOnly(
                              key: const ValueKey('chat-composer-emoji'),
                              onPressed:
                                  _pickingGif ||
                                      _pickingEmoji ||
                                      _savingEdit ||
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
                              variant: DButtonVariant.flat,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
            ValueListenableBuilder<SiteConfig>(
              valueListenable: host.siteConfigListenableFor(
                composer.target.siteUrl,
              ),
              builder: (context, _, _) {
                final gifs = PluginUiScope.maybe(context, chatGifsService);
                return gifs?.isAvailable(widget.siteUrl) ?? false
                    ? Center(
                        heightFactor: 1,
                        child: DButton.iconOnly(
                          key: const ValueKey('chat-composer-gif'),
                          onPressed:
                              _pickingGif ||
                                  _pickingEmoji ||
                                  _savingEdit ||
                                  widget.editingMessage != null ||
                                  !(_chat?.canSendMessage(
                                        widget.siteUrl,
                                        widget.channelId,
                                      ) ??
                                      false)
                              ? null
                              : () => unawaited(_pickGif()),
                          icon: const DIcon(DIcons.paperclip, size: 18),
                          tooltip: 'Send GIF',
                          variant: DButtonVariant.flat,
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: composer.text,
              builder: (context, _, _) => Center(
                heightFactor: 1,
                child: DButton.iconOnly(
                  key: const ValueKey('chat-composer-send'),
                  onPressed:
                      _pickingGif ||
                          _pickingEmoji ||
                          _savingEdit ||
                          !composer.canSubmit ||
                          composer.hasActiveUploads ||
                          !(_chat?.canSendMessageTo(widget.siteUrl, _target) ??
                              false)
                      ? null
                      : () => _send(composer),
                  icon: _savingEdit
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const DIcon(DIcons.paperPlane, size: 18),
                  tooltip: widget.editingMessage == null
                      ? 'Send message'
                      : 'Save edit',
                  variant: DButtonVariant.transparentPrimary,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: composer.focus.requestFocus,
              child: const SizedBox(width: 4, height: 56),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatComposerEditDetails extends StatelessWidget {
  const _ChatComposerEditDetails({
    required this.message,
    required this.saving,
    required this.onCancel,
  });

  final ChatMessage message;
  final bool saving;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final excerpt = message.raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final author = message.author.username.isEmpty
        ? message.author.displayName
        : '@${message.author.username}';
    return Container(
      key: const ValueKey('chat-composer-editing'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const DIcon(DIcons.pencil, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (excerpt.isNotEmpty)
                  Text(
                    excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('chat-composer-edit-cancel'),
            onPressed: saving ? null : onCancel,
            icon: const DIcon(DIcons.xmark, size: 16),
            tooltip: 'Cancel edit',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
