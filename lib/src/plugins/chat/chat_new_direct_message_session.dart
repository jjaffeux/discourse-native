import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'chat_controller.dart';
import 'chat_direct_message_search.dart';
import 'chat_plugin_data.dart';

final class ChatNewDirectMessageSession extends ChangeNotifier {
  ChatNewDirectMessageSession({
    required this.chat,
    required this.siteUrl,
    required this._lease,
  }) : _sender = chat.currentUserFor(siteUrl) {
    _showExistingChannels();
    chat.addListener(_sessionChanged);
    _sessionChanged();
  }

  final ChatController chat;
  final String siteUrl;
  final PluginSiteLease _lease;
  final DiscourseUser? _sender;
  _ConversationMode _mode = const _DirectEditing();
  _EditingActivity _activity = const _Idle();
  Timer? _debounce;
  int _revision = 0;
  String _searchText = '';
  List<ChatDirectMessageSearchItem> _results = const [];
  String? _error;

  int get revision => _revision;
  String get searchText => _searchText;
  List<ChatDirectMessageSearchItem> get results => _results;
  List<ChatDirectMessageSearchItem> get members => _mode.members;
  bool get composingGroup => _mode is _GroupEditing;
  bool get searching => _activity is _QueryAttempt;
  bool get opening => _activity is _OpeningAttempt;
  String? get error => _error;
  bool get staff => chat.currentUserFor(siteUrl)?.staff == true;
  int get maximumGroupMembers =>
      chat.siteConfigFor(siteUrl).chatMaximumDirectMessageUsers;
  bool get canUseGroupChat => staff || maximumGroupMembers > 1;
  int get membersCount => _countMembers(members);

  bool _checkSession() {
    if (_activity is _Retired) return false;
    if (_lease.isCurrent) return true;
    _sessionChanged();
    return false;
  }

  void _sessionChanged() {
    if (_lease.isCurrent || _activity is _Retired) return;
    _invalidate();
    _activity = const _Retired();
    _error = appL10n.yourConnectionChangedReopenTheActionAndTryAgain;
    notifyListeners();
  }

  void _invalidate() {
    _debounce?.cancel();
    _debounce = null;
    _revision++;
    _activity = const _Idle();
  }

  void _showExistingChannels() {
    final channels = [
      ...chat.directChannels(siteUrl),
      ...chat.publicChannels(siteUrl),
    ];
    final positions = {
      for (final (i, channel) in channels.indexed) channel.id: i,
    };
    channels.sort((a, b) {
      final activity = (b.lastMessageAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.lastMessageAt?.millisecondsSinceEpoch ?? 0,
      );
      return activity != 0
          ? activity
          : positions[a.id]!.compareTo(positions[b.id]!);
    });
    _results = List.unmodifiable([
      for (final channel in channels)
        ChatDirectMessageChannel(
          identifier: 'c-${channel.id}',
          matchQuality: 3,
          enabled: true,
          channel: channel,
        ),
    ]);
  }

  void changeQuery(String value) {
    if (!_checkSession() || opening) return;
    _invalidate();
    _searchText = value;
    _error = null;
    final term = value.trim();
    if (term.isEmpty) {
      if (composingGroup) {
        _results = const [];
      } else {
        _showExistingChannels();
      }
    } else {
      final attempt = _QueryAttempt(
        term: term,
        includeGroups: canUseGroupChat,
        includeChannels: !composingGroup,
      );
      _activity = attempt;
      _results = const [];
      _debounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_search(attempt)),
      );
    }
    notifyListeners();
  }

  bool _isCurrent(_EditingActivity attempt) =>
      _checkSession() && identical(_activity, attempt);

  Future<void> _search(_QueryAttempt attempt) async {
    if (!_isCurrent(attempt)) return;
    try {
      final answer = await chat.searchDirectMessages(
        siteUrl,
        attempt.term,
        includeGroups: attempt.includeGroups,
        includeDirectMessageChannels: attempt.includeChannels,
        includeCategoryChannels: attempt.includeChannels,
      );
      if (!_isCurrent(attempt)) return;
      _activity = const _Idle();
      _results = answer.items;
    } catch (error) {
      if (!_isCurrent(attempt)) return;
      _activity = const _Idle();
      _error = _messageFor(error, fallback: appL10n.couldNotSearchChat);
    }
    notifyListeners();
  }

  bool _acceptsResult(int revision) =>
      _checkSession() && _activity is _Idle && revision == _revision;

  Future<ChatNewConversationDestination?> select(
    ChatDirectMessageSearchItem item,
    int revision,
  ) async {
    if (!_acceptsResult(revision) || !item.enabled) return null;
    if (composingGroup) {
      _addMember(item);
      return null;
    }
    if (item case ChatDirectMessageGroup()) {
      _startGroup(revision, initialGroup: item);
      return null;
    }
    if (item case ChatDirectMessageChannel(:final channel)) {
      return ChatNewConversationDestination._(channel.id, _revision, null);
    }
    final user = item as ChatDirectMessageUser;
    return _open(_OpeningAttempt(usernames: [user.username], upsert: true));
  }

  bool startGroup(int revision) => _startGroup(revision);

  bool _startGroup(int revision, {ChatDirectMessageGroup? initialGroup}) {
    final initialMembers = <ChatDirectMessageSearchItem>[?initialGroup];
    if (!_acceptsResult(revision) || !canUseGroupChat || composingGroup) {
      return false;
    }
    if (initialMembers.any((member) => !canAddMember(member))) {
      _memberLimitError();
      return false;
    }
    _invalidate();
    _mode = _GroupEditing(initialMembers);
    _clearSearch();
    notifyListeners();
    return true;
  }

  bool cancelGroup() {
    if (!_checkSession() || opening) return false;
    _invalidate();
    _mode = const _DirectEditing();
    _clearSearch();
    _showExistingChannels();
    notifyListeners();
    return true;
  }

  void _clearSearch() {
    _searchText = '';
    _results = const [];
    _error = null;
  }

  int _countMembers(Iterable<ChatDirectMessageSearchItem> selection) {
    final identifiers = <String>{};
    final usernames = <String>{};
    final senderUsername = _sender?.username.toLowerCase();
    final senderId = _sender?.id;
    var groupMembers = 0;
    for (final item in selection) {
      if (!identifiers.add(item.identifier)) continue;
      switch (item) {
        case ChatDirectMessageUser(:final username):
          final normalized = username.toLowerCase();
          final userId = item.identifier.startsWith('u-')
              ? int.tryParse(item.identifier.substring(2))
              : null;
          final isSender = senderId != null && userId != null
              ? userId == senderId
              : normalized == senderUsername;
          if (!isSender) usernames.add(normalized);
        case ChatDirectMessageGroup(:final memberCount):
          groupMembers += memberCount;
        case ChatDirectMessageChannel():
          break;
      }
    }
    return usernames.length + groupMembers;
  }

  bool canAddMember(ChatDirectMessageSearchItem item) =>
      item is! ChatDirectMessageChannel &&
      item.enabled &&
      (staff || _countMembers([...members, item]) <= maximumGroupMembers);

  void _memberLimitError() {
    _error = appL10n.aGroupChatCanIncludeUpToPeople(
      maximumGroupMembers.toString(),
    );
    notifyListeners();
  }

  void _addMember(ChatDirectMessageSearchItem item) {
    if (item is ChatDirectMessageChannel ||
        members.any((member) => member.identifier == item.identifier)) {
      return;
    }
    if (!canAddMember(item)) {
      _memberLimitError();
      return;
    }
    _invalidate();
    _mode = _GroupEditing([...members, item]);
    _clearSearch();
    notifyListeners();
  }

  void removeMember(ChatDirectMessageSearchItem item) {
    if (!_checkSession() || opening || !composingGroup) return;
    _mode = _GroupEditing(
      members.where((member) => member.identifier != item.identifier),
    );
    _error = null;
    notifyListeners();
  }

  Future<ChatNewConversationDestination?> createGroup(String name) async {
    if (!_checkSession() ||
        opening ||
        !composingGroup ||
        members.isEmpty ||
        (!staff && membersCount > maximumGroupMembers)) {
      return null;
    }
    return _open(
      _OpeningAttempt(
        usernames: [
          for (final member in members)
            if (member case ChatDirectMessageUser(:final username)) username,
        ],
        groups: [
          for (final member in members)
            if (member case ChatDirectMessageGroup(:final name)) name,
        ],
        name: name,
        upsert: false,
      ),
    );
  }

  Future<ChatNewConversationDestination?> _open(_OpeningAttempt attempt) async {
    _invalidate();
    _activity = attempt;
    _error = null;
    notifyListeners();
    if (!_isCurrent(attempt)) return null;
    try {
      final channel = attempt.upsert
          ? await chat.upsertDirectMessageChannel(
              siteUrl,
              attempt.usernames.single,
            )
          : await chat.createDirectMessageChannel(
              siteUrl,
              usernames: attempt.usernames,
              groups: attempt.groups,
              name: attempt.name,
            );
      if (!_isCurrent(attempt)) return null;
      return ChatNewConversationDestination._(channel?.id, _revision, attempt);
    } catch (error) {
      if (!_isCurrent(attempt)) return null;
      _activity = const _Idle();
      _error = _messageFor(
        error,
        fallback: attempt.upsert
            ? appL10n.couldNotStartThisChat
            : appL10n.couldNotCreateThisGroup,
      );
    }
    notifyListeners();
    return null;
  }

  void navigationFailed(ChatNewConversationDestination destination) {
    if (!_checkSession() ||
        destination._revision != _revision ||
        (destination._attempt != null &&
            !identical(_activity, destination._attempt))) {
      return;
    }
    _activity = const _Idle();
    _error = appL10n.thisConversationIsNoLongerAvailable;
    notifyListeners();
  }

  static String _messageFor(Object error, {required String fallback}) =>
      switch (error) {
        WriteException(errors: final errors) when errors.isNotEmpty =>
          errors.join('\n'),
        final WriteException error => error.message,
        _ => fallback,
      };

  @override
  void dispose() {
    chat.removeListener(_sessionChanged);
    _invalidate();
    _activity = const _Retired();
    super.dispose();
  }
}

final class ChatNewConversationDestination {
  const ChatNewConversationDestination._(
    this.channelId,
    this._revision,
    this._attempt,
  );
  final int? channelId;
  final int _revision;
  final _OpeningAttempt? _attempt;
  bool get requiresCurrentRoute => _attempt != null;
}

sealed class _ConversationMode {
  const _ConversationMode();
  List<ChatDirectMessageSearchItem> get members;
}

final class _DirectEditing extends _ConversationMode {
  const _DirectEditing();
  @override
  List<ChatDirectMessageSearchItem> get members => const [];
}

final class _GroupEditing extends _ConversationMode {
  _GroupEditing(Iterable<ChatDirectMessageSearchItem> members)
    : members = List.unmodifiable(members);
  @override
  final List<ChatDirectMessageSearchItem> members;
}

sealed class _EditingActivity {
  const _EditingActivity();
}

final class _Idle extends _EditingActivity {
  const _Idle();
}

final class _Retired extends _EditingActivity {
  const _Retired();
}

final class _QueryAttempt extends _EditingActivity {
  const _QueryAttempt({
    required this.term,
    required this.includeGroups,
    required this.includeChannels,
  });
  final String term;
  final bool includeGroups;
  final bool includeChannels;
}

final class _OpeningAttempt extends _EditingActivity {
  _OpeningAttempt({
    required Iterable<String> usernames,
    Iterable<String> groups = const [],
    this.name,
    required this.upsert,
  }) : usernames = List.unmodifiable(usernames),
       groups = List.unmodifiable(groups);
  final List<String> usernames;
  final List<String> groups;
  final String? name;
  final bool upsert;
}
