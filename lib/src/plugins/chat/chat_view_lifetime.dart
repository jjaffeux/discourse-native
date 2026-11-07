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
    this.onReaderChanged,
  });

  final ChatController chat;
  final String siteUrl;
  final ChatStreamTarget target;
  final VoidCallback? onAcquire;
  final VoidCallback? onShellChanged;
  final VoidCallback? onReaderChanged;

  ChatShellService? _shell;
  ChatConversationReader? _reader;
  String? _readerId;
  ChatConversationReader get reader => _reader!;
  Object? _viewToken;
  bool _viewStartScheduled = false;
  bool _disposed = false;
  bool _tickerEnabled = true;

  bool get tickerEnabled => _tickerEnabled;

  bool get _active =>
      !_disposed && _tickerEnabled && (_shell?.forumActive ?? false);

  void bind(
    ChatShellService shell, {
    required bool tickerEnabled,
    String? readerId,
  }) {
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_handleShellChanged);
      _shell = shell..addListener(_handleShellChanged);
    }
    final id = readerId ?? 'view-${identityHashCode(this)}';
    if (_readerId != id || !(_reader?.isCurrent ?? false)) {
      _replaceReader(id);
    }
    _tickerEnabled = tickerEnabled;
    _syncViewing();
  }

  void _replaceReader(String id) {
    _release();
    _reader?.dispose();
    _readerId = id;
    _reader = chat.acquireReader(siteUrl, target, readerId: id);
  }

  void _handleShellChanged() {
    if (_readerId case final id? when !reader.isCurrent) {
      _replaceReader(id);
      onReaderChanged?.call();
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewStartScheduled = false;
      if (!_active || _viewToken != null) return;
      _acquire();
    });
  }

  void _acquire() {
    _viewToken = reader.beginViewing();
    onAcquire?.call();
  }

  void _release() {
    final token = _viewToken;
    _viewToken = null;
    if (token == null) return;
    reader.endViewing(token);
  }

  void dispose() {
    _disposed = true;
    _shell?.removeListener(_handleShellChanged);
    _release();
    _reader?.dispose();
  }
}
