import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../diagnostics/diagnostics_redactor.dart';
import '../models/bookmark.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/json.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/search_results.dart';
import '../models/sidebar.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_summary.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'discourse_api_contracts.dart';
import 'discourse_transport.dart';
import 'http_transport.dart';
import 'plugin_transport.dart';
import 'site_appearance_loader.dart';

export 'discourse_api_contracts.dart';
export 'plugin_transport.dart';

/// A category-list response plus whether its authenticated site metadata also
/// arrived. A partial list is still useful for badges/navigation, but callers
/// should leave it retryable so lazy-loaded user choices can be filled in.
final class CategoryLoadResult {
  factory CategoryLoadResult(
    Iterable<TopicCategory> categories, {
    bool complete = true,
    Iterable<int>? rootCategoryIds,
    bool canCreateTopic = false,
    SitePostActionCatalog? postActionCatalog,
  }) {
    final immutableCategories = List<TopicCategory>.unmodifiable(categories);
    return CategoryLoadResult._(
      immutableCategories,
      List<int>.unmodifiable(
        rootCategoryIds ??
            immutableCategories
                .where((category) => category.parentCategoryId == null)
                .map((category) => category.id),
      ),
      complete,
      canCreateTopic,
      postActionCatalog,
    );
  }

  CategoryLoadResult._(
    this.categories,
    this.rootCategoryIds,
    this.complete,
    this.canCreateTopic,
    this.postActionCatalog,
  );

  final List<TopicCategory> categories;

  /// Category ids represented as roots by this page's category-list response.
  ///
  /// Nested categories and the page-one `site.json` supplement remain in
  /// [categories] for identity lookup, but must not become category cards.
  final List<int> rootCategoryIds;
  final bool complete;
  final bool canCreateTopic;

  /// Authenticated post-action metadata from the page-one `/site.json` read.
  /// Null means that metadata was not requested or did not arrive.
  final SitePostActionCatalog? postActionCatalog;
}

/// Talks to a Discourse site.
///
/// The lookup mirrors DiscourseMobile's `Site.fromTerm`: probe
/// `/user-api-key/new` to confirm it is a Discourse new enough to expose the
/// user API, then read `/site/basic-info.json` for the details we display.
class DiscourseApi
    implements
        AccountActivityApi,
        BookmarksWriteApi,
        DoNotDisturbApi,
        DraftsApi,
        UserSummariesApi,
        TopicFeedsApi,
        TopicReadsApi,
        UserPreferencesApi,
        PluginApiTransport {
  DiscourseApi({
    http.Client? client,
    this.models = const DiscourseModelCodec.core(),
    this.timeout = const Duration(seconds: 10),
    int maxResponseBytes = 16 * 1024 * 1024,
  }) : assert(timeout > Duration.zero),
       assert(maxResponseBytes > 0),
       _maxResponseBytes = maxResponseBytes,
       _client = client == null
           ? SafeHttpClient.create()
           : SafeHttpClient.owned(client);

  static const int minimumApiVersion = 2;
  static const int maximumSearchTermLength = 2048;
  static const int maximumAutocompleteResults = TopicTagSearch.maximumResults;
  static const int maximumRecentNotifications = 60;
  static const int maximumUserMenuBookmarkRows = 20;
  static const int maximumUserActivityPageSize = UserActivityPage.maximumItems;
  static const int maximumUserDraftPageSize = 30;
  static const int _maxRedirects = 5;

  final SafeHttpClient _client;
  final DiscourseModelCodec models;
  final Duration timeout;

  /// Largest buffered API response accepted from a site.
  ///
  /// These routes return JSON rather than media. Keeping a generous finite
  /// bound prevents a broken endpoint from growing the process without limit.
  final int _maxResponseBytes;

  late final DiscourseTransport _transport = DiscourseTransport(
    _client,
    timeout,
    _maxResponseBytes,
  );

  late final SiteAppearanceLoader _siteAppearanceLoader = SiteAppearanceLoader(
    client: _client,
    coordinator: _transport.coordinator,
    timeout: timeout,
    maxResponseBytes: _maxResponseBytes < 2 * 1024 * 1024
        ? _maxResponseBytes
        : 2 * 1024 * 1024,
  );

  /// Turns whatever the user typed into a URL to probe.
  ///
  /// Bare hosts get https, since that is what any site worth connecting to
  /// serves. Explicit HTTP is reserved for loopback development servers.
  static const int maximumForumAddressLength = 2048;

  static Uri normalize(String term) {
    var trimmed = term.trim();
    if (trimmed.length > maximumForumAddressLength) {
      // Do not echo or redact a rejected oversized value: it may contain a
      // credential whose terminating delimiter lies beyond any safe prefix.
      throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        'that forum address',
        cause: FormatException('Forum address is too long.'),
      );
    }
    // Do not trim the two slashes that belong to a bare scheme. Turning
    // `https://` into `https:` would make the default-scheme branch reinterpret
    // `https` as a host and send a pointless validation request there.
    final schemeSeparator = trimmed.indexOf('://');
    final minimumEnd = schemeSeparator < 0 ? 0 : schemeSeparator + 3;
    var end = trimmed.length;
    while (end > minimumEnd && trimmed.codeUnitAt(end - 1) == 0x2F) {
      end--;
    }
    if (end != trimmed.length) trimmed = trimmed.substring(0, end);
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    try {
      final url = Uri.parse(trimmed);
      return requireSafeHttpUrl(url);
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        error.url.toString(),
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on FormatException catch (_, stackTrace) {
      // Uri.parse's exception can retain its complete source, including
      // credentials or query values. Replace it at this user-input boundary.
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        DiagnosticsRedactor.uri(trimmed),
        cause: const FormatException('Invalid forum URL.'),
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<DiscourseInstance> lookup(String term) async {
    final probe = normalize(term).resolve('/user-api-key/new');

    final _HeadResult head;
    try {
      head = await _head(probe);
    } on SiteLookupException {
      rethrow;
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    // A Discourse always has this route; a 404 means we are talking to
    // something else, or to a version that predates the user API.
    if (head.statusCode == 404) {
      throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        term,
        statusCode: head.statusCode,
      );
    }
    if (head.statusCode != 200) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        statusCode: head.statusCode,
      );
    }

    final apiVersion =
        int.tryParse(head.headers['auth-api-version'] ?? '') ?? 0;
    if (apiVersion < minimumApiVersion) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, term);
    }

    // Redirects may have moved us; keep where we landed, not where we started.
    //
    // Unlike DiscourseMobile we keep any port, which it strips — that would
    // break connecting to a site on localhost during development.
    final baseUrl = head.url
        .toString()
        .replaceFirst(RegExp(r'/user-api-key/new/*$'), '')
        .replaceFirst(RegExp(r'/+$'), '');

    final Map<String, dynamic> info;
    try {
      final response = await _send(
        http.Request('GET', Uri.parse('$baseUrl/site/basic-info.json')),
      );
      if (response.statusCode != 200) {
        throw SiteLookupException(
          SiteLookupFailure.unreachable,
          term,
          statusCode: response.statusCode,
        );
      }
      info = jsonDecode(response.body) as Map<String, dynamic>;
    } on SiteLookupException {
      rethrow;
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        term,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    final title = jsonText(info['title']);

    return DiscourseInstance(
      url: baseUrl,
      title: title == null || title.isEmpty ? Uri.parse(baseUrl).host : title,
      description: jsonText(info['description']),
      iconUrl: _absoluteIcon(jsonText(info['apple_touch_icon_url']), baseUrl),
      apiVersion: apiVersion,
      loginRequired: info['login_required'] == true,
    );
  }

  /// HEAD, following redirects by hand so the final URL is observable —
  /// `package:http` reports the originally requested one.
  Future<_HeadResult> _head(Uri url) async {
    var current = url;

    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('HEAD', current);
      final response = await _send(request);

      final location = response.headers['location'];
      final isRedirect =
          const {301, 302, 303, 307, 308} //
              .contains(response.statusCode);

      if (!isRedirect || location == null) {
        return _HeadResult(current, response.statusCode, response.headers);
      }

      current = resolveSafeHttpRedirect(current, location);
    }

    throw SiteLookupException(SiteLookupFailure.unreachable, url.toString());
  }

  /// Who the stored API key belongs to.
  ///
  /// Needs the `session_info` scope. Throws [SiteLookupFailure.unreachable] on
  /// a network problem and [SiteLookupFailure.notDiscourse] if the key was
  /// rejected — the caller treats the latter as "reconnect".
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
    return models.currentUser(user, siteUrl);
  }

  @override
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

  @override
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

  /// Custom sidebar sections visible to the connected account.
  ///
  /// Discourse returns private sections owned by the user and public sections
  /// together, plus its built-in Community section. The model parser excludes
  /// that built-in so callers can append this result without duplicating the
  /// app's native Community routes.
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
        final section = SidebarSection.customFromJson(json, index: index);
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

  /// The colors Discourse resolved for this site and, when connected, the
  /// account named by [username]. Missing theme metadata is an optional
  /// capability and answers null rather than preventing the site from loading.
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) => _siteAppearanceLoader.load(
    siteUrl: siteUrl,
    username: username,
    apiKey: apiKey,
    clientId: clientId,
  );

  /// Every unread counter the shell shows, in one request.
  ///
  /// Cheap enough to call on launch for each connected site, which is what
  /// DiscourseMobile does.
  @override
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

    return models.notificationTotals(body);
  }

  /// The notifications behind the user menu's first tab.
  ///
  /// `recent=true` asks for the menu's own view of the list — the newest
  /// [limit], unread first — rather than the paged history behind the
  /// notifications page. Discourse caps it at 60.
  ///
  /// Asking also moves the account's "seen" marker, which is what clears the
  /// unseen bubble on the web when the menu is opened. That is deliberate: this
  /// is the same act. Read state is a separate thing and is not touched, so the
  /// rows stay unread until they are tapped.
  ///
  /// [filterByTypes] produces the filtered views used by Replies and Chat.
  /// Filtered requests include `silent=true`, just as Discourse's web client
  /// does, so opening one category does not move the account-wide seen marker.
  @override
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

  /// The bookmarks behind the user menu's bookmarks tab.
  ///
  /// `/u/{username}/user-menu-bookmarks` rather than the paged bookmark list
  /// behind the activity page: it is the route the menu itself uses, and it
  /// answers with the two lists the tab is made of — the bookmark reminders
  /// that have fired and not been read, and then as many bookmarks as its
  /// twenty-row budget has left over, with the reminders' own bookmarks left
  /// out so nothing appears twice.
  ///
  /// [username] has to be the account the key belongs to; Discourse refuses
  /// anybody else's, which is why this asks for one rather than there being a
  /// `/my` form of the route to fall back on.
  @override
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

  /// The connected user's default Activity destination.
  ///
  /// Core's `UserStream.filterParam` maps an unfiltered `userActivity.index`
  /// route to action types 4 and 5. Those are topics and replies; likes,
  /// bookmarks, private messages, reads, and drafts each belong to other
  /// filters or routes and must not leak into this default stream.
  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  /// Marks one notification read.
  ///
  /// Takes an id rather than defaulting to "all of them" the way the route
  /// does: omitting the parameter dismisses the user's entire inbox, which is
  /// not something a mistyped call should be able to do.
  @override
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

  /// One page of a topic list. [path] is the list route, e.g. `/latest.json`.
  ///
  /// The same envelope serves latest, new, unread, top and private messages,
  /// so they all come through here.
  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl$path'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return models.topicList(body, siteUrl);
  }

  /// The small, faceted result set Discourse serves under its header search.
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  }) async {
    if (term.length > maximumSearchTermLength) {
      // Do not attach the value: search text can contain private names and
      // phrases, and this error may be forwarded to diagnostics.
      throw ArgumentError(
        'Search terms must be at most $maximumSearchTermLength characters.',
      );
    }
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final body = await _getObject(
      Uri.parse('$siteUrl/search/query.json').replace(
        queryParameters: {
          'term': term,
          'type_filter': ?typeFilter,
          if (topicId != null) ...{
            'search_context[type]': 'topic',
            'search_context[id]': '$topicId',
          },
          if (searchForId) 'search_for_id': 'true',
          'restrict_to_archetype': ?restrictToArchetype,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return SearchResults.fromJson(body, siteUrl);
  }

  /// People and groups offered by core's header-search `@` assistant.
  ///
  /// This is intentionally separate from composer mention completion. The
  /// composer only offers people it can safely mention; a search modifier may
  /// scope to either a person or a visible group.
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final body = await _getObject(
      Uri.parse('$siteUrl/u/search/users.json').replace(
        queryParameters: {
          if (term.isNotEmpty) 'term': term else 'last_seen_users': 'true',
          'include_groups': 'true',
          'limit': '$limit',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return FoundUsersAndGroups(
      users: List.unmodifiable([
        for (final user in jsonObjects(body['users']).take(limit))
          FoundUser.fromJson(user, siteUrl),
      ]),
      groups: List.unmodifiable([
        for (final group in jsonObjects(body['groups']).take(limit))
          FoundGroup.fromJson(group, siteUrl),
      ]),
    );
  }

  /// The five most recent searches exposed by core's initial search menu.
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/u/recent-searches.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return List.unmodifiable(
      jsonArray(
        body['recent_searches'],
      ).map(jsonText).whereType<String>().take(5),
    );
  }

  Future<void> resetRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    await _write(
      Uri.parse('$siteUrl/u/recent-searches.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  /// Credits a selected autocomplete result to the search log that produced
  /// it, matching core's `/search/click` write.
  Future<void> logSearchClick({
    required String siteUrl,
    required String apiKey,
    required int searchLogId,
    required Object resultId,
    required SearchResultKind resultKind,
    String? clientId,
  }) async {
    _requirePositiveId(searchLogId, 'searchLogId');
    await _write(
      Uri.parse('$siteUrl/search/click.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'search_log_id': searchLogId,
        'search_result_id': resultId,
        'search_result_type': resultKind.name,
      },
    );
  }

  /// A topic with its first chunk of posts (20) and the full list of post ids.
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(id, 'id');
    if (postNumber != null) {
      _requirePositiveId(postNumber, 'postNumber');
    }
    final query = <String, String>{
      if (postNumber != null) 'post_number': '$postNumber',
      if (summary) 'summary': 'true',
    };
    final body = await _getObject(
      // Topic ids are stable; slugs are presentation metadata and can become
      // stale after a title change. Discourse redirects `/t/{old-slug}/{id}`
      // to the current slug, while the authenticated transport deliberately
      // refuses automatic redirects. Its id-only JSON route skips that
      // canonicalization, and `post_number` keeps the numbered form
      // unambiguous with `/t/{slug}/{id}`.
      Uri.parse(
        '$siteUrl/t/$id.json',
      ).replace(queryParameters: query.isEmpty ? null : query),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return models.topic(body, siteUrl);
  }

  /// Records the farthest post a signed-in reader has actually had on screen.
  ///
  /// Fetching a topic is not a read receipt in Discourse. Its web client sends
  /// post timings separately, and `PostTiming.process_timings` advances
  /// `last_read_post_number` from these post numbers. A small positive timing
  /// is enough for a native viewport observation; [milliseconds] also becomes
  /// the topic time so the request has the same shape as the web client's.
  @override
  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postNumber, 'postNumber');
    if (milliseconds <= 0) {
      throw RangeError.value(milliseconds, 'milliseconds', 'Must be positive.');
    }
    await _write(
      Uri.parse('$siteUrl/topics/timings.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'topic_id': topicId,
        'topic_time': milliseconds,
        'timings': {'$postNumber': milliseconds},
      },
    );
  }

  /// Changes how closely the current account follows one topic.
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/notifications'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'notification_level': notificationLevel.value},
    );
  }

  /// Changes this account's pin preference through the same two routes as web.
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/${pinned ? 're-pin' : 'clear-pin'}'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  /// Changes one guardian-approved topic status through core's admin route.
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/status'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'status': status.wireName, 'enabled': enabled},
    );
  }

  /// Soft-deletes a topic through its first post, as core's topic model does.
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId'},
    );
  }

  /// Irreversibly deletes a soft-deleted topic after core's preflight accepts
  /// the current administrator and cooldown.
  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId', 'force_destroy': true},
    );
  }

  /// Recovers a soft-deleted topic through core's topic-specific route.
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/recover.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId'},
    );
  }

  /// Specific posts by id, for paging through a long topic.
  ///
  /// [includeRaw] asks for the markdown alongside the cooked HTML. Reading
  /// never needs it; comparing what was posted against what was typed does.
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    if (ids.isEmpty) return const [];
    _validatePostWindow(topicId, ids);

    return (await _topicPosts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      includeRaw: includeRaw,
      includeSuggested: false,
      apiKey: apiKey,
      clientId: clientId,
    )).posts;
  }

  /// A post window that may also carry the lists shown after the last post.
  ///
  /// Discourse only serializes these when the requested window reaches the
  /// end. Installed model extensions contribute optional sources beside
  /// core's suggestions.
  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    if (ids.isEmpty) {
      return Future.value((posts: const <Post>[], recommendations: null));
    }
    _validatePostWindow(topicId, ids);
    return _topicPosts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      includeRaw: false,
      includeSuggested: true,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  Future<TopicPostsPayload> _topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    required bool includeRaw,
    required bool includeSuggested,
    String? apiKey,
    String? clientId,
  }) async {
    final query = [
      ...ids.map((id) => 'post_ids[]=$id'),
      if (includeRaw) 'include_raw=true',
      if (includeSuggested) 'include_suggested=true',
    ].join('&');
    final body = await _getObject(
      Uri.parse('$siteUrl/t/$topicId/posts.json?$query'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final stream = jsonObject(body['post_stream']);
    return (
      posts: List<Post>.unmodifiable([
        for (final post in jsonObjects(stream['posts']))
          models.post(post, siteUrl),
      ]),
      recommendations: models.topicRecommendations(body, siteUrl),
    );
  }

  /// The summary shown when an avatar or a username is clicked.
  ///
  /// `card.json` is the cheap endpoint for this — a full profile carries far
  /// more than a popup needs.
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
    return models.userCard(user, siteUrl);
  }

  /// Sets the connected account's custom status.
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

  /// Clears the connected account's custom status.
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

  /// Pauses the connected account's notifications for a core duration.
  @override
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

  /// Resumes notifications and releases anything shelved during the pause.
  @override
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

  /// Changes whether the connected account publishes presence features.
  ///
  /// Core's `User.save(["hide_presence"])` sends this option at the top level
  /// of the ordinary user update, rather than nesting it under `user_option`.
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

  /// The site's client settings — every setting Discourse marks `client: true`,
  /// core's and its plugins' alike.
  ///
  /// This is the only public payload carrying a plugin's own configuration.
  /// `/site.json` does not have it: `SiteSerializer` is categories, groups,
  /// archetypes and themes, with no `site_settings` key and no `plugins` key at
  /// all. `/site/basic-info.json` is smaller still and stops at the title.
  ///
  /// Read rather than written, so failures arrive as [SiteLookupException] —
  /// and callers are expected to swallow them. Every field of [SiteConfig] has
  /// a default that is core's default, so a site that will not answer is drawn
  /// as core rather than drawn as broken.
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/site/settings.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return models.siteConfig(body, siteUrl);
    } catch (error, stackTrace) {
      // A payload this cannot read is an answer it cannot use: report it the
      // way every other failure here is reported, rather than letting a decode
      // error escape the contract callers swallow by.
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// The emoji artwork the site uploaded itself, by name.
  ///
  /// `SiteConfig.emojiUrl` can only build the address of an emoji from the
  /// set it names — custom emoji are uploads, and live somewhere else
  /// entirely. This map is the only thing that knows where; a name it does
  /// not hold gets built the ordinary way.
  ///
  /// The payload has been seen in two shapes — an object of name to URL, and
  /// a list of `{name, url}` entries — so both are read.
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/site/emoji.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (jsonDecode(response.body)) {
        final Map<String, dynamic> byName => {
          for (final entry in byName.entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
        final List<dynamic> list => {
          for (final item in list)
            if (item case {'name': final String name, 'url': final String url})
              name: url,
        },
        _ => const <String, String>{},
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Accounts whose names match [term], for the composer's `@` completion.
  ///
  /// [topicId] is not decoration: Discourse's own `UserSearch` ranks people
  /// already in the topic first, which is the difference between offering the
  /// person being replied to and offering an alphabetical stranger.
  ///
  /// Groups are deliberately not asked for. Mentioning one is a different act
  /// with its own permissions, and offering something we cannot check the
  /// reader is allowed to do is worse than not offering it.
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final query = {
      if (term.isNotEmpty) 'term': term else 'last_seen_users': 'true',
      'limit': '$limit',
      if (topicId != null) 'topic_id': '$topicId',
    };
    final response = await _get(
      Uri.parse('$siteUrl/u/search/users.json').replace(queryParameters: query),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (jsonDecode(response.body)) {
        {'users': final List<dynamic> users} => [
          for (final user in users.take(limit))
            if (user is Map<String, dynamic>) FoundUser.fromJson(user, siteUrl),
        ],
        _ => const <FoundUser>[],
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Tags matching a value being typed on the topic filter page.
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse(
        '$siteUrl/tags/filter/search.json',
      ).replace(queryParameters: {'q': term, 'limit': '$limit'}),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return const [];
      return List.unmodifiable([
        for (final entry in jsonArray(body['results']).take(limit))
          if (entry is Map<String, dynamic>)
            if (jsonText(entry['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: '${jsonInt(entry['count'])}',
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Visible tag groups matching a value typed on the topic filter page.
  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse(
        '$siteUrl/tag_groups/filter/search.json',
      ).replace(queryParameters: {'q': term, 'limit': '$limit'}),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return const [];
      return List.unmodifiable([
        for (final entry in jsonArray(body['results']).take(limit))
          if (entry is Map<String, dynamic>)
            if (jsonText(entry['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: [
                  for (final tag in jsonArray(
                    entry['tags'],
                  ).take(maximumAutocompleteResults))
                    if (tag is Map<String, dynamic>) ?jsonText(tag['name']),
                ].join(', '),
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Groups visible to the connected account for `group:` completions.
  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    final response = await _get(
      Uri.parse('$siteUrl/groups/search.json').replace(
        queryParameters: {if (term.isNotEmpty) 'term': term, 'limit': '$limit'},
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = jsonDecode(response.body);
      if (body is! List<dynamic>) return const [];
      return List.unmodifiable([
        for (final item in body.take(limit))
          if (item is Map<String, dynamic>)
            if (jsonText(item['name']) case final name?)
              TopicFilterLookupValue(
                name: name,
                description: jsonText(item['full_name']) ?? name,
              ),
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// How many refs one lookup may carry, matching Discourse's own cap
  /// (`HashtagsController::HASHTAGS_PER_REQUEST`). A request over it is
  /// rejected outright rather than truncated.
  static const int hashtagsPerRequest = 20;

  /// The order hashtag results are ranked in, and the set of types asked for.
  ///
  /// Discourse reads this per context from `Site#hashtag_configurations`, which
  /// is served by `/site.json` — this app reads `/site/settings.json` and so
  /// does not have it. Core's default for the composer is what is sent, which
  /// is what the overwhelming majority of sites run.
  static const List<String> hashtagOrder = ['category', 'tag'];

  /// Categories and tags matching [term], best first.
  ///
  /// `order[]` is not optional decoration: `HashtagsController#search` does
  /// `params.require(:order)` and answers 400 without it.
  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    _validateComposerLookupValue(term, allowEmpty: true);
    if (order.isEmpty || order.length > hashtagsPerRequest) {
      throw RangeError.range(
        order.length,
        1,
        hashtagsPerRequest,
        'order.length',
      );
    }
    final response = await _get(
      Uri.parse('$siteUrl/hashtags/search.json').replace(
        // `<String, dynamic>` so the list is emitted as a repeated parameter.
        // A `Map<String, String>` would stringify it to `[category, tag]` and
        // the site would reject the lot.
        queryParameters: <String, dynamic>{'term': term, 'order[]': order},
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (jsonDecode(response.body)) {
        {'results': final List<dynamic> results} => [
          for (final item in results.take(maximumAutocompleteResults))
            if (item is Map<String, dynamic>) ?FoundHashtag.fromJson(item),
        ],
        _ => const <FoundHashtag>[],
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// What [refs] actually name on this site, for refs already written down.
  ///
  /// The composer's other question: `searchHashtags` answers "what could this
  /// become", this answers "what is this". Anything the site does not resolve —
  /// or will not show this reader — is simply absent from the reply, which is
  /// the caller's cue to leave it as text.
  ///
  /// The response is keyed by type rather than being a list, and the keys are
  /// flattened back out here: which type a ref turned out to be is already on
  /// the item.
  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    String? apiKey,
    String? clientId,
  }) async {
    final slugs = refs.take(hashtagsPerRequest).toList(growable: false);
    if (slugs.isEmpty) return const [];
    for (final slug in slugs) {
      _validateComposerLookupValue(slug);
    }
    final requested = slugs.toSet();

    final response = await _get(
      Uri.parse('$siteUrl/hashtags.json').replace(
        queryParameters: <String, dynamic>{
          'slugs[]': slugs,
          'order[]': hashtagOrder,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return const [];
      return <FoundHashtag>[
        for (final entry in body.values)
          if (entry is List<dynamic>)
            for (final item in entry)
              if (item is Map<String, dynamic>)
                if (FoundHashtag.fromJson(item) case final hashtag?
                    when requested.contains(hashtag.ref))
                  hashtag,
      ].take(hashtagsPerRequest).toList(growable: false);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Which of [names] the site would actually notify.
  ///
  /// The composer asks before drawing a mention as a pill: a name nobody has
  /// cooks as plain text, and a pill over it would be the composer promising a
  /// person who is not there.
  ///
  /// Groups come back under their own key and are folded in — a group mention
  /// cooks as a pill too. `user_reasons` is deliberately ignored: a name the
  /// reader cannot notify *here* is still a real account, and Discourse still
  /// links it.
  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  }) async {
    final asked = names.take(hashtagsPerRequest).toList(growable: false);
    if (asked.isEmpty) return const {};
    for (final name in asked) {
      _validateComposerLookupValue(name);
    }
    if (topicId != null) _requirePositiveId(topicId, 'topicId');
    final requested = asked.toSet();

    final response = await _get(
      Uri.parse('$siteUrl/composer/mentions').replace(
        queryParameters: <String, dynamic>{
          'names[]': asked,
          if (topicId != null) 'topic_id': '$topicId',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return const {};
      return {
        for (final name in jsonArray(body['users']))
          if (name is String && requested.contains(name)) name,
        for (final name in jsonObject(body['groups']).keys)
          if (requested.contains(name)) name,
      };
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Every emoji a site allows, retaining the site's authoritative group order.
  ///
  /// `/emojis.json` is already filtered by the site's deny list and includes
  /// custom uploads in their configured groups. Group identifiers are opaque:
  /// core names and theme/plugin-defined names travel through unchanged.
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/emojis.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return SiteEmojiCatalog.empty;

      final groups = <SiteEmojiGroup>[];
      for (final entry in decoded.entries) {
        if (entry.value is! List<dynamic>) continue;
        final emojis = <SiteEmoji>[];
        for (final row in entry.value as List<dynamic>) {
          if (row is! Map<String, dynamic>) continue;
          final name = row['name'];
          final url = row['url'];
          if (name is! String || name.isEmpty || url is! String) continue;
          final resolved = _absoluteIcon(url, siteUrl);
          if (resolved == null) continue;
          emojis.add(
            SiteEmoji(
              name: name,
              url: resolved,
              tonable: row['tonable'] == true,
            ),
          );
        }
        groups.add(SiteEmojiGroup(id: entry.key, emojis: emojis));
      }
      return SiteEmojiCatalog(groups: groups);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Localized and base-language search aliases keyed by canonical emoji name.
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/emojis/search-aliases.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const {};

      final aliases = <String, List<String>>{};
      for (final entry in decoded.entries) {
        if (entry.key.isEmpty || entry.value is! List<dynamic>) continue;
        final unique = <String>{};
        for (final raw in entry.value as List<dynamic>) {
          if (raw is! String) continue;
          final alias = raw.trim();
          if (alias.isNotEmpty) unique.add(alias);
        }
        aliases[entry.key] = List<String>.unmodifiable(unique);
      }
      return Map<String, List<String>>.unmodifiable(aliases);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// Categories, flattened — subcategories arrive nested but the topic rows
  /// need to look any of them up by id.
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => (await loadCategories(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    page: page,
  )).categories;

  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    if (page < 1) throw RangeError.value(page, 'page', 'Must be positive');

    // Start every authenticated request before yielding. A controller lease is
    // known-current when this method is entered; dispatching a second request
    // only after the first response could send a key whose session was revoked
    // while that response was in flight.
    final categoryRequest = _getObject(
      Uri.parse('$siteUrl/categories.json').replace(
        queryParameters: {
          'include_subcategories': 'true',
          'include_topics': 'true',
          if (page > 1) 'page': '$page',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    final siteRequest = apiKey == null || page > 1
        ? null
        : _categorySiteMetadata(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
          );

    final body = await categoryRequest;
    final list = jsonObject(body['category_list']);
    final roots = jsonObjects(list['categories']).toList(growable: false);
    final rootCategoryIds = <int>[
      for (final category in roots)
        if (category['parent_category_id'] == null)
          if (jsonIntOrNull(category['id']) case final id? when id > 0) id,
    ];
    final rawById = <int, Map<String, dynamic>>{};

    for (final category in _flattenCategories(roots)) {
      rawById.putIfAbsent(jsonInt(category['id']), () => category);
    }

    // CategoryList is paginated on sites that lazy-load categories. Core puts
    // a signed-in user's selected sidebar categories and their ancestors in
    // site.json specifically so navigation never loses choices beyond page 1.
    final siteResult = await siteRequest;
    final site = siteResult?.body ?? const <String, dynamic>{};
    for (final category in _flattenCategories(site['categories'])) {
      rawById.putIfAbsent(jsonInt(category['id']), () => category);
    }
    final uncategorizedId = jsonIntOrNull(site['uncategorized_category_id']);

    return CategoryLoadResult(
      [
        for (final entry in rawById.entries)
          TopicCategory.fromJson(
            entry.key == uncategorizedId
                ? {...entry.value, 'is_uncategorized': true}
                : entry.value,
          ),
      ],
      rootCategoryIds: rootCategoryIds,
      complete: siteResult?.complete ?? true,
      canCreateTopic: list['can_create_topic'] == true,
      postActionCatalog: siteResult?.body == null
          ? null
          : SitePostActionCatalog.fromJson(site),
    );
  }

  Future<({Map<String, dynamic>? body, bool complete})> _categorySiteMetadata({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    try {
      final body = await _getObject(
        Uri.parse('$siteUrl/site.json'),
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      return (body: body, complete: true);
    } on SiteLookupException {
      return (body: null, complete: false);
    }
  }

  /// Session-scoped permissions and validation data used by a topic composer.
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/site.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return TopicComposerCapabilities.fromJson(body);
  }

  /// Tags available for the selected category in the topic composer.
  ///
  /// [limit] is not a local display cap: core validates it against the site's
  /// `max_tag_search_results` and answers 400 for anything larger, so callers
  /// pass that setting through. Its default is core's own, not this client's
  /// autocomplete ceiling, so an unaware caller cannot be rejected.
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async {
    _validateAutocompleteRequest(term: term, limit: limit);
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    final body = await _getObject(
      Uri.parse('$siteUrl/tags/filter/search.json').replace(
        queryParameters: <String, dynamic>{
          'q': term,
          'limit': '$limit',
          if (categoryId != null) 'categoryId': '$categoryId',
          if (selectedTagIds.isNotEmpty)
            'selected_tag_ids[]': selectedTagIds.map((id) => '$id').toList(),
          'filterForInput': 'true',
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return TopicTagSearch.fromJson(body, limit: limit);
  }

  /// Replies to a topic.
  ///
  /// Returns what the site did with the post, which is not always "posted it" —
  /// see [PostOutcome].
  ///
  /// [typingDuration] is required and is not decorative. Discourse reads
  /// `typing_duration_msecs` with `to_i`, so leaving it out means zero, which
  /// is under every `fast_typing_threshold`; on a user's first post that
  /// silences the account rather than merely queueing it
  /// (`NewPostManager.is_fast_typer?`). It is time spent actually typing —
  /// wall clock since the composer opened is [composerOpenDuration].
  ///
  /// Never retry a failure from here. See [_write].
  Future<PostCreation> createPost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? replyToPostNumber,
    String? draftKey,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    if (replyToPostNumber != null) {
      _requirePositiveId(replyToPostNumber, 'replyToPostNumber');
    }
    final body = await _write(
      Uri.parse('$siteUrl/posts.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'raw': raw,
        'topic_id': topicId,
        // A post *number*, not an id. `reply_to_post_id` is not a parameter
        // Discourse permits, and sending it is silently ignored — the reply
        // lands in the topic addressed to nobody.
        'reply_to_post_number': replyToPostNumber,
        'typing_duration_msecs': typingDuration.inMilliseconds,
        'composer_open_duration_msecs': composerOpenDuration.inMilliseconds,
        'draft_key': draftKey,
        // Asks for the envelope, which is the only shape carrying `action`.
        // Without it a queued post is indistinguishable from a published one.
        'nested_post': true,
      },
    );

    return models.postCreation(body, siteUrl);
  }

  /// Creates a topic. The tag objects deliberately retain both id and name:
  /// current Discourse servers no longer accept the old list of bare strings.
  Future<PostCreation> createTopic({
    required String siteUrl,
    required String apiKey,
    required String title,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? categoryId,
    Iterable<TopicTag> tags = const [],
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
  }) async {
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    final body = await _write(
      Uri.parse('$siteUrl/posts.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'title': title,
        'raw': raw,
        'category': categoryId,
        'tags': tags.map((tag) => tag.toJson()).toList(),
        'typing_duration_msecs': typingDuration.inMilliseconds,
        'composer_open_duration_msecs': composerOpenDuration.inMilliseconds,
        'draft_key': draftKey,
        'nested_post': true,
      },
    );
    return models.postCreation(body, siteUrl);
  }

  /// Updates topic metadata before a first-post body edit.
  Future<void> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    required Iterable<TopicTag> tags,
    required Iterable<TopicTag> originalTags,
    int? categoryId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'title': title,
        'category_id': categoryId,
        'tags': tags.map((tag) => tag.toJson()).toList(),
        'original_title': originalTitle,
        'original_tags': originalTags.map((tag) => tag.toJson()).toList(),
      },
    );
  }

  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    await _write(
      Uri.parse('$siteUrl/t/$topicId/tags.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'tags': tags.map((tag) => tag.toJson()).toList()},
    );
  }

  /// Rewrites an existing post, and returns it as the site now holds it.
  ///
  /// Safe to retry, unlike [createPost]: the same raw sent twice leaves the
  /// post saying the same thing, so a timeout here needs no reconciliation.
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    final body = await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      // Nested, which is what the controller reads — a top-level `raw` is
      // ignored and the post comes back unchanged.
      body: {
        'post': {
          'raw': raw,
          'original_text': ?originalText,
          'edit_reason': ?editReason,
        },
      },
    );

    final post = switch (body['post']) {
      final Map<String, dynamic> post => post,
      _ => null,
    };
    if (post == null) throw const WriteException(WriteFailure.unreachable);
    return models.post(post, siteUrl);
  }

  /// Deletes a post.
  ///
  /// What that means is the site's business, not ours, and it is not one thing:
  /// staff get a soft delete they can undo, an author deleting their own post
  /// gets a placeholder that is swept away later, and the last post in some
  /// topics goes for good. So nothing is returned — the caller re-reads the
  /// post to find out which of those happened.
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  /// Rechecks the server-only permanent-deletion constraints.
  ///
  /// The serializer flag only says the action is worth offering. Core still
  /// applies its five-minute/different-admin constraint immediately before the
  /// destructive write and returns a localized reason when it refuses.
  Future<({bool allowed, String? reason})> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    final body = await _getObject(
      Uri.parse('$siteUrl/posts/$postId/permanently_delete_check.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return (
      allowed: body['can_permanently_delete'] == true,
      reason: jsonText(body['reason']),
    );
  }

  /// Irreversibly deletes one soft-deleted reply.
  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'context': '/t/$topicId', 'force_destroy': true},
    );
  }

  /// Deletes the posts selected in a topic's moderation mode.
  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    _validateSelectedPostIds(postIds);
    await _write(
      Uri.parse('$siteUrl/posts/destroy_many.json'),
      siteUrl: siteUrl,
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds, 'agree_with_first_reply_flag': true},
    );
  }

  /// Merges selected replies into the first selected post.
  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    _validateSelectedPostIds(postIds, minimum: 2);
    await _write(
      Uri.parse('$siteUrl/posts/merge_posts.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds},
    );
  }

  /// Moves selected posts to an existing topic or splits them into a new one.
  Future<String> movePosts({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    int? destinationTopicId,
    String? title,
    int? categoryId,
    List<int> tagIds = const [],
    bool chronologicalOrder = false,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _validateSelectedPostIds(postIds);
    if (destinationTopicId != null) {
      _requirePositiveId(destinationTopicId, 'destinationTopicId');
    }
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    if (tagIds.any((id) => id <= 0)) {
      throw ArgumentError.value(tagIds, 'tagIds', 'must contain positive ids');
    }
    final trimmedTitle = title?.trim();
    if ((destinationTopicId == null) ==
        (trimmedTitle == null || trimmedTitle.isEmpty)) {
      throw ArgumentError(
        'Exactly one of destinationTopicId or a non-empty title is required.',
      );
    }
    if (destinationTopicId == topicId) {
      throw ArgumentError.value(
        destinationTopicId,
        'destinationTopicId',
        'must differ from topicId',
      );
    }

    final body = await _write(
      Uri.parse('$siteUrl/t/$topicId/move-posts.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'post_ids': postIds,
        'destination_topic_id': ?destinationTopicId,
        if (trimmedTitle != null && trimmedTitle.isNotEmpty)
          'title': trimmedTitle,
        'category_id': ?categoryId,
        if (tagIds.isNotEmpty) 'tag_ids': tagIds,
        if (destinationTopicId != null)
          'chronological_order': chronologicalOrder,
      },
    );
    final url = jsonText(body['url']);
    if (body['success'] != true || url == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return url;
  }

  /// Reassigns posts by one author to another account.
  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _validateSelectedPostIds(postIds);
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      throw ArgumentError.value(
        username.length,
        'username',
        'must not be empty',
      );
    }
    final body = await _write(
      Uri.parse('$siteUrl/t/$topicId/change-owner.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_ids': postIds, 'username': trimmedUsername},
    );
    if (body['success'] != true) {
      throw const WriteException(WriteFailure.unreachable);
    }
  }

  /// Makes a post collaboratively editable, or returns it to ordinary edits.
  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/wiki.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'wiki': wiki},
    );
  }

  /// Prevents or permits further edits to one post.
  Future<void> updatePostLocked({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool locked,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/locked.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'locked': locked},
    );
  }

  /// Restores a post automatically hidden by the flagging system.
  Future<void> unhidePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/unhide.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  /// Converts an ordinary post to a moderator post, or reverts it.
  Future<void> updatePostType({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postType,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    if (postType != Post.regularPostType &&
        postType != Post.moderatorPostType) {
      throw ArgumentError.value(postType, 'postType', 'must be 1 or 2');
    }
    await _write(
      Uri.parse('$siteUrl/posts/$postId/post_type.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_type': postType},
    );
  }

  /// Adds, changes, or removes the staff notice shown above a post.
  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    final trimmed = notice?.trim();
    await _write(
      Uri.parse('$siteUrl/posts/$postId/notice.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {if (trimmed != null && trimmed.isNotEmpty) 'notice': trimmed},
    );
  }

  /// Likes a post, and returns it as the site now holds it.
  ///
  /// Safe to retry: a second like from the same account is refused as one it
  /// already has, and the post is left saying what it said.
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    return _actedPost(
      await _write(
        Uri.parse('$siteUrl/post_actions.json'),
        siteUrl: siteUrl,
        method: 'POST',
        apiKey: apiKey,
        clientId: clientId,
        body: {'id': postId, 'post_action_type_id': Post.likeActionId},
      ),
      siteUrl,
    );
  }

  /// Privately flags a post and returns the personalized post the site now
  /// holds.
  ///
  /// The response is unwrapped, like the like route. Unlike an undo, creation
  /// is expected to return a post; accepting an empty body as success would
  /// close the editor without any authoritative state to display.
  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    _requirePositiveId(postActionTypeId, 'postActionTypeId');
    final post = _actedPost(
      await _write(
        Uri.parse('$siteUrl/post_actions.json'),
        siteUrl: siteUrl,
        method: 'POST',
        apiKey: apiKey,
        clientId: clientId,
        body: {
          'id': postId,
          'post_action_type_id': postActionTypeId,
          'message': ?message,
        },
      ),
      siteUrl,
    );
    if (post == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return post;
  }

  /// Privately flags a topic through core's first-post action bridge.
  ///
  /// The id is deliberately the topic id and `flag_topic` selects the bridge;
  /// sending the first loaded post id instead would lose core's topic-level
  /// visibility and permission checks.
  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    _requirePositiveId(topicId, 'topicId');
    _requirePositiveId(postActionTypeId, 'postActionTypeId');
    await _write(
      Uri.parse('$siteUrl/post_actions.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'id': topicId,
        'post_action_type_id': postActionTypeId,
        'flag_topic': true,
        'message': ?message,
      },
    );
  }

  /// Takes a like back, and returns the post as the site now holds it.
  ///
  /// The type goes in the query string rather than the body. Discourse reads
  /// it out of either, and a DELETE is the one request whose body nothing
  /// between here and the site is obliged to forward.
  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    return _actedPost(
      await _write(
        Uri.parse(
          '$siteUrl/post_actions/$postId.json'
          '?post_action_type_id=${Post.likeActionId}',
        ),
        siteUrl: siteUrl,
        method: 'DELETE',
        apiKey: apiKey,
        clientId: clientId,
        body: const {},
      ),
      siteUrl,
    );
  }

  /// The post a like route answered with, or null when it answered with none.
  ///
  /// Unlike every other write here the post arrives unwrapped — the controller
  /// serializes it with `root: false` — so there is no envelope to look inside
  /// and the id is what says a post came back at all. Undoing answers with no
  /// content when the post has since stopped being visible to the reader,
  /// which is a success there is simply nothing to draw from.
  Post? _actedPost(Map<String, dynamic> body, String siteUrl) =>
      body['id'] == null ? null : models.post(body, siteUrl);

  /// Who liked a post, oldest like first.
  ///
  /// [limit] is what stops a much-liked post from answering with a few hundred
  /// accounts for a popup that shows a handful. The post's own like count
  /// stays the total, so the caller can say how many were left out.
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    if (limit < 1 || limit > PostLikers.maximumPageSize) {
      throw RangeError.range(limit, 1, PostLikers.maximumPageSize, 'limit');
    }
    final body = await _getObject(
      Uri.parse(
        '$siteUrl/post_action_users.json'
        '?id=$postId&post_action_type_id=${Post.likeActionId}&limit=$limit',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return PostLikers.parse(body, postId: postId, siteUrl: siteUrl);
  }

  /// Puts a deleted post back, where the site allows it.
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    _requirePositiveId(postId, 'postId');
    await _write(
      Uri.parse('$siteUrl/posts/$postId/recover.json'),
      siteUrl: siteUrl,
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    );
  }

  /// Saves the draft of a reply, and returns the sequence to save the next one
  /// against.
  ///
  /// A conflict means the sequence moved under us — the same account writing
  /// from another client, or a post that advanced it. The text in front of the
  /// user is the one they are looking at, so it wins, and the save is repeated
  /// with `force_save`. That is what the web composer does too.
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) async {
    Future<Map<String, dynamic>> send({required bool force}) => _write(
      Uri.parse('$siteUrl/drafts.json'),
      siteUrl: siteUrl,
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {
        'draft_key': draftKey,
        'sequence': sequence,
        // A JSON string rather than an object: the controller rejects anything
        // that is not a String outright.
        'data': data,
        'owner': owner,
        if (force) 'force_save': true,
      },
    );

    Map<String, dynamic> body;
    try {
      body = await send(force: false);
    } on WriteException catch (e) {
      if (e.failure != WriteFailure.conflict) rethrow;
      body = await send(force: true);
    }

    return jsonIntOrNull(body['draft_sequence']);
  }

  /// Uploads one composer image while reporting progress over the file bytes.
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    String? clientId,
  }) async {
    final int fileLength;
    try {
      final resolvedLength = await Future.any<int?>([
        abortTrigger.then((_) => null),
        file.length().then<int?>((value) => value),
      ]);
      if (resolvedLength == null) {
        throw const ComposerUploadException('Upload cancelled.');
      }
      fileLength = resolvedLength;
    } on ComposerUploadException {
      rethrow;
    } catch (_) {
      throw ComposerUploadException("Couldn't read ${file.name}.");
    }

    var sent = 0;
    final timeoutAbort = Completer<void>();
    final timer = Timer(const Duration(minutes: 5), timeoutAbort.complete);
    final request =
        http.AbortableMultipartRequest(
            'POST',
            Uri.parse('$siteUrl/uploads.json'),
            abortTrigger: Future.any<void>([abortTrigger, timeoutAbort.future]),
          )
          ..fields['upload_type'] = uploadType.wireName
          ..files.add(
            http.MultipartFile(
              'file',
              file.openRead().map((chunk) {
                sent += chunk.length;
                onProgress(
                  fileLength == 0 ? 0 : (sent / fileLength).clamp(0, 1),
                );
                return chunk;
              }),
              fileLength,
              filename: file.name,
            ),
          );

    final http.Response response;
    try {
      response = await _transport.sendAuthenticated(
        request,
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        requestTimeout: const Duration(minutes: 5),
      );
    } catch (error) {
      throw ComposerUploadException(
        error is http.RequestAbortedException
            ? 'Upload cancelled.'
            : "Couldn't upload ${file.name}.",
      );
    } finally {
      timer.cancel();
    }

    final decoded = DiscourseTransport.decodeObjectOrEmpty(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ComposerUploadException(
        _uploadError(decoded, file.name),
        statusCode: response.statusCode,
      );
    }

    final originalFilename = jsonText(decoded['original_filename']);
    final id = jsonIntOrNull(decoded['id']);
    final url = jsonText(decoded['url']);
    final shortUrl = jsonText(decoded['short_url']) ?? url;
    if (id == null ||
        id <= 0 ||
        originalFilename == null ||
        url == null ||
        shortUrl == null) {
      throw ComposerUploadException(
        "The site returned an incomplete upload for ${file.name}.",
        statusCode: response.statusCode,
      );
    }
    final thumbnail = jsonObject(decoded['thumbnail']);
    onProgress(1);
    return ComposerUploadResult(
      id: id,
      originalFilename: originalFilename,
      shortUrl: shortUrl,
      url: _absoluteUploadUrl(siteUrl, url),
      width: jsonIntOrNull(decoded['width']),
      height: jsonIntOrNull(decoded['height']),
      thumbnailWidth: jsonIntOrNull(decoded['thumbnail_width']),
      thumbnailHeight: jsonIntOrNull(decoded['thumbnail_height']),
      thumbnailUrl: switch (jsonText(thumbnail['url'])) {
        final value? => _absoluteUploadUrl(siteUrl, value),
        null => null,
      },
    );
  }

  /// Resolves the compact `upload://` URLs stored in raw post markdown.
  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  }) async {
    final requested = shortUrls.toSet();
    if (requested.isEmpty) return const {};
    final request = http.Request(
      'POST',
      Uri.parse('$siteUrl/uploads/lookup-urls'),
    )..body = jsonEncode({'short_urls': requested.toList()});
    final response = await _transport.sendAuthenticated(
      request,
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ComposerUploadException(
        "Couldn't load image previews.",
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) return const {};
    return {
      for (final value in decoded)
        if (value is Map<String, dynamic>)
          if ((jsonText(value['short_url']), jsonText(value['url'])) case (
            final shortUrl?,
            final url?,
          ))
            shortUrl: _absoluteUploadUrl(siteUrl, url),
    };
  }

  static String _absoluteUploadUrl(String siteUrl, String url) =>
      Uri.parse(siteUrl).resolve(url).toString();

  static String _uploadError(Map<String, dynamic> body, String filename) {
    final message = jsonText(body['message']);
    if (message != null && message.trim().isNotEmpty) return message.trim();
    final errors = jsonArray(body['errors'])
        .map(jsonText)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return errors.isEmpty
        ? "Couldn't upload $filename."
        : errors.map((value) => value.trim()).join('\n');
  }

  /// Restores a server draft, including drafts created on another client.
  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  }) async {
    final body = await _getObject(
      Uri.parse('$siteUrl/drafts/${Uri.encodeComponent(draftKey)}.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    return (
      draft: switch (body['draft']) {
        final String value => ComposerDraft.decode(value),
        final Map<String, dynamic> value => ComposerDraft.fromJson(value),
        _ => null,
      },
      sequence: jsonIntOrNull(body['draft_sequence']) ?? 0,
    );
  }

  /// The connected account's drafts, newest first.
  @override
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

  /// Permanently removes one server draft at the sequence the list returned.
  @override
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

  /// The connected account's profile Summary, using core's side-loaded wire
  /// envelope rather than reconstructing rankings from smaller client feeds.
  @override
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

  /// Shared JSON-object write path.
  ///
  /// Unlike [_get] it keeps the decoded body and maps refusals to something the
  /// user can read and act on. Specialized upload payloads use the same
  /// authenticated transport without pretending their response is an object.
  ///
  /// Deliberately never retries, and callers must not either. A user API key
  /// gets no idempotency from Discourse — the request memoizer is gated on
  /// `is_api?`, which needs the `Api-Key` header rather than ours — so a resend
  /// after a timeout publishes the post twice. Recovery is to re-read the
  /// topic and look, not to send it again.
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

  /// Shared GET with the error mapping every authenticated call wants.
  Future<http.Response> _get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) =>
      _transport.get(url, siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  /// Shared object-shaped JSON read. List-shaped compatibility routes keep the
  /// buffered response from [_get] and decode their deliberately wider shape.
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

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async => _getObject(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async => _write(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    clientId: clientId,
    body: body,
  );

  /// Resolves a repository-owned plugin route without letting that extension
  /// boundary redirect a user API key to another origin.
  static Uri _resolvePluginPath(String siteUrl, String path) {
    final site = Uri.parse(siteUrl);
    final target = site.resolve(path);
    if (target.origin != site.origin) {
      throw ArgumentError.value(
        path,
        'path',
        'Plugin API paths must stay on the connected site origin.',
      );
    }
    return target;
  }

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static void _validateSelectedPostIds(List<int> postIds, {int minimum = 1}) {
    if (postIds.length < minimum ||
        postIds.any((id) => id <= 0) ||
        postIds.toSet().length != postIds.length) {
      throw ArgumentError.value(
        postIds,
        'postIds',
        'must contain at least $minimum unique positive ids',
      );
    }
  }

  static void _validatePostWindow(int topicId, List<int> ids) {
    _requirePositiveId(topicId, 'topicId');
    if (ids.length > TopicDetail.maximumInitialPosts) {
      throw RangeError.range(
        ids.length,
        1,
        TopicDetail.maximumInitialPosts,
        'ids.length',
      );
    }
    for (final id in ids) {
      _requirePositiveId(id, 'ids');
    }
  }

  static void _validateComposerLookupValue(
    String value, {
    bool allowEmpty = false,
  }) {
    if ((!allowEmpty && value.isEmpty) ||
        value.length > maximumSearchTermLength) {
      throw ArgumentError(
        'Composer lookup values must be ${allowEmpty ? 'at most' : 'between 1 and'} '
        '$maximumSearchTermLength characters.',
      );
    }
  }

  static void _validateAutocompleteRequest({
    required String term,
    required int limit,
  }) {
    if (term.length > maximumSearchTermLength) {
      throw ArgumentError(
        'Autocomplete terms must be at most '
        '$maximumSearchTermLength characters.',
      );
    }
    if (limit < 1 || limit > maximumAutocompleteResults) {
      throw RangeError.range(limit, 1, maximumAutocompleteResults, 'limit');
    }
  }

  /// Tells the site to forget the key, so deleting our copy does not leave a
  /// live key sitting in the user's authorized-apps list forever.
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse('$siteUrl/user-api-key/revoke'),
    );
    final response = await _transport.sendAuthenticated(
      request,
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

  Future<http.Response> _send(http.BaseRequest request) =>
      _transport.send(request);

  /// How this client names itself, everywhere it talks to a site — including
  /// the message_bus poll, which does not go through here.
  static const String userAgent = DiscourseTransport.userAgent;

  /// Headers every authenticated request carries, matching DiscourseMobile.
  static Map<String, String> authHeaders(String apiKey, {String? clientId}) =>
      DiscourseTransport.authHeaders(apiKey, clientId: clientId);

  /// Icons come back protocol-relative or site-relative depending on the site's
  /// CDN setup.
  static String? _absoluteIcon(String? icon, String baseUrl) {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('//')) {
      final scheme = Uri.tryParse(baseUrl)?.scheme;
      return '${scheme == null || scheme.isEmpty ? 'https' : scheme}:$icon';
    }
    if (icon.startsWith('http://') || icon.startsWith('https://')) return icon;
    return '$baseUrl${icon.startsWith('/') ? '' : '/'}$icon';
  }

  void close() {
    _transport.close();
    _client.close();
  }
}

Iterable<Map<String, dynamic>> _flattenCategories(Object? categories) sync* {
  // Category nesting is site-controlled. Keep preorder without recursively
  // nesting sync* iterators, so a malformed deep tree cannot exhaust the Dart
  // call stack while the otherwise valid response is committed.
  final pending = <Map<String, dynamic>>[];

  void pushReversed(Object? value) {
    final values = jsonArray(value);
    for (var index = values.length - 1; index >= 0; index--) {
      final entry = values[index];
      if (entry is Map<String, dynamic>) pending.add(entry);
    }
  }

  pushReversed(categories);
  while (pending.isNotEmpty) {
    final category = pending.removeLast();
    yield category;
    pushReversed(category['subcategory_list']);
  }
}

class _HeadResult {
  const _HeadResult(this.url, this.statusCode, this.headers);

  final Uri url;
  final int statusCode;
  final Map<String, String> headers;
}
