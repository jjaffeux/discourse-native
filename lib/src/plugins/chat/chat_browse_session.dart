import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_inbox_filters.dart';

typedef _BrowseQuery = ({String filter, ChatChannelBrowseStatus status});

/// The query and server cursor for one mounted channel directory.
final class ChatBrowseSession extends ChangeNotifier {
  ChatBrowseSession({required this.chat, required this.siteUrl}) {
    final saved = chat.inboxFilters.browseFor(siteUrl);
    _query = (filter: saved.query, status: saved.status);
    _membership = saved.membership;
  }

  final ChatController chat;
  final String siteUrl;
  late _BrowseQuery _query;
  late ChatChannelJoinedFilter _membership;
  Timer? _debounce;
  _BrowseRequest? _request;
  bool _retired = false;
  List<ChatChannel> _channels = const [];
  int _nextOffset = 0;
  bool _hasMore = false;
  String? _error;

  String get query => _query.filter;
  ChatChannelBrowseStatus get status => _query.status;
  ChatChannelJoinedFilter get membership => _membership;
  bool get loading => _request?.reset == true;
  bool get loadingMore => _request?.reset == false;
  bool get hasMore => _hasMore;
  String? get error => _error;

  List<ChatChannel> get visibleChannels => switch (_membership) {
    ChatChannelJoinedFilter.all => _channels,
    ChatChannelJoinedFilter.joined => [
      for (final channel in _channels)
        if ((chat.channel(siteUrl, channel.id) ?? channel).membership.following)
          channel,
    ],
    ChatChannelJoinedFilter.notJoined => [
      for (final channel in _channels)
        if (!(chat.channel(siteUrl, channel.id) ?? channel)
            .membership
            .following)
          channel,
    ],
  };

  void changeQuery(String value) {
    if (_retired || value == query) return;
    _query = (filter: value, status: status);
    chat.inboxFilters.browseFor(siteUrl).query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _debounce = null;
      unawaited(refresh());
    });
  }

  void changeStatus(ChatChannelBrowseStatus value) {
    if (_retired || value == status) return;
    _query = (filter: query, status: value);
    chat.inboxFilters.browseFor(siteUrl).status = value;
    unawaited(refresh());
  }

  void changeMembership(ChatChannelJoinedFilter value) {
    if (_retired || value == _membership) return;
    _membership = value;
    chat.inboxFilters.browseFor(siteUrl).membership = value;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_retired) return Future.value();
    _debounce?.cancel();
    _debounce = null;
    return _load(reset: true);
  }

  /// Automatic prefetch waits for an explicit retry after a failed page.
  Future<void> loadMore({bool retry = false}) {
    if (_retired ||
        _debounce != null ||
        _request != null ||
        !_hasMore ||
        (_error != null && !retry)) {
      return Future.value();
    }
    return _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    final request = _BrowseRequest(
      query: _query,
      offset: reset ? 0 : _nextOffset,
      reset: reset,
    );
    _request = request;
    if (reset) _error = null;
    notifyListeners();
    if (_retired || !identical(_request, request)) return;
    final result = await chat.fetchBrowseChannels(
      siteUrl,
      filter: request.query.filter,
      status: request.query.status,
      offset: request.offset,
    );
    if (_retired || !identical(_request, request)) return;
    _request = null;
    _error = result.error;
    if (result.page case final page?) {
      _nextOffset = request.offset + page.rowCount;
      final ids = {for (final channel in _channels) channel.id};
      _channels = request.reset
          ? List.unmodifiable(page.channels)
          : List.unmodifiable([
              ..._channels,
              for (final channel in page.channels)
                if (ids.add(channel.id)) channel,
            ]);
      _hasMore = page.hasMore && page.rowCount > 0;
    } else if (request.reset) {
      _channels = const [];
      _hasMore = false;
    }
    notifyListeners();
  }

  void replaceChannel(ChatChannel channel) {
    if (_retired) return;
    final index = _channels.indexWhere((value) => value.id == channel.id);
    if (index < 0) return;
    _channels = List.unmodifiable([..._channels]..[index] = channel);
    notifyListeners();
  }

  @override
  void dispose() {
    _retired = true;
    _request = null;
    _debounce?.cancel();
    super.dispose();
  }
}

final class _BrowseRequest {
  const _BrowseRequest({
    required this.query,
    required this.offset,
    required this.reset,
  });

  final _BrowseQuery query;
  final int offset;
  final bool reset;
}
