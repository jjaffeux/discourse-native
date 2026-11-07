// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'ai_conversations_service.dart';

final class AiConversationsState {
  AiConversationsState({
    Iterable<AiConversation> conversations = const [],
    this.loading = true,
    this.hasMore = false,
    this.unavailable = false,
    this.error = false,
    this.retryMore = false,
    this.page = -1,
  }) : conversations = List.unmodifiable(conversations);

  final List<AiConversation> conversations;
  final bool loading;
  final bool hasMore;
  final bool unavailable;
  final bool error;
  final bool retryMore;
  final int page;
}

/// Owns the account, rows, and cursor for one mounted AI conversation route.
final class AiConversationsSession extends FrameSafeNotifier {
  AiConversationsSession({
    required PluginSiteLease account,
    required Future<AiConversationPage?> Function(int page) load,
    required void Function(AiConversation conversation) open,
  }) : _account = account,
       _load = load,
       _open = open {
    final detach = account.onRetire(_retire);
    if (_retired) {
      detach();
    } else {
      _detachRetirement = detach;
    }
  }

  final PluginSiteLease _account;
  final Future<AiConversationPage?> Function(int page) _load;
  final void Function(AiConversation conversation) _open;
  void Function()? _detachRetirement;
  Object? _request;
  bool _retired = false;
  AiConversationsState _state = AiConversationsState();

  AiConversationsState get state => _state;
  bool get isCurrent => !isDisposed && !_retired && _account.isCurrent;

  Future<void> refresh() => _loadPage(more: false);

  Future<void> loadMore() {
    if (!isCurrent || _state.loading || !_state.hasMore) return Future.value();
    return _loadPage(more: true);
  }

  Future<void> retry() {
    if (!isCurrent || _state.loading) return Future.value();
    return _loadPage(more: _state.retryMore);
  }

  void open(AiConversation conversation) {
    if (isCurrent && _state.conversations.contains(conversation)) {
      _open(conversation);
    }
  }

  Future<void> _loadPage({required bool more}) async {
    if (!isCurrent) return;
    final held = _state;
    final request = Object();
    _request = request;
    _state = AiConversationsState(
      conversations: held.conversations,
      loading: true,
      hasMore: held.hasMore,
      retryMore: more,
      page: held.page,
    );
    notifySafely();
    if (!_owns(request)) return;
    try {
      final result = await _load(more ? held.page + 1 : 0);
      if (!_owns(request)) return;
      if (result == null) {
        _retire();
        return;
      }
      final seen = <int>{};
      _state = AiConversationsState(
        conversations: [
          for (final conversation in [
            if (more) ...held.conversations,
            ...result.conversations,
          ])
            if (seen.add(conversation.id)) conversation,
        ],
        loading: false,
        hasMore: result.hasMore,
        page: result.page,
      );
    } catch (error) {
      if (!_owns(request)) return;
      _state = AiConversationsState(
        conversations: held.conversations,
        loading: false,
        hasMore: held.hasMore,
        error: true,
        unavailable: error is AiConversationsUnavailable,
        retryMore: more,
        page: held.page,
      );
    }
    if (!_owns(request)) return;
    _request = null;
    notifySafely();
  }

  bool _owns(Object request) => isCurrent && identical(_request, request);

  void _retire() {
    if (_retired || isDisposed) return;
    _retired = true;
    _request = null;
    _state = AiConversationsState(loading: false, unavailable: true);
    _detachRetirement?.call();
    _detachRetirement = null;
    notifySafely();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _retired = true;
    _request = null;
    _detachRetirement?.call();
    _detachRetirement = null;
    _state = AiConversationsState(loading: false, unavailable: true);
    super.dispose();
  }
}
