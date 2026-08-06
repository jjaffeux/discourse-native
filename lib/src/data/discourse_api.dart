import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/topic.dart';
import '../models/user_card.dart';

/// Why a site lookup did not produce an instance.
enum SiteLookupFailure {
  /// Reachable, but not a Discourse — or one too old to talk to an app.
  notDiscourse,

  /// Nothing answered: bad host, no network, timeout, or a non-200 status.
  unreachable,
}

class SiteLookupException implements Exception {
  const SiteLookupException(this.failure, this.term);

  final SiteLookupFailure failure;
  final String term;

  String get message => switch (failure) {
    SiteLookupFailure.notDiscourse =>
      '$term is not a Discourse forum, or is running a version too old to '
          'support apps.',
    SiteLookupFailure.unreachable => "Couldn't reach $term.",
  };

  @override
  String toString() => 'SiteLookupException($failure, $term)';
}

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

class WriteException implements Exception {
  const WriteException(
    this.failure, {
    this.errors = const [],
    this.statusCode,
    this.retryAfter,
  });

  final WriteFailure failure;

  /// Discourse's own messages. Already written for a reader, so they are shown
  /// as they arrive rather than translated into something of ours.
  final List<String> errors;

  final int? statusCode;

  /// How long to wait before trying again, on a [WriteFailure.rateLimited].
  final Duration? retryAfter;

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
  String toString() => 'WriteException($failure, $statusCode, $errors)';
}

/// Talks to a Discourse site.
///
/// The lookup mirrors DiscourseMobile's `Site.fromTerm`: probe
/// `/user-api-key/new` to confirm it is a Discourse new enough to expose the
/// user API, then read `/site/basic-info.json` for the details we display.
class DiscourseApi {
  DiscourseApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  static const int minimumApiVersion = 2;
  static const int _maxRedirects = 5;

  final http.Client _client;
  final Duration timeout;

  /// Turns whatever the user typed into a URL to probe.
  ///
  /// Bare hosts get https, since that is what any site worth connecting to
  /// serves; typing an explicit `http://` is the escape hatch for local
  /// development.
  static Uri normalize(String term) {
    var trimmed = term.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      trimmed = 'https://$trimmed';
    }
    return Uri.parse(trimmed);
  }

  Future<DiscourseInstance> lookup(String term) async {
    final probe = normalize(term).resolve('/user-api-key/new');

    final _HeadResult head;
    try {
      head = await _head(probe);
    } on SiteLookupException {
      rethrow;
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }

    // A Discourse always has this route; a 404 means we are talking to
    // something else, or to a version that predates the user API.
    if (head.statusCode == 404) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, term);
    }
    if (head.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
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
      final response = await _client
          .get(Uri.parse('$baseUrl/site/basic-info.json'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw SiteLookupException(SiteLookupFailure.unreachable, term);
      }
      info = jsonDecode(response.body) as Map<String, dynamic>;
    } on SiteLookupException {
      rethrow;
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, term);
    }

    final title = (info['title'] as String?)?.trim();

    return DiscourseInstance(
      url: baseUrl,
      title: title == null || title.isEmpty ? Uri.parse(baseUrl).host : title,
      description: info['description'] as String?,
      iconUrl: _absoluteIcon(info['apple_touch_icon_url'] as String?, baseUrl),
      apiVersion: apiVersion,
      loginRequired: info['login_required'] as bool? ?? false,
    );
  }

  /// HEAD, following redirects by hand so the final URL is observable —
  /// `package:http` reports the originally requested one.
  Future<_HeadResult> _head(Uri url) async {
    var current = url;

    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('HEAD', current)..followRedirects = false;
      final response = await _client.send(request).timeout(timeout);
      await response.stream.drain<void>();

      final location = response.headers['location'];
      final isRedirect =
          const {301, 302, 303, 307, 308} //
              .contains(response.statusCode);

      if (!isRedirect || location == null) {
        return _HeadResult(current, response.statusCode, response.headers);
      }
      current = current.resolve(location);
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
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$siteUrl/session/current.json'),
            headers: authHeaders(apiKey, clientId: clientId),
          )
          .timeout(timeout);
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['current_user'] as Map<String, dynamic>?;
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }

    return DiscourseUser(
      username: user['username'] as String,
      name: user['name'] as String?,
      avatarUrl: _avatarUrl(user['avatar_template'] as String?, siteUrl),
    );
  }

  /// Every unread counter the shell shows, in one request.
  ///
  /// Cheap enough to call on launch for each connected site, which is what
  /// DiscourseMobile does.
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$siteUrl/notifications/totals.json'),
            headers: authHeaders(apiKey, clientId: clientId),
          )
          .timeout(timeout);
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    return NotificationTotals.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

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
  Future<TopicDetail> topic({
    required String siteUrl,
    required String slug,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      // A link can arrive without a slug — `/t/123` — and Discourse routes
      // that too, so there is nothing to invent here.
      Uri.parse(
        slug.isEmpty ? '$siteUrl/t/$id.json' : '$siteUrl/t/$slug/$id.json',
      ),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );

    return TopicDetail.fromJson(
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
    final stream = body['post_stream'] as Map<String, dynamic>? ?? const {};
    return (stream['posts'] as List<dynamic>? ?? const [])
        .map((p) => Post.fromJson(p as Map<String, dynamic>, siteUrl))
        .toList();
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
    final user = body['user'] as Map<String, dynamic>?;
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return UserCard.fromJson(user, siteUrl);
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
    final list = body['category_list'] as Map<String, dynamic>? ?? const {};
    final result = <TopicCategory>[];

    for (final entry in (list['categories'] as List<dynamic>? ?? const [])) {
      final map = entry as Map<String, dynamic>;
      result.add(TopicCategory.fromJson(map));
      for (final sub
          in (map['subcategory_list'] as List<dynamic>? ?? const [])) {
        result.add(TopicCategory.fromJson(sub as Map<String, dynamic>));
      }
    }
    return result;
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

    return switch (body['draft_sequence']) {
      final num sequence => sequence.toInt(),
      final String sequence => int.tryParse(sequence),
      _ => null,
    };
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
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } catch (_) {
      throw const WriteException(WriteFailure.unreachable);
    }

    final decoded = _decode(response.body);
    if (response.statusCode == 200) return decoded;

    final errors = [
      for (final error in decoded['errors'] as List<dynamic>? ?? const [])
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

    final extras = body['extras'] as Map<String, dynamic>?;
    return switch (extras?['wait_seconds']) {
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
      response = await _client
          .get(
            url,
            headers: apiKey == null
                ? const {}
                : authHeaders(apiKey, clientId: clientId),
          )
          .timeout(timeout);
    } catch (_) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }

    if (response.statusCode == 403 || response.statusCode == 401) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    if (response.statusCode != 200) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return response;
  }

  /// Tells the site to forget the key, so deleting our copy does not leave a
  /// live key sitting in the user's authorized-apps list forever.
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$siteUrl/user-api-key/revoke'),
          headers: authHeaders(apiKey, clientId: clientId),
        )
        .timeout(timeout);

    // 404 means the site predates the revoke route; nothing to do about it.
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
  }

  /// Headers every authenticated request carries, matching DiscourseMobile.
  static Map<String, String> authHeaders(String apiKey, {String? clientId}) => {
    'User-Api-Key': apiKey,
    'User-Api-Client-Id': ?clientId,
    'User-Agent': 'DiscourseNative/1.0',
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
