import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../data/plugin_transport.dart';
import '../../models/json.dart';
import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_direct_message_search.dart';
import 'chat_message.dart';
import 'chat_pin.dart';
import 'chat_reactors.dart';
import 'chat_search.dart';
import 'chat_thread.dart';

final class ChatApiClient implements ChatApi {
  const ChatApiClient(this._transport);

  static const int maximumSearchTermLength = 2048;

  final PluginApiTransport _transport;

  Future<Map<String, dynamic>> _getObject(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) => _transport.pluginGetJson(
    siteUrl: siteUrl,
    path: url.toString(),
    apiKey: apiKey,
    clientId: clientId,
  );

  Future<Map<String, dynamic>> _write(
    Uri url, {
    required String siteUrl,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => _transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: url.toString(),
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  @override
  Future<ChatDirectMessageSearchResults> searchChatDirectMessages({
    required String siteUrl,
    required String apiKey,
    required String term,
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    String? clientId,
  }) async {
    _validateComposerLookupValue(term);
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/chatables').replace(
        queryParameters: {
          'term': term,
          'include_users': 'true',
          'include_groups': '$includeGroups',
          'include_category_channels': 'false',
          'include_direct_message_channels': '$includeDirectMessageChannels',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatDirectMessageSearchResults.fromJson(body, siteUrl);
  }

  /// [upsert] is for one-to-one chats; group chats may legitimately share members.
  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) async {
    if (usernames.isEmpty && groups.isEmpty) {
      throw ArgumentError('A direct-message target is required.');
    }
    for (final value in [...usernames, ...groups]) {
      _validateComposerLookupValue(value);
    }
    if (name != null) _validateComposerLookupValue(name, allowEmpty: true);
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/direct-message-channels.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        if (usernames.isNotEmpty) 'target_usernames': usernames,
        if (groups.isNotEmpty) 'target_groups': groups,
        'upsert': upsert,
        'name': name,
      },
    );
    final channel = body['channel'];
    if (channel is! Map<String, dynamic>) {
      throw const FormatException('Missing direct-message chat channel.');
    }
    return ChatChannel.fromJson(channel, siteUrl);
  }

  /// The unpaginated server response caps public/direct channels at 100/75.
  @override
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/me/channels.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return ChatChannel.parse(body, siteUrl);
  }

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels/$channelId.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final channel = body['channel'];
    if (channel is! Map<String, dynamic>) {
      throw const FormatException('Missing chat channel.');
    }
    return ChatChannel.fromJson(channel, siteUrl);
  }

  /// Sends an empty description because core normalizes it to null for removal.
  @override
  Future<ChatChannel> updateChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (name == null &&
        slug == null &&
        description == null &&
        threadingEnabled == null) {
      throw ArgumentError('At least one channel field is required.');
    }
    final trimmedName = name?.trim();
    final trimmedSlug = slug?.trim();
    if (slug != null && (trimmedSlug == null || trimmedSlug.isEmpty)) {
      throw ArgumentError.value(slug, 'slug', 'must not be empty');
    }
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'channel': {
          'name': ?(name == null ? null : trimmedName),
          'slug': ?(slug == null ? null : trimmedSlug),
          'description': ?description,
          'threading_enabled': ?threadingEnabled,
        },
      },
    );
    final channel = body['channel'];
    if (channel is! Map<String, dynamic>) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return ChatChannel.fromJson(channel, siteUrl);
  }

  /// Only core's open/closed status service is valid here; archive states use a
  /// separate workflow.
  @override
  Future<ChatChannel> updateChatChannelStatus({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required ChatChannelStatus status,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (status != ChatChannelStatus.open &&
        status != ChatChannelStatus.closed) {
      throw ArgumentError.value(status, 'status', 'must be open or closed');
    }
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/status.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'status': status.name},
    );
    final channel = body['channel'];
    if (channel is! Map<String, dynamic>) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return ChatChannel.fromJson(channel, siteUrl);
  }

  @override
  Future<void> updateChatChannelStarred({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required bool starred,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/memberships/me.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'starred': starred},
    );
  }

  @override
  Future<ChatMembership> updateChatChannelNotifications({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (muted == null && notificationLevel == null) {
      throw ArgumentError(
        'At least one channel notification setting is required.',
      );
    }
    final settings = <String, Object?>{
      'muted': ?muted,
      'notification_level': ?notificationLevel?.name,
    };
    final body = await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/'
        'notifications-settings/me.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'notifications_settings': settings},
    );
    final membership = body['membership'];
    if (membership is! Map<String, dynamic>) {
      throw const FormatException('Missing chat channel membership.');
    }
    return ChatMembership.fromJson(membership);
  }

  @override
  Future<ChatChannelMembersPage> chatChannelMembers({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String username = '',
    int offset = 0,
    int limit = 20,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    final term = username.trim();
    if (term.length > maximumSearchTermLength) {
      throw ArgumentError.value(
        term.length,
        'username',
        'Member filters must be at most $maximumSearchTermLength characters.',
      );
    }
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'must be non-negative');
    }
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/memberships').replace(
        queryParameters: {
          'offset': '$offset',
          'limit': '$limit',
          if (term.isNotEmpty) 'username': term,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final members = List<ChatUser>.unmodifiable([
      for (final membership in jsonObjects(body['memberships']).take(limit))
        if (membership['user'] case final Map<String, dynamic> user)
          if (jsonIntOrNull(user['id']) case final id? when id > 0)
            ChatUser.fromJson(user, siteUrl),
    ]);
    return (
      members: members,
      totalRows: jsonInt(jsonObject(body['meta'])['total_rows']),
      canLoadMore: members.length == limit,
    );
  }

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    final term = filter.trim();
    if (term.length > maximumSearchTermLength) {
      throw ArgumentError.value(
        term.length,
        'filter',
        'Channel filters must be at most $maximumSearchTermLength characters.',
      );
    }
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'must be non-negative');
    }
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels').replace(
        queryParameters: {
          'status': status.name,
          'offset': '$offset',
          'limit': '$limit',
          if (term.isNotEmpty) 'filter': term,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatChannelBrowsePage.fromJson(body, siteUrl, limit: limit);
  }

  @override
  Future<ChatMembership> followChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _writeChatChannelFollowing(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    following: true,
    clientId: clientId,
  );

  @override
  Future<ChatMembership> unfollowChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _writeChatChannelFollowing(
    siteUrl: siteUrl,
    apiKey: apiKey,
    channelId: channelId,
    following: false,
    clientId: clientId,
  );

  Future<ChatMembership> _writeChatChannelFollowing({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required bool following,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    final suffix = following
        ? 'memberships/me.json'
        : 'memberships/me/follows.json';
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/$suffix'),
      siteUrl: siteUrl,
      method: following ? 'POST' : 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
    final membership = body['membership'];
    if (membership is! Map<String, dynamic>) {
      throw const FormatException('Missing chat channel membership.');
    }
    return ChatMembership.fromJson(membership);
  }

  @override
  Future<void> editChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String message,
    List<int> uploadIds = const [],
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'must not be blank');
    }
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/messages/$messageId.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'message': message, 'upload_ids': uploadIds},
    );
  }

  @override
  Future<void> deleteChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/messages/$messageId.json',
      ),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<void> deleteChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (messageIds.isEmpty ||
        messageIds.length > 200 ||
        messageIds.any((id) => id <= 0)) {
      throw ArgumentError.value(
        messageIds,
        'messageIds',
        'must contain between 1 and 200 positive ids',
      );
    }
    await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/messages.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'message_ids': messageIds},
    );
  }

  @override
  Future<ChatMessageMove> moveChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int destinationChannelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(destinationChannelId, 'destinationChannelId');
    if (channelId == destinationChannelId) {
      throw ArgumentError.value(
        destinationChannelId,
        'destinationChannelId',
        'must differ from channelId',
      );
    }
    if (messageIds.isEmpty || messageIds.any((id) => id <= 0)) {
      throw ArgumentError.value(
        messageIds,
        'messageIds',
        'must contain positive ids',
      );
    }
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/messages/moves.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'move': {
          'message_ids': messageIds,
          'destination_channel_id': destinationChannelId,
        },
      },
    );
    final returnedDestination = jsonIntOrNull(body['destination_channel_id']);
    final firstMovedMessage = jsonIntOrNull(body['first_moved_message_id']);
    if (returnedDestination == null || firstMovedMessage == null) {
      throw const FormatException('Missing chat message move destination.');
    }
    return (
      destinationChannelId: returnedDestination,
      firstMovedMessageId: firstMovedMessage,
    );
  }

  @override
  Future<void> restoreChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/messages/$messageId/restore.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<void> rebakeChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse('$siteUrl/chat/$channelId/$messageId/rebake.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<String> generateChatQuote({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (messageIds.isEmpty || messageIds.any((id) => id <= 0)) {
      throw ArgumentError.value(
        messageIds,
        'messageIds',
        'must contain positive ids',
      );
    }
    final body = await _write(
      Uri.parse('$siteUrl/chat/$channelId/quote.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'message_ids': messageIds},
    );
    final markdown = body['markdown'];
    if (markdown is! String || markdown.trim().isEmpty) {
      throw const FormatException('Missing chat quote markdown.');
    }
    return markdown;
  }

  /// Core encodes pin state in the HTTP method, not a boolean body.
  @override
  Future<void> updateChatMessagePinned({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required bool pinned,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/messages/$messageId/pin.json',
      ),
      siteUrl: siteUrl,
      method: pinned ? 'POST' : 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<ChatPins> chatPinnedMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/pins.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatPin.parse(body, siteUrl);
  }

  @override
  Future<void> markChatPinsRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/pins/read.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<void> flagChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required int flagTypeId,
    String? message,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    _requirePositiveId(flagTypeId, 'flagTypeId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/messages/$messageId/flags.json',
      ),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'flag_type_id': flagTypeId, 'message': ?message},
    );
  }

  @override
  Future<ChatSearchPage> searchChatMessages({
    required String siteUrl,
    required String apiKey,
    required String query,
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
    int limit = ChatSearchPage.defaultPageSize,
    bool excludeThreads = false,
    String? clientId,
  }) async {
    final term = query.trim();
    if (term.isEmpty) {
      throw ArgumentError.value(query, 'query', 'must not be blank');
    }
    if (term.length > maximumSearchTermLength) {
      throw ArgumentError.value(
        term.length,
        'query',
        'Search terms must be at most $maximumSearchTermLength characters.',
      );
    }
    if (channelId != null) _requirePositiveId(channelId, 'channelId');
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'must be non-negative');
    }
    if (limit < 1 || limit > ChatSearchPage.maximumPageSize) {
      throw RangeError.range(limit, 1, ChatSearchPage.maximumPageSize, 'limit');
    }

    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/search.json').replace(
        queryParameters: {
          'query': term,
          if (channelId != null) 'channel_id': '$channelId',
          'sort': sort.name,
          'offset': '$offset',
          'limit': '$limit',
          if (excludeThreads) 'exclude_threads': 'true',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatSearchPage.fromJson(body, siteUrl);
  }

  /// Exactly one window selector is allowed. Around-last-read ignores
  /// [pageSize], and every GET updates `last_viewed_at` without marking reads.
  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    _validateChatPageDirection(
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      fromLastRead: fromLastRead,
    );

    // Empty target params resolve to newest and make pagination repeat forever.
    final query = [
      'page_size=$pageSize',
      if (fromLastRead) 'fetch_from_last_read=true',
      if (targetMessageId != null) 'target_message_id=$targetMessageId',
      if (before != null) ...['direction=past', 'target_message_id=$before'],
      if (after != null) ...['direction=future', 'target_message_id=$after'],
    ].join('&');

    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/messages.json?$query'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return ChatMessage.parsePage(
      body,
      siteUrl,
      window: after == null
          ? (fromLastRead || targetMessageId != null
                ? ChatMessagePageWindow.aroundTarget
                : ChatMessagePageWindow.retainNewest)
          : ChatMessagePageWindow.retainOldest,
      maximumMessages: fromLastRead ? ChatMessage.maximumPageSize : pageSize,
    );
  }

  /// The server advances this cursor monotonically, so debounced writes may
  /// arrive out of order; exact counts arrive later on the tracking channel.
  @override
  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/read.json?message_id=$messageId',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    if (pageSize < 1 || pageSize > 50) {
      throw RangeError.range(pageSize, 1, 50, 'pageSize');
    }
    _validateChatPageDirection(
      before: before,
      after: after,
      targetMessageId: targetMessageId,
    );
    final query = [
      'page_size=$pageSize',
      if (targetMessageId != null) 'target_message_id=$targetMessageId',
      if (before != null) ...['direction=past', 'target_message_id=$before'],
      if (after != null) ...['direction=future', 'target_message_id=$after'],
    ].join('&');
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/threads/$threadId/messages.json?'
        '$query',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatMessage.parsePage(
      body,
      siteUrl,
      window: after == null
          // Without a target, the endpoint selects membership's last-read id.
          ? ChatMessagePageWindow.aroundTarget
          : ChatMessagePageWindow.retainOldest,
      maximumMessages: pageSize,
    );
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    final body = await _getObject(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/threads/$threadId.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatThread.fromJson(jsonObject(body['thread']), siteUrl);
  }

  @override
  Future<ChatThreadPage> chatThreads({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    if (offset < 0) throw RangeError.value(offset, 'offset');
    if (limit < 1 || limit > ChatThreadPage.pageSize) {
      throw RangeError.range(limit, 1, ChatThreadPage.pageSize, 'limit');
    }
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/chat/api/me/threads.json?limit=$limit&offset=$offset',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatThreadPage.fromJson(body, siteUrl);
  }

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (offset < 0) throw RangeError.value(offset, 'offset');
    if (limit < 1 || limit > ChatThreadPage.pageSize) {
      throw RangeError.range(limit, 1, ChatThreadPage.pageSize, 'limit');
    }
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/threads.json?'
        'limit=$limit&offset=$offset',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatThreadPage.fromJson(body, siteUrl);
  }

  @override
  Future<ChatThread> createChatThread({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int originalMessageId,
    String? title,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(originalMessageId, 'originalMessageId');
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/threads.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'original_message_id': originalMessageId, 'title': ?title},
    );
    return ChatThread.fromJson(body, siteUrl);
  }

  @override
  Future<void> updateChatThreadTitle({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required String title,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    await _write(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/threads/$threadId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'title': title},
    );
  }

  @override
  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    final body = await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/threads/$threadId/'
        'notifications-settings/me.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'notification_level': notificationLevel.value},
    );
    final membership = ChatThreadMembership.fromJson(body['membership']);
    if (membership == null) {
      throw const FormatException('Missing chat thread membership.');
    }
    return membership;
  }

  static void _validateChatPageDirection({
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
  }) {
    if (before != null) _requirePositiveId(before, 'before');
    if (after != null) _requirePositiveId(after, 'after');
    if (targetMessageId != null) {
      _requirePositiveId(targetMessageId, 'targetMessageId');
    }
    final shapes = [
      before != null,
      after != null,
      targetMessageId != null,
      fromLastRead,
    ];
    if (shapes.where((selected) => selected).length > 1) {
      throw ArgumentError('Only one pagination target may be selected.');
    }
  }

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static void _validateReactionName(String reaction) {
    if (reaction.isNotEmpty && reaction.length <= maximumSearchTermLength) {
      return;
    }
    // Plugin response values may reach diagnostics.
    throw ArgumentError(
      'Reaction names must contain between 1 and '
      '$maximumSearchTermLength characters.',
    );
  }

  static void _validateComposerLookupValue(
    String value, {
    bool allowEmpty = false,
  }) {
    if ((!allowEmpty && value.isEmpty) ||
        value.length > maximumSearchTermLength) {
      // Composer values can contain private names and may reach diagnostics.
      throw ArgumentError(
        'Composer lookup values must be ${allowEmpty ? 'at most' : 'between 1 and'} '
        '$maximumSearchTermLength characters.',
      );
    }
  }

  @override
  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    List<int> uploadIds = const [],
    int? threadId,
    String? stagedId,
    DateTime? clientCreatedAt,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    if (threadId != null) _requirePositiveId(threadId, 'threadId');
    if (message.trim().isEmpty && uploadIds.isEmpty) {
      throw ArgumentError.value(
        '',
        'message',
        'A message or upload is required.',
      );
    }
    if (uploadIds.length > ChatMessage.maximumUploadsPerMessage ||
        uploadIds.any((id) => id <= 0)) {
      throw ArgumentError.value(uploadIds, 'uploadIds', 'Invalid upload IDs.');
    }
    final body = await _write(
      Uri.parse('$siteUrl/chat/$channelId.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'message': message,
        'upload_ids': uploadIds.isEmpty ? null : uploadIds,
        'thread_id': threadId,
        'staged_id': stagedId,
        'client_created_at': clientCreatedAt?.toUtc().toIso8601String(),
      },
    );
    return jsonIntOrNull(body['message_id']);
  }

  /// The reaction route requires an explicit action and returns no message state.
  @override
  Future<void> setChatMessageReaction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String emoji,
    required ChatReactionAction action,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    _validateReactionName(emoji);
    await _write(
      Uri.parse('$siteUrl/chat/$channelId/react/$messageId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'emoji': emoji, 'react_action': action.name},
    );
  }

  /// This endpoint uses `page` pagination and names its reaction filter `emoji`.
  @override
  Future<ChatMessageReactors> chatMessageReactors({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? reaction,
    int limit = ChatMessageReactors.maximumPageSize,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(messageId, 'messageId');
    if (limit < 1 || limit > ChatMessageReactors.maximumPageSize) {
      throw RangeError.range(
        limit,
        1,
        ChatMessageReactors.maximumPageSize,
        'limit',
      );
    }
    if (reaction != null) _validateReactionName(reaction);

    final uri =
        Uri.parse(
          '$siteUrl/chat/$channelId/$messageId/reactions-users.json',
        ).replace(
          queryParameters: {'page': '0', 'limit': '$limit', 'emoji': ?reaction},
        );
    final body = await _getObject(
      uri,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return ChatMessageReactors.parse(
      body,
      channelId: channelId,
      messageId: messageId,
      siteUrl: siteUrl,
      filter: reaction,
    );
  }

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {
    _requirePositiveId(channelId, 'channelId');
    _requirePositiveId(threadId, 'threadId');
    _requirePositiveId(messageId, 'messageId');
    await _write(
      Uri.parse(
        '$siteUrl/chat/api/channels/$channelId/threads/$threadId/read.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'message_id': messageId},
    );
  }
}
