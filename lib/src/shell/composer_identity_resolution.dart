part of 'shell_controller.dart';

final class _ComposerIdentityResolution {
  _ComposerIdentityResolution({
    required this._session,
    required this._credentials,
    required this._authenticated,
    required this._search,
    required this._lookups,
    required Iterable<String> pluginHashtagTypes,
    required this._onChanged,
  }) : _hashtagTypes = List.unmodifiable(
         {
           ...defaultDiscourseHashtagOrder,
           ...pluginHashtagTypes,
         }.take(maximumDiscourseHashtagsPerRequest),
       );

  final AccountRequestSession _session;
  final ApiCredentialReader _credentials;
  final bool _authenticated;
  final ShellSearchApi _search;
  final ShellLookupApi _lookups;
  final List<String> _hashtagTypes;
  final void Function(bool artwork) _onChanged;
  final _hashtags = BoundedLruCache<String, FoundHashtag?>(
    ShellController.composerIdentityCacheCapacity,
  );
  final _mentions = BoundedLruCache<String, bool>(
    ShellController.composerIdentityCacheCapacity,
  );
  final _hashtagsInFlight = <String>{};
  final _mentionsInFlight = <String>{};
  bool _retired = false;

  bool get isCurrent => !_retired && _session.lease.isCurrent;
  String get _siteUrl => _session.siteUrl;

  Map<String, bool> get mentions => isCurrent ? _mentions.snapshot : const {};

  Map<String, Object?> get hashtags => !isCurrent
      ? const {}
      : {
          for (final entry in _hashtags.snapshot.entries)
            if (entry.value case final FoundHashtag hashtag)
              entry.key: {
                'type': hashtag.type,
                'ref': hashtag.ref,
                'slug': hashtag.slug,
                'text': hashtag.text,
                'relative_url': hashtag.relativeUrl,
                'icon': hashtag.icon,
                'id': hashtag.id,
                'style_type': hashtag.styleType,
                'emoji': hashtag.emoji,
                'colors': hashtag.colors,
              },
        };

  Future<T> _run<T>(
    Future<T> Function(AccountRequestCredentials credential) operation,
  ) async {
    if (!isCurrent) throw const AccountRequestRetiredException();
    final credential = _authenticated
        ? await _session.credentials(_credentials)
        : _session.anonymousCredentials();
    if (!isCurrent) throw const AccountRequestRetiredException();
    final result = await credential.run(() => operation(credential));
    if (!isCurrent) throw const AccountRequestRetiredException();
    return result;
  }

  Future<List<FoundHashtag>> searchHashtags(String term) async {
    final List<FoundHashtag> found;
    try {
      found = await _run(
        (credential) => _search.searchHashtags(
          siteUrl: _siteUrl,
          term: term,
          order: _hashtagTypes,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (_) {
      return const [];
    }
    if (!isCurrent) return const [];
    for (final hashtag in found) {
      _hashtags.put(hashtag.ref, hashtag);
    }
    if (found.isNotEmpty) _onChanged(false);
    return found;
  }

  Future<FoundUsersAndGroups> searchMentions(String term, int? topicId) async {
    final FoundUsersAndGroups found;
    try {
      found = await _run(
        (credential) => _search.searchMentions(
          siteUrl: _siteUrl,
          term: term,
          topicId: topicId,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (_) {
      if (isCurrent) rethrow;
      return const FoundUsersAndGroups();
    }
    if (!isCurrent) return const FoundUsersAndGroups();
    _seedMentions([
      for (final user in found.users) user.username,
      for (final group in found.groups) group.name,
    ]);
    return found;
  }

  Future<List<FoundUser>> searchUsers(String term, int? topicId) async {
    final List<FoundUser> found;
    try {
      found = await _run(
        (credential) => _lookups.searchUsers(
          siteUrl: _siteUrl,
          term: term,
          topicId: topicId,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
    } catch (_) {
      return const [];
    }
    if (!isCurrent) return const [];
    _seedMentions([for (final user in found) user.username]);
    return found;
  }

  void _seedMentions(List<String> names) {
    for (final name in names) {
      _mentions.put(name, true);
    }
    if (names.isNotEmpty) _onChanged(false);
  }

  ComposerPills pills(int? topicId) => (
    hashtag: (ref) => isCurrent ? _hashtags.read(ref) : null,
    mention: (name) => isCurrent ? _mentions.read(name) : null,
    resolve: (refs, usernames) {
      unawaited(_resolveHashtags(refs));
      unawaited(_resolveMentions(topicId, usernames));
    },
  );

  Future<void> _resolveHashtags(Set<String> refs) async {
    if (!isCurrent) return;
    final ask = [
      for (final ref in refs)
        if (!_hashtags.containsKey(ref) && _hashtagsInFlight.add(ref)) ref,
    ];
    if (ask.isEmpty) return;
    try {
      for (
        var offset = 0;
        offset < ask.length;
        offset += maximumDiscourseHashtagsPerRequest
      ) {
        if (!isCurrent) return;
        final batch = ask
            .skip(offset)
            .take(maximumDiscourseHashtagsPerRequest)
            .toList(growable: false);
        try {
          final found = await _run(
            (credential) => _lookups.lookupHashtags(
              siteUrl: _siteUrl,
              refs: batch,
              order: _hashtagTypes,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          if (!isCurrent) return;
          for (final ref in batch) {
            _hashtags.put(ref, null);
          }
          for (final hashtag in found) {
            _hashtags.put(hashtag.ref, hashtag);
          }
          _onChanged(true);
        } catch (_) {}
      }
    } finally {
      _hashtagsInFlight.removeAll(ask);
    }
  }

  Future<void> _resolveMentions(int? topicId, Set<String> names) async {
    if (!isCurrent) return;
    final ask = [
      for (final name in names)
        if (!_mentions.containsKey(name) && _mentionsInFlight.add(name)) name,
    ];
    if (ask.isEmpty) return;
    try {
      for (
        var offset = 0;
        offset < ask.length;
        offset += maximumDiscourseHashtagsPerRequest
      ) {
        if (!isCurrent) return;
        final batch = ask
            .skip(offset)
            .take(maximumDiscourseHashtagsPerRequest)
            .toList(growable: false);
        try {
          final real = await _run(
            (credential) => _lookups.checkMentions(
              siteUrl: _siteUrl,
              names: batch,
              topicId: topicId,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          if (!isCurrent) return;
          for (final name in batch) {
            _mentions.put(name, real.contains(name));
          }
          _onChanged(true);
        } catch (_) {}
      }
    } finally {
      _mentionsInFlight.removeAll(ask);
    }
  }

  void retire() {
    _retired = true;
    _hashtags.clear();
    _mentions.clear();
    _hashtagsInFlight.clear();
    _mentionsInFlight.clear();
  }
}
