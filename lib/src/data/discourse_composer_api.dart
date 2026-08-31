part of 'discourse_api.dart';

final class DiscourseComposerApi {
  const DiscourseComposerApi(this._transport, this._models);

  final DiscourseTransport _transport;
  final DiscourseModelCodec _models;
  static const int maximumSearchTermLength = maximumDiscourseSearchTermLength;
  static const int maximumAutocompleteResults = TopicTagSearch.maximumResults;

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

  Future<PostCreation> createPost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? replyToPostNumber,
    bool whisper = false,
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
        'whisper': whisper ? true : null,
        'typing_duration_msecs': typingDuration.inMilliseconds,
        'composer_open_duration_msecs': composerOpenDuration.inMilliseconds,
        'draft_key': draftKey,
        // Asks for the envelope, which is the only shape carrying `action`.
        // Without it a queued post is indistinguishable from a published one.
        'nested_post': true,
      },
    );

    return _models.postCreation(body, siteUrl);
  }

  Future<PostCreation> createTopic({
    required String siteUrl,
    required String apiKey,
    required String title,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? categoryId,
    Iterable<TopicTag> tags = const [],
    String? targetRecipients,
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
  }) async {
    if (categoryId != null) _requirePositiveId(categoryId, 'categoryId');
    final recipients = targetRecipients == null
        ? null
        : _normalizePrivateMessageRecipients(targetRecipients);
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
        'archetype': recipients == null
            ? null
            : ComposerDraft.privateMessageArchetype,
        'target_recipients': recipients,
        'typing_duration_msecs': typingDuration.inMilliseconds,
        'composer_open_duration_msecs': composerOpenDuration.inMilliseconds,
        'draft_key': draftKey,
        'nested_post': true,
      },
    );
    return _models.postCreation(body, siteUrl);
  }

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
    return _models.post(post, siteUrl);
  }

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

    final fileBytes = file.openRead();
    final http.Response response;
    try {
      response = await _transport.upload(
        url: Uri.parse('$siteUrl/uploads.json'),
        siteUrl: siteUrl,
        apiKey: apiKey,
        uploadType: uploadType.wireName,
        filename: file.name,
        fileLength: fileLength,
        fileBytes: fileBytes,
        onProgress: onProgress,
        abortTrigger: abortTrigger,
        clientId: clientId,
      );
    } catch (error) {
      throw ComposerUploadException(
        error is http.RequestAbortedException
            ? 'Upload cancelled.'
            : "Couldn't upload ${file.name}.",
      );
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

  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  }) async {
    final requested = shortUrls.toSet();
    if (requested.isEmpty) return const {};
    final response = await _transport.requestAuthenticated(
      'POST',
      Uri.parse('$siteUrl/uploads/lookup-urls'),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      jsonBody: {'short_urls': requested.toList()},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ComposerUploadException(
        "Couldn't load image previews.",
        statusCode: response.statusCode,
      );
    }
    final decoded = await decodeJsonHttpResponse(response);
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

  static void _requirePositiveId(int value, String name) {
    if (value <= 0) throw RangeError.value(value, name, 'Must be positive.');
  }

  static String _normalizePrivateMessageRecipients(String value) {
    if (value.length > maximumSearchTermLength || value.contains('\u0000')) {
      throw ArgumentError.value(value, 'targetRecipients');
    }
    final recipients = value
        .split(',')
        .map((recipient) => recipient.trim())
        .where((recipient) => recipient.isNotEmpty)
        .toList();
    if (recipients.isEmpty) {
      throw ArgumentError.value(value, 'targetRecipients');
    }
    return recipients.join(',');
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
}
