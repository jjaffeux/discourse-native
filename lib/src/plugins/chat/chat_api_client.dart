import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../data/plugin_transport.dart';
import '../../models/json.dart';
import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_message.dart';
import 'chat_pin.dart';
import 'chat_reactors.dart';
import 'chat_search.dart';
import 'chat_thread.dart';

/// Chat's wire adapter over core's bounded, same-origin JSON transport.
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

  /// Finds or creates a direct-message channel with one user.
  ///
  /// This is the same upsert route used by Chat's web user-card button. The
  /// server remains authoritative for both permission and whether an existing
  /// one-to-one channel can be reused.
  @override
  Future<ChatChannel> upsertChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    _validateComposerLookupValue(username);
    final body = await _write(
      Uri.parse('$siteUrl/chat/api/direct-message-channels.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'target_usernames': [username],
        'upsert': true,
      },
    );
    final channel = body['channel'];
    if (channel is! Map<String, dynamic>) {
      throw const FormatException('Missing direct-message chat channel.');
    }
    return ChatChannel.fromJson(channel, siteUrl);
  }

  /// Every chat channel this account follows, public and direct, with the
  /// unread counts that belong beside them.
  ///
  /// Only followed channels come back, and the site caps the answer at 100
  /// public channels and 75 direct ones. There is no paging here and nothing
  /// asks for one: past that many followed channels a sidebar is not the
  /// affordance anyway.
  ///
  /// A `403` is `Discourse::InvalidAccess` — chat is off, or this reader may
  /// not use it — and arrives as a [SiteLookupException] like every other read.
  /// `ChatController.loadChannels` swallows it, which is why the sidebar shows
  /// nothing rather than an error.
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

  /// Updates staff-editable channel metadata and returns the authoritative
  /// channel serializer. An empty description is intentionally sent: core
  /// normalizes it to null, which is how its own editor removes one.
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

  /// Opens or closes a category channel through core's dedicated status
  /// service. Read-only and archived are separate archive workflow states and
  /// are deliberately not accepted here.
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

  /// Moves one followed channel into or out of this account's starred bucket.
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

  /// Updates the independent mute and push-notification channel preferences.
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

  /// Lists only public user identity, never another member's private settings.
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

  /// Lists discoverable public channels using core's Browse Channels filters.
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

  /// Replaces one message's Markdown while retaining its current uploads.
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

  /// Queues core's asynchronous Markdown-to-HTML rebuild for one chat row.
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

  /// Lets core build the canonical `[chat]` transcript for a selection.
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

  /// Adds or removes one channel pin. Core uses the same route with method as
  /// the state, rather than accepting a boolean body.
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

  /// One page of a channel's messages, oldest first.
  ///
  /// Four shapes, and the caller picks exactly one:
  ///
  /// * nothing — the newest [pageSize] messages. The present, which is where
  ///   "jump to now" lands.
  /// * [fromLastRead] — the site resolves the target to this reader's
  ///   `last_read_message_id` and takes the query's *around-target* branch: 25
  ///   messages either side of where they left off. This is where opening a
  ///   channel starts, and it is what Discourse's own client sends. A reader
  ///   who has never opened the channel has no last-read, the target resolves
  ///   to nil, and the answer is the newest page — the same bytes as sending
  ///   nothing, which is why there is no separate case for it here.
  /// * [before] — the page immediately older than a message already held, that
  ///   message excluded.
  /// * [after] — the same, forwards. Only reachable because [fromLastRead] can
  ///   anchor the stream somewhere that is not the end; without it there would
  ///   be nothing in front to fetch.
  ///
  /// [pageSize] is capped at 50 server side and sent explicitly so the number
  /// in the code is the number that applies. The around-target branch ignores
  /// it and answers with its own 25-and-25.
  ///
  /// Worth knowing rather than discovering: this `GET` writes. The controller
  /// runs `update_membership_last_viewed_at`, so opening a channel touches
  /// `last_viewed_at`. It does not touch `last_read_message_id` — that is
  /// [markChatChannelRead]'s job — so nothing is marked read by reading it.
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

    // Absent params are left out rather than sent empty, and the failure mode
    // is worse than an error: `target_message_id=` casts to nil server side and
    // is treated as *absent*, so `direction=past` with an empty target answers
    // with the newest page again rather than the one before it. A load-older
    // that silently returns what the reader already has, forever. (A target
    // that does not exist answers 404, and `page_size=0` answers 400 — both
    // loud. This one is the quiet one.)
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

  /// Credits the reader with everything in a channel up to [messageId].
  ///
  /// The id goes in the query string rather than the body, which is where
  /// Discourse's own client puts it. Nothing comes back worth reading: the
  /// answer is `{"success":"OK"}`, and what the site now believes about the
  /// counts arrives on the tracking channel rather than here.
  ///
  /// Only ever forwards. `ensure_message_id_recency` refuses an id older than
  /// the one already recorded, so a stale write — one whose reader has since
  /// scrolled on — is answered rather than obeyed. That makes this safe to
  /// send out of order, which a debounced caller inevitably does.
  ///
  /// The site does more than move a number: it marks the mentions in what was
  /// just read as read too, and in a direct channel without threading it
  /// catches the thread memberships up as well. So this is the whole of
  /// "I have seen it", not a piece of it.
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
          // With no explicit target the thread endpoint implicitly resolves
          // the membership's last-read id and returns it in response metadata.
          // Bound around that server-selected target just as we do for an
          // explicit notification destination.
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
    // Do not include the value: plugin responses can supply it and errors may
    // be forwarded to diagnostics.
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
      // Do not include the value: composer input can contain private names and
      // errors may be forwarded to diagnostics.
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

  /// Adds or removes one emoji reaction from a chat message for this reader.
  ///
  /// Unlike post reactions, chat reactions are independent: adding one does
  /// not replace another. The route therefore takes an explicit action rather
  /// than behaving as a toggle. Its success response carries no message state;
  /// the controller projects the change immediately and keeps that projection
  /// when this write succeeds.
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

  /// Who gave a chat message one reaction, from chat's own lazy user route.
  ///
  /// This endpoint paginates differently from post reactions (`page` rather
  /// than an offset) and calls its filter `emoji`. The UI asks for the largest
  /// legal first page, matching the bounded eager list used for topic posts.
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
