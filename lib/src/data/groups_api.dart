import '../models/group.dart';
import '../models/json.dart';
import '../models/topic.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'plugin_transport.dart';

/// Typed client for Discourse's built-in group directory and group pages.
///
/// Read methods accept a nullable key because public groups are visible to an
/// anonymous visitor. Mutations require an authenticated key; the server still
/// remains the authority for every capability exposed by [Group].
final class GroupsApi {
  const GroupsApi(this._transport, this._models);

  static const int defaultMemberPageSize = 50;
  static const int maximumMemberPageSize = 1000;
  static const int maximumGroupNameLength = 255;
  static const int maximumFilterLength = 255;

  final PluginApiTransport _transport;
  final DiscourseModelCodec _models;

  Future<GroupDirectoryPage> directory({
    required String siteUrl,
    String? apiKey,
    int page = 0,
    String? filter,
    String? type,
    String? order,
    bool ascending = true,
    String? username,
    String? clientId,
  }) async {
    if (page < 0) {
      throw RangeError.value(page, 'page', 'Must be non-negative.');
    }
    final normalizedFilter = _optionalQuery(filter, 'filter');
    final normalizedType = _optionalQuery(type, 'type');
    final normalizedOrder = _optionalQuery(order, 'order');
    final normalizedUsername = _optionalQuery(username, 'username');
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/groups.json', {
        if (page > 0) 'page': '$page',
        'filter': ?normalizedFilter,
        'type': ?normalizedType,
        'order': ?normalizedOrder,
        if (!ascending) 'asc': 'false',
        'username': ?normalizedUsername,
      }),
    );
    return GroupDirectoryPage.fromWire(
      body,
      siteUrl,
      extensions: _models.extensions,
    );
  }

  Future<GroupDetail> detail({
    required String siteUrl,
    required String groupName,
    String? apiKey,
    String? clientId,
  }) async => GroupDetail.fromWire(
    await _get(
      siteUrl: siteUrl,
      path: '/groups/${_groupName(groupName)}.json',
      apiKey: apiKey,
      clientId: clientId,
    ),
    siteUrl,
    extensions: _models.extensions,
  );

  Future<GroupMembersPage> members({
    required String siteUrl,
    required String groupName,
    String? apiKey,
    int offset = 0,
    int limit = defaultMemberPageSize,
    String? order,
    bool ascending = true,
    String? filter,
    bool includeCustomFields = false,
    String? clientId,
  }) async {
    final group = _groupName(groupName);
    _validateWindow(offset: offset, limit: limit);
    final normalizedOrder = _optionalQuery(order, 'order');
    final normalizedFilter = _optionalQuery(filter, 'filter');
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/groups/$group/members.json', {
        'offset': '$offset',
        'limit': '$limit',
        'order': ?normalizedOrder,
        if (!ascending) 'asc': 'false',
        'filter': ?normalizedFilter,
        if (includeCustomFields) 'include_custom_fields': 'true',
      }),
    );
    return GroupMembersPage.fromWire(
      body,
      siteUrl,
      groupName: groupName.trim(),
    );
  }

  Future<GroupRequestersPage> requesters({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    int offset = 0,
    int limit = defaultMemberPageSize,
    String? order,
    bool ascending = true,
    String? filter,
    String? clientId,
  }) async {
    final group = _groupName(groupName);
    _validateWindow(offset: offset, limit: limit);
    final normalizedOrder = _optionalQuery(order, 'order');
    final normalizedFilter = _optionalQuery(filter, 'filter');
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/groups/$group/members.json', {
        'requesters': 'true',
        'offset': '$offset',
        'limit': '$limit',
        'order': ?normalizedOrder,
        if (!ascending) 'asc': 'false',
        'filter': ?normalizedFilter,
      }),
    );
    return GroupRequestersPage.fromWire(body, siteUrl);
  }

  Future<GroupActivityPage> posts({
    required String siteUrl,
    required String groupName,
    String? apiKey,
    DateTime? before,
    int? categoryId,
    String? clientId,
  }) => _activity(
    siteUrl: siteUrl,
    apiKey: apiKey,
    groupName: groupName,
    kind: 'posts',
    before: before,
    categoryId: categoryId,
    clientId: clientId,
  );

  Future<GroupActivityPage> mentions({
    required String siteUrl,
    required String groupName,
    String? apiKey,
    DateTime? before,
    int? categoryId,
    String? clientId,
  }) => _activity(
    siteUrl: siteUrl,
    apiKey: apiKey,
    groupName: groupName,
    kind: 'mentions',
    before: before,
    categoryId: categoryId,
    clientId: clientId,
  );

  Future<TopicList> topics({
    required String siteUrl,
    required String groupName,
    String? apiKey,
    String? clientId,
  }) => _topicList(
    siteUrl: siteUrl,
    apiKey: apiKey,
    path: '/topics/groups/${_groupName(groupName)}.json',
    clientId: clientId,
  );

  Future<TopicList> messages({
    required String siteUrl,
    required String apiKey,
    required String username,
    required String groupName,
    bool archived = false,
    String? clientId,
  }) {
    final normalizedUsername = _pathSegment(username, 'username');
    final group = _groupName(groupName);
    final archiveSuffix = archived ? '/archive' : '';
    return _topicList(
      siteUrl: siteUrl,
      apiKey: apiKey,
      path:
          '/topics/private-messages-group/$normalizedUsername/'
          '$group$archiveSuffix.json',
      clientId: clientId,
    );
  }

  /// Follows a server-authored topic-list cursor after constraining it to a
  /// same-origin JSON path.
  Future<TopicList> topicPage({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final safePath = TopicList.asJsonPath(path);
    if (safePath == null) {
      throw ArgumentError.value(path, 'path', 'Invalid topic-list cursor.');
    }
    return _topicList(
      siteUrl: siteUrl,
      apiKey: apiKey,
      path: safePath,
      clientId: clientId,
    );
  }

  Future<GroupLogsPage> logs({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    int offset = 0,
    String? action,
    String? actingUsername,
    String? targetUsername,
    String? subject,
    String? clientId,
  }) async {
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must be non-negative.');
    }
    final group = _groupName(groupName);
    final normalizedAction = _optionalQuery(action, 'action');
    final normalizedActing = _optionalQuery(actingUsername, 'actingUsername');
    final normalizedTarget = _optionalQuery(targetUsername, 'targetUsername');
    final normalizedSubject = _optionalQuery(subject, 'subject');
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/groups/$group/logs.json', {
        if (offset > 0) 'offset': '$offset',
        'filters[action]': ?normalizedAction,
        'filters[acting_username]': ?normalizedActing,
        'filters[target_username]': ?normalizedTarget,
        'filters[subject]': ?normalizedSubject,
      }),
    );
    return GroupLogsPage.fromWire(body, siteUrl);
  }

  Future<List<GroupPermission>> permissions({
    required String siteUrl,
    String? apiKey,
    required String groupName,
    String? clientId,
  }) async {
    final transport = _transport;
    if (transport is! PluginJsonListTransport) {
      throw UnsupportedError(
        'Group permissions require PluginJsonListTransport because the '
        'endpoint returns a bare JSON array.',
      );
    }
    final rows = await (transport as PluginJsonListTransport).pluginGetJsonList(
      siteUrl: siteUrl,
      path: '/g/${_groupName(groupName)}/permissions',
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable([
      for (final row in rows.take(Group.maximumNotificationDefaults))
        GroupPermission.fromWire(row),
    ]);
  }

  Future<void> join({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_positiveId(groupId, 'groupId')}/join.json',
      method: 'PUT',
    );
  }

  Future<void> leave({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_positiveId(groupId, 'groupId')}/leave.json',
      method: 'DELETE',
    );
  }

  Future<String?> requestMembership({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required String reason,
    String? clientId,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'A reason is required.');
    }
    final body = await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_groupName(groupName)}/request_membership.json',
      method: 'POST',
      body: {'reason': normalizedReason},
    );
    return jsonText(body['relative_url']);
  }

  Future<void> setNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required int notificationLevel,
    int? userId,
    String? clientId,
  }) async {
    if (notificationLevel < 0) {
      throw RangeError.value(
        notificationLevel,
        'notificationLevel',
        'Must be non-negative.',
      );
    }
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_groupName(groupName)}/notifications.json',
      method: 'POST',
      body: {
        'notification_level': notificationLevel,
        if (userId != null) 'user_id': _positiveId(userId, 'userId'),
      },
    );
  }

  Future<GroupMembershipMutationResult> addMembers({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    Iterable<String> usernames = const [],
    Iterable<String> emails = const [],
    bool notifyUsers = true,
    bool skipEmail = false,
    String? clientId,
  }) async {
    final normalizedUsernames = _identifiers(usernames, 'usernames');
    final normalizedEmails = _identifiers(emails, 'emails');
    if (normalizedUsernames.isEmpty && normalizedEmails.isEmpty) {
      throw ArgumentError('At least one username or email is required.');
    }
    return GroupMembershipMutationResult.fromWire(
      await _write(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        path: '/groups/${_positiveId(groupId, 'groupId')}/members.json',
        method: 'PUT',
        body: {
          if (normalizedUsernames.isNotEmpty)
            'usernames': normalizedUsernames.join(','),
          if (normalizedEmails.isNotEmpty) 'emails': normalizedEmails.join(','),
          'notify_users': notifyUsers,
          if (skipEmail) 'skip_email': 'true',
        },
      ),
    );
  }

  Future<GroupMembershipMutationResult> removeMembers({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required Iterable<int> userIds,
    String? clientId,
  }) async {
    final ids = _ids(userIds, 'userIds');
    return GroupMembershipMutationResult.fromWire(
      await _write(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        path: '/groups/${_positiveId(groupId, 'groupId')}/members.json',
        method: 'DELETE',
        body: {'user_ids': ids.join(',')},
      ),
    );
  }

  Future<void> addOwners({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required Iterable<String> usernames,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_positiveId(groupId, 'groupId')}/owners.json',
      method: 'PUT',
      body: {'usernames': _identifiers(usernames, 'usernames').join(',')},
    );
  }

  Future<void> removeOwners({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required Iterable<String> usernames,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/admin/groups/${_positiveId(groupId, 'groupId')}/owners.json',
      method: 'DELETE',
      body: {
        'group': {'usernames': _identifiers(usernames, 'usernames').join(',')},
      },
    );
  }

  Future<void> setPrimaryGroup({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required Iterable<String> usernames,
    required bool primary,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/admin/groups/${_positiveId(groupId, 'groupId')}/primary.json',
      method: 'PUT',
      body: {
        'group': {'usernames': _identifiers(usernames, 'usernames').join(',')},
        // The Rails controller compares this parameter to the literal string.
        'primary': primary.toString(),
      },
    );
  }

  Future<void> handleMembershipRequest({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required int userId,
    required bool accept,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path:
          '/groups/${_positiveId(groupId, 'groupId')}'
          '/handle_membership_request.json',
      method: 'PUT',
      body: {
        'user_id': _positiveId(userId, 'userId'),
        if (accept) 'accept': true,
      },
    );
  }

  Future<Group> createGroup({
    required String siteUrl,
    required String apiKey,
    required Map<String, Object?> values,
    String? clientId,
  }) async {
    final body = await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/admin/groups.json',
      method: 'POST',
      body: {'group': values},
    );
    return Group.fromWire(
      jsonObject(body['basic_group']),
      siteUrl,
      extensions: _models.extensions,
    );
  }

  Future<Group> updateGroup({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required Map<String, Object?> values,
    bool updateExistingUsers = false,
    String? clientId,
  }) async {
    final body = await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/groups/${_positiveId(groupId, 'groupId')}.json',
      method: 'PUT',
      body: {
        'group': values,
        if (updateExistingUsers)
          'update_existing_users': updateExistingUsers.toString(),
      },
    );
    final groupJson = jsonObject(body['group']);
    return Group.fromWire(
      groupJson.isEmpty ? body : groupJson,
      siteUrl,
      extensions: _models.extensions,
    );
  }

  Future<void> deleteGroup({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    String? clientId,
  }) async {
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/admin/groups/${_positiveId(groupId, 'groupId')}.json',
      method: 'DELETE',
    );
  }

  Future<void> testSmtpSettings({
    required String siteUrl,
    required String apiKey,
    required int groupId,
    required String smtpServer,
    required int smtpPort,
    required int smtpSslMode,
    required String emailUsername,
    required String emailPassword,
    required String emailFromAlias,
    String? clientId,
  }) async {
    if (smtpPort < 1 || smtpPort > 65535) {
      throw RangeError.range(smtpPort, 1, 65535, 'smtpPort');
    }
    await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path:
          '/groups/${_positiveId(groupId, 'groupId')}'
          '/test_email_settings.json',
      method: 'POST',
      body: {
        'smtp_server': smtpServer,
        'smtp_port': smtpPort,
        'smtp_ssl_mode': smtpSslMode,
        'email_username': emailUsername,
        'email_password': emailPassword,
        'email_from_alias': emailFromAlias,
      },
    );
  }

  Future<int?> automaticMembershipCount({
    required String siteUrl,
    required String apiKey,
    required String emailDomains,
    String? clientId,
  }) async => jsonIntOrNull(
    (await _write(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: '/admin/groups/automatic_membership_count.json',
      method: 'PUT',
      body: {'automatic_membership_email_domains': emailDomains.trim()},
    ))['user_count'],
  );

  Future<GroupActivityPage> _activity({
    required String siteUrl,
    required String? apiKey,
    required String groupName,
    required String kind,
    required DateTime? before,
    required int? categoryId,
    required String? clientId,
  }) async {
    if (categoryId != null) _positiveId(categoryId, 'categoryId');
    final body = await _get(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      path: _withQuery('/groups/${_groupName(groupName)}/$kind.json', {
        if (before != null) 'before': before.toUtc().toIso8601String(),
        if (categoryId != null) 'category_id': '$categoryId',
      }),
    );
    return GroupActivityPage.fromWire(body, siteUrl);
  }

  Future<TopicList> _topicList({
    required String siteUrl,
    required String? apiKey,
    required String path,
    required String? clientId,
  }) async => _models.topicList(
    await _get(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    ),
    siteUrl,
  );

  Future<Map<String, dynamic>> _get({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required String? clientId,
  }) => _transport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );

  Future<Map<String, dynamic>> _write({
    required String siteUrl,
    required String apiKey,
    required String path,
    required String method,
    Map<String, Object?> body = const {},
    required String? clientId,
  }) => _transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  static String _withQuery(String path, Map<String, dynamic> query) =>
      query.isEmpty
      ? path
      : Uri.parse(path).replace(queryParameters: query).toString();

  static String _groupName(String value) => _pathSegment(value, 'groupName');

  static String _pathSegment(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maximumGroupNameLength ||
        normalized.contains('/')) {
      throw ArgumentError.value(value, name, 'Invalid path segment.');
    }
    return Uri.encodeComponent(normalized);
  }

  static String? _optionalQuery(String? value, String name) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maximumFilterLength) {
      throw ArgumentError.value(
        normalized.length,
        name,
        'Must be at most $maximumFilterLength characters.',
      );
    }
    return normalized;
  }

  static void _validateWindow({required int offset, required int limit}) {
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must be non-negative.');
    }
    if (limit < 1 || limit > maximumMemberPageSize) {
      throw RangeError.range(limit, 1, maximumMemberPageSize, 'limit');
    }
  }

  static int _positiveId(int value, String name) {
    if (value < 1) {
      throw RangeError.value(value, name, 'Must be positive.');
    }
    return value;
  }

  static List<int> _ids(Iterable<int> values, String name) {
    final ids = List<int>.unmodifiable([
      for (final value in values) _positiveId(value, name),
    ]);
    if (ids.isEmpty) {
      throw ArgumentError.value(values, name, 'Must not be empty.');
    }
    return ids;
  }

  static List<String> _identifiers(Iterable<String> values, String name) {
    final identifiers = List<String>.unmodifiable([
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    ]);
    if (identifiers.length > maximumMemberPageSize) {
      throw ArgumentError.value(
        identifiers.length,
        name,
        'Must contain at most $maximumMemberPageSize values.',
      );
    }
    return identifiers;
  }
}
