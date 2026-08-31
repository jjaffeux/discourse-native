part of 'discourse_api.dart';

final class DiscourseAccountApi {
  const DiscourseAccountApi(this._transport, this._models);

  final DiscourseTransport _transport;
  final DiscourseModelCodec _models;
  static const int maximumRecentNotifications = 60;
  static const int maximumUserMenuBookmarkRows = 20;
  static const int maximumUserActivityPageSize = UserActivityPage.maximumItems;
  static const int maximumUserDraftPageSize = 30;

  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/session/current.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final user = switch (body['current_user']) {
      final Map<String, dynamic> user => user,
      _ => null,
    };
    final username = jsonText(user?['username']);
    if (user == null || username == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return _models.currentUser(user, siteUrl);
  }

  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse(
        '$siteUrl/u/${Uri.encodeComponent(username)}/topic-tracking-state.json',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Expected a topic tracking state list');
      }
      return TopicTrackingState.fromJson(decoded);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/u/${Uri.encodeComponent(username)}.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return UserPreferences.fromJson(jsonObject(body['user']));
  }

  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) async {
    _validateUserPreferenceValues(values);
    final body = await _write(
      Uri.parse(
        '$siteUrl/u/${Uri.encodeComponent(username.toLowerCase())}.json',
      ),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: values,
    );
    return UserPreferences.fromJson(
      jsonObject(body['user']),
      fallback: fallback,
    );
  }

  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/sidebar_sections.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final sections = <SidebarSection>[];
      var index = 0;
      for (final json in jsonObjects(body['sidebar_sections'])) {
        final section = SidebarSection.customFromJson(
          json,
          index: index,
          icons: _models.icons,
        );
        if (section != null) sections.add(section);
        index++;
      }
      return List.unmodifiable(sections);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/notifications/totals.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return _models.notificationTotals(body);
  }

  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async {
    if (limit < 1 || limit > maximumRecentNotifications) {
      throw RangeError.range(limit, 1, maximumRecentNotifications, 'limit');
    }
    final url = Uri.parse('$siteUrl/notifications.json').replace(
      queryParameters: {
        'recent': 'true',
        'limit': '$limit',
        if (filterByTypes.isNotEmpty) ...{
          'filter_by_types': filterByTypes.map((type) => type.value).join(','),
          'silent': 'true',
        },
      },
    );
    final body = await _getObject(
      url,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return List.unmodifiable([
      for (final entry in jsonObjects(body['notifications']).take(limit))
        DiscourseNotification.fromJson(entry),
    ]);
  }

  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/u/${Uri.encodeComponent(username)}/user-menu-bookmarks.json',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    // Core gives this menu route one twenty-row budget, with due reminders
    // first. Keep that boundary locally too: a broken serializer response must
    // not turn opening the user menu into an arbitrary eager list build.
    final reminderEntries = jsonObjects(
      body['notifications'],
    ).take(maximumUserMenuBookmarkRows).toList(growable: false);
    final bookmarkBudget = maximumUserMenuBookmarkRows - reminderEntries.length;

    return (
      reminders: List<DiscourseNotification>.unmodifiable([
        for (final entry in reminderEntries)
          DiscourseNotification.fromJson(entry),
      ]),
      bookmarks: List<Bookmark>.unmodifiable([
        for (final entry in jsonObjects(body['bookmarks']).take(bookmarkBudget))
          Bookmark.fromJson(entry),
      ]),
    );
  }

  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit < 1 || limit > maximumUserActivityPageSize) {
      throw RangeError.range(limit, 1, maximumUserActivityPageSize, 'limit');
    }
    final url = Uri.parse('$siteUrl/user_actions.json').replace(
      queryParameters: {
        'offset': '$offset',
        'username': username,
        'filter':
            '${UserActivityItem.topicActionType},'
            '${UserActivityItem.replyActionType}',
        'limit': '$limit',
      },
    );
    final body = await _getObject(
      url,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return UserActivityPage.fromJson(body, siteUrl, limit: limit);
  }

  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    _requirePositiveId(targetId, 'targetId');
    _validateBookmarkDraft(name: name, reminderAt: reminderAt);
    final body = await _write(
      Uri.parse('$siteUrl/bookmarks.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'bookmarkable_id': targetId,
        'bookmarkable_type': targetType.wireName,
        'name': name,
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'auto_delete_preference': autoDeletePreference?.wireValue,
      },
    );
    final id = jsonIntOrNull(body['id']);
    if (id == null || id <= 0) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return id;
  }

  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    _requirePositiveId(bookmarkId, 'bookmarkId');
    _validateBookmarkDraft(name: name, reminderAt: reminderAt);
    await _write(
      Uri.parse('$siteUrl/bookmarks/$bookmarkId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'name': name,
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'auto_delete_preference': autoDeletePreference.wireValue,
      },
    );
  }

  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    _requirePositiveId(bookmarkId, 'bookmarkId');
    final body = await _write(
      Uri.parse('$siteUrl/bookmarks/$bookmarkId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
    final topicBookmarked = body['topic_bookmarked'];
    if (targetType.updatesTopicBookmarkState && topicBookmarked is! bool) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return topicBookmarked is bool ? topicBookmarked : null;
  }

  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/remove_bookmarks'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    _requirePositiveId(id, 'id');
    await _write(
      Uri.parse('$siteUrl/notifications/mark-read.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'id': id},
    );
  }

  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    if (types.isEmpty) {
      throw ArgumentError.value(types, 'types', 'Must not be empty');
    }
    await _write(
      Uri.parse('$siteUrl/notifications/mark-read.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'dismiss_types': types.map((type) => type.value).join(',')},
    );
  }

  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/u/${Uri.encodeComponent(username)}/card.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final user = switch (body['user']) {
      final Map<String, dynamic> user => user,
      _ => null,
    };
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return _models.userCard(user, siteUrl);
  }

  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) async {
    final normalizedDescription = description.trim();
    final normalizedEmoji = emoji
        .trim()
        .replaceFirst(RegExp(r'^:'), '')
        .replaceFirst(RegExp(r':$'), '');
    if (normalizedDescription.isEmpty || normalizedDescription.length > 100) {
      throw ArgumentError.value(
        description,
        'description',
        'must contain between 1 and 100 characters',
      );
    }
    if (normalizedEmoji.isEmpty || normalizedEmoji.length > 100) {
      throw ArgumentError.value(emoji, 'emoji', 'must name one emoji');
    }
    await _write(
      Uri.parse('$siteUrl/user-status.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'description': normalizedDescription,
        'emoji': normalizedEmoji,
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await _write(
      Uri.parse('$siteUrl/user-status.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) async {
    final body = await _write(
      Uri.parse('$siteUrl/do-not-disturb.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'duration': duration.wireValue},
    );
    final endsAt = jsonDate(body['ends_at']);
    if (endsAt == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return endsAt.toUtc();
  }

  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await _write(
      Uri.parse('$siteUrl/do-not-disturb.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) async {
    await _write(
      Uri.parse('$siteUrl/u/${Uri.encodeComponent(username)}.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'hide_presence': hidePresence},
    );
  }

  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit < 1 || limit > maximumUserDraftPageSize) {
      throw RangeError.range(limit, 1, maximumUserDraftPageSize, 'limit');
    }
    final url = Uri.parse(
      '$siteUrl/drafts.json',
    ).replace(queryParameters: {'offset': '$offset', 'limit': '$limit'});
    final body = await _getObject(
      url,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable(
      jsonObjects(body['drafts'])
          .take(limit)
          .map(UserDraft.fromJson)
          .where((draft) => draft.key.isNotEmpty),
    );
  }

  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) async {
    final encoded = Uri.encodeComponent(draftKey);
    await _write(
      Uri.parse('$siteUrl/drafts/$encoded.json?sequence=$sequence'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final encoded = Uri.encodeComponent(username);
    final body = await _getObject(
      Uri.parse('$siteUrl/u/$encoded/summary.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return UserSummary.fromJson(body, siteUrl);
  }

  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final response = await _transport.requestAuthenticated(
      'POST',
      Uri.parse('$siteUrl/user-api-key/revoke'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    // 404 means the site predates the revoke route; nothing to do about it.
    // Every other non-2xx response is a failed revocation. In particular,
    // SafeHttpClient deliberately refuses automatic redirects, so accepting a
    // 3xx here would delete our local key while leaving the remote key live.
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        response.statusCode != 404) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _write(
    Uri url, {
    required String siteUrl,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => _transport.write(
    url,
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  Future<http.Response> _get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) =>
      _transport.get(url, siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  Future<Map<String, dynamic>> _getObject(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) => _transport.getObject(
    url,
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  static const Set<String> _userPreferenceFields = {
    'timezone',
    'like_notification_frequency',
    'notify_on_linked_posts',
    'new_topic_duration_minutes',
    'auto_track_topics_after_msecs',
    'notification_level_when_replying',
    'bookmark_auto_delete_preference',
  };

  static void _validateUserPreferenceValues(Map<String, Object?> values) {
    final unsupported = values.keys.where(
      (key) => !_userPreferenceFields.contains(key),
    );
    if (unsupported.isNotEmpty) {
      throw ArgumentError.value(
        unsupported.first,
        'values',
        'Unsupported user preference field',
      );
    }
  }

  static void _validateBookmarkDraft({
    required String? name,
    required DateTime? reminderAt,
  }) {
    if (name != null && name.length > 100) {
      throw const WriteException(
        WriteFailure.validation,
        errors: ['Bookmark notes must be 100 characters or fewer.'],
      );
    }
    if (reminderAt == null) return;
    final now = DateTime.now().toUtc();
    final reminder = reminderAt.toUtc();
    if (!reminder.isAfter(now)) {
      throw const WriteException(
        WriteFailure.validation,
        errors: ['Bookmark reminders must be in the future.'],
      );
    }
    final maximum = DateTime.utc(
      now.year + 10,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    if (reminder.isAfter(maximum)) {
      throw const WriteException(
        WriteFailure.validation,
        errors: ['Bookmark reminders cannot be more than 10 years away.'],
      );
    }
  }

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }
}
