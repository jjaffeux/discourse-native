import 'package:flutter/widgets.dart';

import 'chat_controller.dart';
import 'chat_shell_service.dart';
import 'chat_stream_target.dart';

/// Owns a mounted pane's live subscription while its forum and ticker are active.
class ChatViewLifetime {
  ChatViewLifetime({
    required this.chat,
    required this.siteUrl,
    required this.target,
    this.onAcquire,
    this.onShellChanged,
  }) {
    if (target case final ChatThreadTarget thread) {
      _viewToken = chat.beginViewingThread(siteUrl, thread);
    }
  }

  final ChatController chat;
  final String siteUrl;
  final ChatStreamTarget target;
  final VoidCallback? onAcquire;
  final VoidCallback? onShellChanged;

  ChatShellService? _shell;
  Object? _viewToken;
  bool _viewStartScheduled = false;
  bool _disposed = false;
  bool _tickerEnabled = true;

  bool get tickerEnabled => _tickerEnabled;

  bool get _active =>
      !_disposed && _tickerEnabled && (_shell?.forumActive ?? false);

  void bind(ChatShellService shell, {required bool tickerEnabled}) {
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_handleShellChanged);
      _shell = shell..addListener(_handleShellChanged);
    }
    _tickerEnabled = tickerEnabled;
    _syncViewing();
  }

  void _handleShellChanged() {
    _syncViewing();
    onShellChanged?.call();
  }

  void _syncViewing() {
    if (!_active) {
      _release();
      return;
    }
    if (_viewToken != null || _viewStartScheduled) return;
    if (target is ChatThreadTarget) {
      _acquire();
      return;
    }
    _viewStartScheduled = true;
    // Advancing the channel record can notify a sibling header still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewStartScheduled = false;
      if (!_active || _viewToken != null) return;
      _acquire();
    });
  }

  void _acquire() {
    _viewToken = switch (target) {
      ChatChannelTarget(:final channelId) => chat.beginViewingChannel(
        siteUrl,
        channelId,
      ),
      final ChatThreadTarget thread => chat.beginViewingThread(siteUrl, thread),
    };
    onAcquire?.call();
  }

  void _release() {
    final token = _viewToken;
    _viewToken = null;
    if (token == null) return;
    switch (target) {
      case ChatChannelTarget(:final channelId):
        chat.endViewingChannel(siteUrl, channelId, token);
      case final ChatThreadTarget thread:
        chat.endViewingThread(siteUrl, thread, token);
    }
  }

  void dispose() {
    _disposed = true;
    _shell?.removeListener(_handleShellChanged);
    _release();
  }
}
