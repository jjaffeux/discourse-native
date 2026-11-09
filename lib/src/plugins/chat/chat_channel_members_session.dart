import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';

final class ChatChannelMembersSession extends ChangeNotifier {
  ChatChannelMembersSession({
    required ChatController chat,
    required String siteUrl,
    required int channelId,
    required this._membershipsCount,
  }) : _query = _MemberQuery(_MemberTarget(chat, siteUrl, channelId), '') {
    _observeTarget(_query.target);
  }

  static const _pageSize = 20;

  _MemberQuery _query;
  int _membershipsCount;
  Timer? _searchTimer;
  bool _disposed = false;
  int _notificationDepth = 0;

  List<ChatUser> get members => _query.members;
  String get filter => _query.filter;
  String? get error => _query.error;
  int get nextOffset => _query.nextOffset;
  bool get loading => _query.request != null;
  bool get loaded => _query.loaded;
  bool get canLoadMore => _query.canLoadMore;

  void bind({
    required ChatController chat,
    required String siteUrl,
    required int channelId,
    required int membershipsCount,
  }) {
    if (_disposed) return;
    final target = _query.target;
    if (target.lease.isCurrent &&
        identical(target.chat, chat) &&
        target.siteUrl == siteUrl &&
        target.channelId == channelId &&
        _membershipsCount == membershipsCount) {
      return;
    }
    _membershipsCount = membershipsCount;
    unawaited(_restart(target: _MemberTarget(chat, siteUrl, channelId)));
  }

  void filterChanged(String value) {
    if (_disposed) return;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      final filter = value.trim();
      if (_disposed || filter == _query.filter) return;
      unawaited(_restart(filter: filter));
    });
  }

  Future<void> refresh() => _restart();

  Future<void> _restart({_MemberTarget? target, String? filter}) {
    if (_disposed) return Future.value();
    final held = _query.target;
    target ??= held.lease.isCurrent
        ? held
        : _MemberTarget(held.chat, held.siteUrl, held.channelId);
    held.detach?.call();
    held.detach = null;
    _query = _MemberQuery(target, filter ?? _query.filter);
    _observeTarget(target);
    return loadMore();
  }

  void _observeTarget(_MemberTarget target) {
    target.detach = target.lease.onRetire(() {
      if (_disposed || !identical(_query.target, target)) return;
      target.detach?.call();
      target.detach = null;
      _searchTimer?.cancel();
      _query = _MemberQuery(target, _query.filter)..canLoadMore = false;
      _notify();
    });
  }

  Future<void> loadMore({bool prefetch = false}) async {
    if (_disposed) return;
    final query = _query;
    final paging = ScrollPagingGate(
      hasMore: query.canLoadMore,
      busy: query.request != null,
      lastPageFailed: prefetch && query.error != null,
    );
    if (!query.target.lease.isCurrent || !paging.admits) return;
    final request = _MemberRequest(query: query, offset: query.nextOffset);
    query.request = request;
    query.error = null;
    _notify();
    if (!_isCurrent(request)) return;

    final result = await query.target.chat.fetchChannelMembers(
      query.target.siteUrl,
      query.target.channelId,
      username: query.filter,
      offset: request.offset,
      limit: _pageSize,
    );
    if (!_isCurrent(request)) return;
    query.request = null;
    query.loaded = true;
    query.error = result.error;
    final page = result.page;
    if (page != null) {
      // Server progress includes duplicate and malformed rows.
      query.nextOffset = request.offset + page.rowCount;
      final ids = query._members.map((member) => member.id).toSet();
      query._members.addAll(page.members.where((member) => ids.add(member.id)));
      query.canLoadMore = page.canLoadMore && page.rowCount > 0;
    }
    _notify();
  }

  bool _isCurrent(_MemberRequest request) =>
      !_disposed &&
      request.query.target.lease.isCurrent &&
      identical(_query, request.query) &&
      identical(_query.request, request);

  void _notify() {
    _notificationDepth++;
    try {
      notifyListeners();
    } finally {
      _notificationDepth--;
      if (_disposed && _notificationDepth == 0) super.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _searchTimer?.cancel();
    _query.target.detach?.call();
    _query.target.detach = null;
    if (_notificationDepth == 0) super.dispose();
  }
}

final class _MemberTarget {
  _MemberTarget(this.chat, this.siteUrl, this.channelId)
    : lease = chat.captureAccount(siteUrl);

  final ChatController chat;
  final String siteUrl;
  final int channelId;
  final PluginSiteLease lease;
  VoidCallback? detach;
}

final class _MemberQuery {
  _MemberQuery(this.target, this.filter);

  final _MemberTarget target;
  final String filter;
  final _members = <ChatUser>[];
  late final List<ChatUser> members = UnmodifiableListView(_members);
  _MemberRequest? request;
  String? error;
  int nextOffset = 0;
  bool loaded = false;
  bool canLoadMore = true;
}

final class _MemberRequest {
  const _MemberRequest({required this.query, required this.offset});

  final _MemberQuery query;
  final int offset;
}
