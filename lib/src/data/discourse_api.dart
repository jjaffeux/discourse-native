import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../diagnostics/diagnostic_error_cause.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/json.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_likers.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../plugins/chat/chat_channel.dart';
import '../plugins/chat/chat_message.dart';
import '../plugins/poll/poll.dart';
import '../plugins/reactions/post_reactors.dart';
import 'discourse_api_contracts.dart';
import 'http_transport.dart';
import 'site_appearance_loader.dart';

export 'discourse_api_contracts.dart';

/// Why a write did not go through.
///
/// Reads collapse into "couldn't reach it" because there is nothing the reader
/// can do either way. A write is the opposite: the user typed something, it was
/// refused, and the reason decides what they do next — fix the text, wait,
/// reconnect, or reload.
enum WriteFailure {
  /// The site refused the content. [WriteException.errors] says why, in words
  /// Discourse already wrote for a reader.
  validation,

  /// Too fast. [WriteException.retryAfter] says how long to wait, when the
  /// site said.
  rateLimited,

  /// Not allowed here — or the key is gone. The two are indistinguishable from
  /// the status alone, since Discourse answers 403 to both.
  forbidden,

  /// Someone changed it first. Only edits can hit this.
  conflict,

  /// Nothing answered, or what answered made no sense.
  unreachable,
}

class WriteException implements Exception, DiagnosticErrorCause {
  const WriteException(
    this.failure, {
    this.errors = const [],
    this.statusCode,
    this.retryAfter,
    this.cause,
    this.causeStackTrace,
  });

  final WriteFailure failure;

  /// Discourse's own messages. Already written for a reader, so they are shown
  /// as they arrive rather than translated into something of ours.
  final List<String> errors;

  final int? statusCode;

  /// How long to wait before trying again, on a [WriteFailure.rateLimited].
  final Duration? retryAfter;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  Object get diagnosticCause => cause ?? this;

  @override
  StackTrace? get diagnosticCauseStackTrace => causeStackTrace;

  String get message {
    if (errors.isNotEmpty) return errors.join('\n');
    return switch (failure) {
      WriteFailure.validation => "That wasn't accepted.",
      WriteFailure.rateLimited => switch (retryAfter) {
        final wait? => 'Too fast — try again in ${wait.inSeconds}s.',
        null => 'Too fast — try again in a moment.',
      },
      WriteFailure.forbidden =>
        "You can't post that here — or the connection to this site has "
            'expired.',
      WriteFailure.conflict => 'Someone else changed that first.',
      WriteFailure.unreachable => "Couldn't reach the site.",
    };
  }

  @override
  String toString() =>
      'WriteException($failure, statusCode: $statusCode, '
      'retryAfter: $retryAfter)';
}

/// Talks to a Discourse site.
///
/// The lookup mirrors DiscourseMobile's `Site.fromTerm`: probe
/// `/user-api-key/new` to confirm it is a Discourse new enough to expose the
/// user API, then read `/site/basic-info.json` for the details we display.
class DiscourseApi
    implements AccountActivityApi, ChatApi, ReactionsApi, PollsApi {
  DiscourseApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    int maxResponseBytes = 16 * 1024 * 1024,
  }) : assert(timeout > Duration.zero),
       assert(maxResponseBytes > 0),
       _maxResponseBytes = maxResponseBytes,
       _client = client == null
           ? SafeHttpClient.create()
           : SafeHttpClient.owned(client);

  static const int minimumApiVersion = 2;
  static const int _maxRedirects = 5;

  final http.Client _client;
  final Duration timeout;

  /// Largest buffered API response accepted from a site.
  ///
  /// These routes return JSON rather than media. Keeping a generous finite
  /// bound prevents a broken endpoint from growing the process without limit.
  final int _maxResponseBytes;

  late final SiteAppearanceLoader _siteAppearanceLoader = SiteAppearanceLoader(
    client: _client,
    timeout: timeout,
    maxResponseBytes: _maxResponseBytes < 2 * 1024 * 1024
        ? _maxResponseBytes
        : 2 * 1024 * 1024,
  );

  /// Turns whatever the user typed into a URL to probe.
  ///
  /// Bare hosts get https, since that is what any site worth connecting to
  /// serves. Explicit HTTP is reserved for loopback development servers.
  static Uri normalize(String term) {
    var trimmed = term.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    final url = Uri.parse(trimmed);
    try {
      return requireSafeHttpUrl(url);
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        url.toString(),
        cause: error,
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
    final response = await _get(
      Uri.parse('$siteUrl/session/current.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = switch (body['current_user']) {
      final Map<String, dynamic> user => user,
      _ => null,
    };
    final username = jsonText(user?['username']);
    if (user == null || username == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }

    return DiscourseUser(
      username: username,
      id: jsonIntOrNull(user['id']),
      name: jsonText(user['name']),
      avatarUrl: _avatarUrl(jsonText(user['avatar_template']), siteUrl),
      // Plugin serializers omit can_create_poll when Poll is unavailable.
      // Preserve that distinction so the composer never guesses capability.
      canCreatePoll: user.containsKey('can_create_poll')
          ? user['can_create_poll'] == true
          : null,
      staff:
          user['staff'] == true ||
          user['admin'] == true ||
          user['moderator'] == true,
      groups: List.unmodifiable([
        for (final group in jsonObjects(user['groups']))
          ?jsonText(group['name']),
      ]),
    );
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
    final response = await _get(
      Uri.parse('$siteUrl/notifications/totals.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return NotificationTotals.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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
  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/notifications.json?recent=true&limit=$limit'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return List.unmodifiable([
      for (final entry in jsonObjects(body['notifications']))
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
    final response = await _get(
      Uri.parse(
        '$siteUrl/u/${Uri.encodeComponent(username)}/user-menu-bookmarks.json',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      reminders: List<DiscourseNotification>.unmodifiable([
        for (final entry in jsonObjects(body['notifications']))
          DiscourseNotification.fromJson(entry),
      ]),
      bookmarks: List<Bookmark>.unmodifiable([
        for (final entry in jsonObjects(body['bookmarks']))
          Bookmark.fromJson(entry),
      ]),
    );
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
  }) => _write(
    Uri.parse('$siteUrl/notifications/mark-read.json'),
    method: 'PUT',
    apiKey: apiKey,
    clientId: clientId,
    body: {'id': id},
  );

  /// One page of a topic list. [path] is the list route, e.g. `/latest.json`.
  ///
  /// The same envelope serves latest, new, unread, top and private messages,
  /// so they all come through here.
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl$path'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return TopicList.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      siteUrl,
    );
  }

  /// A topic with its first chunk of posts (20) and the full list of post ids.
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    String? apiKey,
    String? clientId,
  }) async {
    final path = [
      siteUrl,
      't',
      if (slug.isNotEmpty) slug,
      '$id',
      if (slug.isNotEmpty && postNumber != null) '$postNumber',
    ].join('/');
    final response = await _get(
      // A link can arrive without a slug — `/t/123` — and Discourse routes
      // that too, so there is nothing to invent here.
      // The slugless numbered shape is ambiguous with `/t/{slug}/{id}`, so it
      // names its target in the query, as Discourse's own reload does.
      Uri.parse('$path.json').replace(
        queryParameters: slug.isEmpty && postNumber != null
            ? {'post_number': '$postNumber'}
            : null,
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return TopicDetail.parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      siteUrl,
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

    final query = [
      ...ids.map((id) => 'post_ids[]=$id'),
      if (includeRaw) 'include_raw=true',
    ].join('&');
    final response = await _get(
      Uri.parse('$siteUrl/t/$topicId/posts.json?$query'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final stream = jsonObject(body['post_stream']);
    return List.unmodifiable([
      for (final post in jsonObjects(stream['posts']))
        Post.fromJson(post, siteUrl),
    ]);
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
    final response = await _get(
      Uri.parse('$siteUrl/u/${Uri.encodeComponent(username)}/card.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = switch (body['user']) {
      final Map<String, dynamic> user => user,
      _ => null,
    };
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return UserCard.fromJson(user, siteUrl);
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
    final response = await _get(
      Uri.parse('$siteUrl/site/settings.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return SiteConfig.fromSettings(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
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
    final query = {
      'term': term,
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
          for (final user in users)
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
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/hashtags/search.json').replace(
        // `<String, dynamic>` so the list is emitted as a repeated parameter.
        // A `Map<String, String>` would stringify it to `[category, tag]` and
        // the site would reject the lot.
        queryParameters: <String, dynamic>{
          'term': term,
          'order[]': hashtagOrder,
        },
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    try {
      return switch (jsonDecode(response.body)) {
        {'results': final List<dynamic> results} => [
          for (final item in results)
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
    final slugs = refs.take(hashtagsPerRequest).toList();
    if (slugs.isEmpty) return const [];

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
      return [
        for (final entry in body.values)
          if (entry is List<dynamic>)
            for (final item in entry)
              if (item is Map<String, dynamic>) ?FoundHashtag.fromJson(item),
      ];
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
    final asked = names.take(hashtagsPerRequest).toList();
    if (asked.isEmpty) return const {};

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
          if (name is String) name,
        ...jsonObject(body['groups']).keys,
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

  /// Every emoji a site allows, flattened out of the groups it lists them in.
  ///
  /// `/emojis.json` answers with `Emoji.grouped` — an object of group name to
  /// list — and the grouping is a picker's business, not a completion's. The
  /// site has already dropped the emoji it denies, so nothing here has to, and
  /// custom uploads are in the same payload carrying their own upload url.
  Future<List<SiteEmoji>> emojis({
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
      if (decoded is! Map<String, dynamic>) return const [];

      return [
        for (final group in decoded.values)
          if (group is List<dynamic>)
            for (final emoji in group)
              if (emoji case {
                'name': final String name,
                'url': final String url,
              })
                if (_absoluteIcon(url, siteUrl) case final resolved?)
                  SiteEmoji(name: name, url: resolved),
      ];
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
  }) async {
    final response = await _get(
      Uri.parse('$siteUrl/categories.json?include_subcategories=true'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = jsonObject(body['category_list']);
    final result = <TopicCategory>[];

    for (final category in jsonObjects(list['categories'])) {
      result.add(TopicCategory.fromJson(category));
      for (final subcategory in jsonObjects(category['subcategory_list'])) {
        result.add(TopicCategory.fromJson(subcategory));
      }
    }
    return List.unmodifiable(result);
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
    final body = await _write(
      Uri.parse('$siteUrl/posts.json'),
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

    return PostCreation.fromJson(body, siteUrl);
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
    String? editReason,
    String? clientId,
  }) async {
    final body = await _write(
      Uri.parse('$siteUrl/posts/$postId.json'),
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      // Nested, which is what the controller reads — a top-level `raw` is
      // ignored and the post comes back unchanged.
      body: {
        'post': {'raw': raw, 'edit_reason': ?editReason},
      },
    );

    final post = switch (body['post']) {
      final Map<String, dynamic> post => post,
      _ => null,
    };
    if (post == null) throw const WriteException(WriteFailure.unreachable);
    return Post.fromJson(post, siteUrl);
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
  }) => _write(
    Uri.parse('$siteUrl/posts/$postId.json'),
    method: 'DELETE',
    apiKey: apiKey,
    clientId: clientId,
    body: const {},
  );

  /// Likes a post, and returns it as the site now holds it.
  ///
  /// Safe to retry: a second like from the same account is refused as one it
  /// already has, and the post is left saying what it said.
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _actedPost(
    await _write(
      Uri.parse('$siteUrl/post_actions.json'),
      method: 'POST',
      apiKey: apiKey,
      clientId: clientId,
      body: {'id': postId, 'post_action_type_id': Post.likeActionId},
    ),
    siteUrl,
  );

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
  }) async => _actedPost(
    await _write(
      Uri.parse(
        '$siteUrl/post_actions/$postId.json'
        '?post_action_type_id=${Post.likeActionId}',
      ),
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    ),
    siteUrl,
  );

  /// The post a like route answered with, or null when it answered with none.
  ///
  /// Unlike every other write here the post arrives unwrapped — the controller
  /// serializes it with `root: false` — so there is no envelope to look inside
  /// and the id is what says a post came back at all. Undoing answers with no
  /// content when the post has since stopped being visible to the reader,
  /// which is a success there is simply nothing to draw from.
  static Post? _actedPost(Map<String, dynamic> body, String siteUrl) =>
      body['id'] == null ? null : Post.fromJson(body, siteUrl);

  /// Gives, moves or takes back this reader's reaction, and answers with the
  /// post as the site now holds it — unwrapped, like the like routes.
  ///
  /// A true toggle, and so **not idempotent**: sending the same reaction twice
  /// removes it, and a different one replaces what was there. [_write] already
  /// refuses to retry and callers must not either — here a resend after a
  /// timeout would not double-apply, it would undo.
  ///
  /// The reaction is a path segment, so it is percent-encoded. `+1` is a
  /// perfectly ordinary reaction id.
  ///
  /// A 404 means the plugin has been switched off — its controller is behind
  /// `requires_plugin` — **or** that the post is gone. The same bytes for both,
  /// which is why the caller repairs one post rather than a whole site.
  Future<Post?> toggleReaction({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String reaction,
    String? clientId,
  }) async => _actedPost(
    await _write(
      Uri.parse(
        '$siteUrl/discourse-reactions/posts/$postId'
        '/custom-reactions/${Uri.encodeComponent(reaction)}/toggle.json',
      ),
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: const {},
    ),
    siteUrl,
  );

  /// Casts or changes this reader's selection in one named poll.
  ///
  /// The response is personalized: its poll contains the result visibility
  /// this reader earned by voting, and `vote` is the selection the server
  /// actually saved. A malformed success is treated as unreachable so the
  /// controller reconciles by refetching the post rather than applying a
  /// guessed selection.
  @override
  Future<PollVoteResponse> votePoll({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    required List<String> options,
    String? clientId,
  }) async {
    final body = await _write(
      Uri.parse('$siteUrl/polls/vote.json'),
      method: 'PUT',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_id': postId, 'poll_name': pollName, 'options': options},
    );
    return _pollVoteResponse(
      body,
      siteUrl: siteUrl,
      pollName: pollName,
      requireVote: true,
    );
  }

  /// Removes this reader's selection from one named poll.
  @override
  Future<PollVoteResponse> removePollVote({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    String? clientId,
  }) async {
    final body = await _write(
      Uri.parse('$siteUrl/polls/vote.json'),
      method: 'DELETE',
      apiKey: apiKey,
      clientId: clientId,
      body: {'post_id': postId, 'poll_name': pollName},
    );
    return _pollVoteResponse(
      body,
      siteUrl: siteUrl,
      pollName: pollName,
      requireVote: false,
    );
  }

  static PollVoteResponse _pollVoteResponse(
    Map<String, dynamic> body, {
    required String siteUrl,
    required String pollName,
    required bool requireVote,
  }) {
    final rawPoll = body['poll'];
    if (rawPoll is! Map<String, dynamic> ||
        rawPoll['name'] is! String ||
        rawPoll['type'] is! String ||
        rawPoll['status'] is! String ||
        rawPoll['results'] is! String ||
        rawPoll['options'] is! List ||
        rawPoll['chart_type'] is! String ||
        (requireVote && body['vote'] is! List)) {
      throw const WriteException(WriteFailure.unreachable);
    }

    final withoutSelection = Poll.fromJson(rawPoll, siteUrl);
    if (withoutSelection == null ||
        withoutSelection.name != pollName ||
        withoutSelection.options.length !=
            (rawPoll['options'] as List).length) {
      throw const WriteException(WriteFailure.unreachable);
    }
    final selection = requireVote
        ? PollSelection.fromJson(body['vote'], type: withoutSelection.type)
        : PollSelection.none;
    // A non-ranked vote is a list of non-empty digest strings. Silently
    // accepting a list of objects as an empty vote would make a malformed
    // success look like the server removed the reader's selection.
    if (requireVote &&
        withoutSelection.type != PollType.rankedChoice &&
        selection.optionIds.length != (body['vote'] as List).length) {
      throw const WriteException(WriteFailure.unreachable);
    }
    final optionIds = withoutSelection.options
        .map((option) => option.id)
        .toSet();
    if (selection.optionIds.any((id) => !optionIds.contains(id)) ||
        selection.rankedChoices.any(
          (choice) => !optionIds.contains(choice.digest),
        )) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return PollVoteResponse(
      poll: withoutSelection.withSelection(selection),
      selection: selection,
    );
  }

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
    final response = await _get(
      Uri.parse(
        '$siteUrl/post_action_users.json'
        '?id=$postId&post_action_type_id=${Post.likeActionId}&limit=$limit',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return PostLikers.parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      postId: postId,
      siteUrl: siteUrl,
    );
  }

  /// Puts a deleted post back, where the site allows it.
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => _write(
    Uri.parse('$siteUrl/posts/$postId/recover.json'),
    method: 'PUT',
    apiKey: apiKey,
    clientId: clientId,
    body: const {},
  );

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

  /// Shared write, and the only path in here that sends a body.
  ///
  /// Unlike [_get] it keeps the status and the decoded body, because a refused
  /// write is something the user has to read and act on.
  ///
  /// Deliberately never retries, and callers must not either. A user API key
  /// gets no idempotency from Discourse — the request memoizer is gated on
  /// `is_api?`, which needs the `Api-Key` header rather than ours — so a resend
  /// after a timeout publishes the post twice. Recovery is to re-read the
  /// topic and look, not to send it again.
  Future<Map<String, dynamic>> _write(
    Uri url, {
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      final request = http.Request(method, url)
        ..headers.addAll(authHeaders(apiKey, clientId: clientId))
        // Null entries are dropped rather than sent: Rails reads a missing
        // parameter and an explicit null differently, and every optional field
        // here means "the server picks" when absent.
        ..body = jsonEncode({
          for (final entry in body.entries)
            if (entry.value != null) entry.key: entry.value,
        });
      response = await _send(request);
    } catch (error, stackTrace) {
      throw WriteException(
        WriteFailure.unreachable,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    final decoded = _decode(response.body);
    // Any 2xx, not 200 alone: a delete answers with no content, and which of
    // the empty-success statuses that is depends on the route.
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final errors = [
      for (final error in jsonArray(decoded['errors']))
        if (error is String && error.trim().isNotEmpty) error.trim(),
    ];

    throw WriteException(
      switch (response.statusCode) {
        401 || 403 => WriteFailure.forbidden,
        409 => WriteFailure.conflict,
        429 => WriteFailure.rateLimited,
        // A refused write is a 422 carrying messages. Anything else that
        // brought messages is treated the same way rather than hidden behind
        // "couldn't reach it", which would throw away the only useful part.
        _ when errors.isNotEmpty => WriteFailure.validation,
        _ => WriteFailure.unreachable,
      },
      errors: errors,
      statusCode: response.statusCode,
      retryAfter: _retryAfter(response, decoded),
    );
  }

  /// Nothing about an error body is guaranteed — a proxy or a 500 answers with
  /// HTML — so failing to decode is not itself an error.
  static Map<String, dynamic> _decode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// How long to wait after a 429. Discourse sends `Retry-After` and repeats it
  /// in `extras.wait_seconds`; neither is guaranteed, so take whichever came.
  static Duration? _retryAfter(
    http.Response response,
    Map<String, dynamic> body,
  ) {
    final header = int.tryParse(response.headers['retry-after'] ?? '');
    if (header != null) return Duration(seconds: header);

    final extras = jsonObject(body['extras']);
    return switch (extras['wait_seconds']) {
      final num seconds => Duration(seconds: seconds.round()),
      final String seconds when int.tryParse(seconds) != null => Duration(
        seconds: int.parse(seconds),
      ),
      _ => null,
    };
  }

  /// Shared GET with the error mapping every authenticated call wants.
  Future<http.Response> _get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      final request = http.Request('GET', url)
        ..headers.addAll(
          apiKey == null ? const {} : authHeaders(apiKey, clientId: clientId),
        );
      response = await _send(request);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      throw SiteLookupException(
        SiteLookupFailure.notDiscourse,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  /// Who reacted to a post, oldest first, likers and reactors merged.
  ///
  /// [reaction] narrows it to one emoji. [limit] is clamped server side to
  /// 1..50 and defaults to 30 there; sent explicitly so the number in the code
  /// is the number that applies.
  ///
  /// Unauthenticated reads are allowed — the plugin's controller exempts this
  /// route from `ensure_logged_in` — so a signed-out reader can still see who
  /// reacted.
  @override
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      Uri.parse(
        '$siteUrl/discourse-reactions/posts/$postId/reactions-users-list.json'
        '?limit=$limit'
        '${reaction == null ? '' : '&reaction_value=${Uri.encodeQueryComponent(reaction)}'}',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return PostReactors.parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      postId: postId,
      siteUrl: siteUrl,
      filter: reaction,
    );
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
    final response = await _get(
      Uri.parse('$siteUrl/chat/api/me/channels.json'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return ChatChannel.parse(
      jsonDecode(response.body) as Map<String, dynamic>,
      siteUrl,
    );
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
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    assert(
      [before != null, after != null, fromLastRead].where((on) => on).length <=
          1,
      'A page is asked for in one shape at a time; the site reads only the '
      'first it recognises and the caller would not be told which.',
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
      if (before != null) ...['direction=past', 'target_message_id=$before'],
      if (after != null) ...['direction=future', 'target_message_id=$after'],
    ].join('&');

    final response = await _get(
      Uri.parse('$siteUrl/chat/api/channels/$channelId/messages.json?$query'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return ChatMessage.parsePage(
      jsonDecode(response.body) as Map<String, dynamic>,
      siteUrl,
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
  }) => _write(
    Uri.parse(
      '$siteUrl/chat/api/channels/$channelId/read.json?message_id=$messageId',
    ),
    method: 'PUT',
    apiKey: apiKey,
    clientId: clientId,
    body: const {},
  );

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
    )..headers.addAll(authHeaders(apiKey, clientId: clientId));
    final response = await _send(request);

    // 404 means the site predates the revoke route; nothing to do about it.
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: response.statusCode,
      );
    }
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await sendBoundedHttpRequest(
        _client,
        request,
        timeout: timeout,
        maxBodyBytes: _maxResponseBytes,
      );
    } on UnsafeHttpTransportException catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        error.url.toString(),
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  /// How this client names itself, everywhere it talks to a site — including
  /// the message_bus poll, which does not go through here.
  static const String userAgent = 'DiscourseNative/1.0';

  /// Headers every authenticated request carries, matching DiscourseMobile.
  static Map<String, String> authHeaders(String apiKey, {String? clientId}) => {
    'User-Api-Key': apiKey,
    'User-Api-Client-Id': ?clientId,
    'User-Agent': userAgent,
    'Content-Type': 'application/json',
    'Dont-Chunk': 'true',
  };

  /// Avatar templates carry a `{size}` placeholder and may be site-relative.
  static String? _avatarUrl(String? template, String baseUrl) {
    if (template == null || template.isEmpty) return null;
    final sized = template.replaceAll('{size}', '120');
    return _absoluteIcon(sized, baseUrl);
  }

  /// Icons come back protocol-relative or site-relative depending on the site's
  /// CDN setup.
  static String? _absoluteIcon(String? icon, String baseUrl) {
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('//')) return 'https:$icon';
    if (icon.startsWith('http://') || icon.startsWith('https://')) return icon;
    return '$baseUrl${icon.startsWith('/') ? '' : '/'}$icon';
  }

  void close() => _client.close();
}

class _HeadResult {
  const _HeadResult(this.url, this.statusCode, this.headers);

  final Uri url;
  final int statusCode;
  final Map<String, String> headers;
}
