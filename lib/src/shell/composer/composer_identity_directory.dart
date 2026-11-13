import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';

import '../../data/account_request_session.dart';
import '../../data/api_credentials.dart';
import '../../data/discourse_search_contract.dart';
import '../../data/shell_lookup_api.dart';
import '../../data/site_lifecycle.dart';
import '../../foundation/bounded_lru_cache.dart';
import '../../foundation/elapsed_time.dart';
import '../../foundation/icons/d_icons.dart';
import '../../models/found_group.dart';
import '../../models/found_hashtag.dart';
import '../../models/found_user.dart';
import '../../models/site_emoji.dart';
import '../../plugin_api/composer_target.dart';
import '../../plugin_api/hashtag_kind.dart';
import '../cooking_context_owner.dart' show CookingIdentityMetadata;
import '../hashtag_presentation.dart';
import 'autocomplete.dart';
import 'pills.dart';
import 'triggers.dart';

const int _identityCacheCapacity = 2048;
const int _recentAnswerCapacity = 256;

/// How long core's autocomplete serves an answer before asking again
/// (`user-search.js`, `hashtag-autocomplete.js`).
const Duration _recentAnswerLifetime = Duration(seconds: 30);

typedef ComposerEmojiSource = ({
  bool Function(String siteUrl) enabled,
  Future<SiteEmojiCatalog?> Function(String siteUrl) ensureCatalog,
  Future<Map<String, List<String>>?> Function(String siteUrl)
  ensureSearchAliases,
  List<SiteEmoji> Function(String siteUrl, String query, {int limit}) search,
  String Function(String siteUrl, String name) urlFor,
  Future<void> Function(String siteUrl) ensurePreferences,
  EmojiSkinTone Function(String siteUrl) skinTone,
});

final class ComposerRecipientSearch {
  const ComposerRecipientSearch({
    required this.siteUrl,
    required this.sourceIdentity,
    required this.lease,
    required this.isSourceCurrent,
    required this.search,
  });

  final String siteUrl;
  final Object sourceIdentity;
  final SiteLease lease;
  final bool Function() isSourceCurrent;
  final Future<FoundUsersAndGroups> Function(String term) search;

  bool get isCurrent => lease.isCurrent && isSourceCurrent();
}

/// Answers who a composer's `@` and `#` refer to on each site.
///
/// Each site's identities belong to the account lease that resolved them: a
/// replaced lease retires its resolution, and work it started cannot publish
/// into the next account's.
final class ComposerIdentityDirectory {
  ComposerIdentityDirectory({
    required this._credentials,
    required this._lifecycle,
    required this._search,
    required this._lookups,
    required this._isConnected,
    required this._emoji,
    required this._pluginHashtagPresentation,
    required this._pluginHashtagTypes,
    required this._onChanged,
    this._clock = DateTime.now,
  });

  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final ShellSearchApi _search;
  final ShellLookupApi _lookups;
  final bool Function(String siteUrl) _isConnected;
  final ComposerEmojiSource _emoji;
  final PluginHashtagPresentationResolver _pluginHashtagPresentation;
  final Iterable<String> Function() _pluginHashtagTypes;
  final void Function(String siteUrl, bool artwork) _onChanged;
  final DateTime Function() _clock;
  final Map<String, _ComposerIdentityResolution> _resolutions = {};
  bool _disposed = false;

  CookingIdentityMetadata cookingIdentities(String siteUrl) => (
    mentions: _resolutions[siteUrl]?.mentions ?? const {},
    hashtags: _resolutions[siteUrl]?.hashtags ?? const {},
  );

  _ComposerIdentityResolution _resolutionFor(String siteUrl) {
    final existing = _resolutions[siteUrl];
    if (existing != null && existing.isCurrent) return existing;
    existing?.retire();
    final owner = _ComposerIdentityResolution(
      session: AccountRequestSession(siteUrl, _lifecycle.capture(siteUrl)),
      credentials: _credentials,
      authenticated: _isConnected(siteUrl),
      search: _search,
      lookups: _lookups,
      pluginHashtagTypes: _pluginHashtagTypes(),
      onChanged: (artwork) => _onChanged(siteUrl, artwork),
      clock: _clock,
    );
    if (_disposed) owner.retire();
    return _resolutions[siteUrl] = owner;
  }

  ComposerSearch search(ComposerTarget target) {
    if (_emoji.enabled(target.siteUrl)) {
      unawaited(_emoji.ensureCatalog(target.siteUrl));
      unawaited(_emoji.ensureSearchAliases(target.siteUrl));
    }

    final mentionTopicId = target.mentionTopicId;
    return (
      users: (term) async {
        final found = await _searchMentions(
          siteUrl: target.siteUrl,
          topicId: mentionTopicId != null && mentionTopicId > 0
              ? mentionTopicId
              : null,
          term: term,
        );
        return [
          for (final group in found.groups)
            ComposerSuggestion(
              kind: ComposerTriggerKind.mention,
              value: group.name,
              label: group.name,
              detail: group.fullName ?? appL10n.group,
              art: const ArtIcon(null, fallback: DIcons.users),
            ),
          for (final user in found.users)
            ComposerSuggestion(
              kind: ComposerTriggerKind.mention,
              value: user.username,
              label: user.username,
              detail: user.name,
              art: ArtAvatar(user.avatarUrl),
              siteUrl: target.siteUrl,
              userId: user.id,
              userStatus: user.status,
            ),
        ];
      },
      hashtags: (term) async {
        final found = await searchHashtags(siteUrl: target.siteUrl, term: term);
        return [
          for (final hashtag in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.hashtag,
              // The ref, not the slug: it is what the site cooks against, and
              // the only form that finds a subcategory or tells two things
              // that share a name apart.
              value: hashtag.ref,
              label: hashtag.text,
              detail: hashtag.secondaryText,
              art: _hashtagArt(target.siteUrl, hashtag),
            ),
        ];
      },
      emojis: (query) async {
        if (!_emoji.enabled(target.siteUrl)) return const [];
        final catalog = await _emoji.ensureCatalog(target.siteUrl);
        if (catalog == null ||
            catalog.isEmpty ||
            !_emoji.enabled(target.siteUrl)) {
          return const [];
        }

        unawaited(_emoji.ensureSearchAliases(target.siteUrl));
        await _emoji.ensurePreferences(target.siteUrl);
        if (!_emoji.enabled(target.siteUrl)) return const [];
        final tone = _emoji.skinTone(target.siteUrl);
        final found = _emoji.search(target.siteUrl, query, limit: 5);
        return [
          for (final emoji in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.emoji,
              value: emoji.codeFor(tone),
              label: emoji.codeFor(tone),
              art: ArtImage(emoji.urlFor(tone)),
            ),
          ComposerSuggestion(
            kind: ComposerTriggerKind.emoji,
            value: query,
            label: appL10n.moreEmoji,
            art: const ArtIcon('discourse-emojis'),
            action: ComposerSuggestionAction.openEmojiPicker,
          ),
        ];
      },
    );
  }

  SuggestionArt _hashtagArt(String siteUrl, FoundHashtag hashtag) {
    final presentation = resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: hashtag.type,
        style: HashtagStyle.parse(hashtag.styleType),
        icon: hashtag.icon,
        emoji: hashtag.emoji,
        colorValues: hashtag.colorValues,
      ),
      pluginPresentation: _pluginHashtagPresentation,
    );
    return hashtagSuggestionArt(
      presentation,
      resolveEmoji: (emoji) => _emoji.urlFor(siteUrl, emoji),
    );
  }

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
  }) => _resolutionFor(siteUrl).searchHashtags(term);

  ComposerPills pills(ComposerTarget target) =>
      _resolutionFor(target.siteUrl).pills(target.mentionTopicId);

  ComposerRecipientSearch messageRecipientSearch(String siteUrl) {
    final lease = _lifecycle.capture(siteUrl);
    return ComposerRecipientSearch(
      siteUrl: siteUrl,
      // Lookups compare this with `identical` to survive a rebind.
      sourceIdentity: this,
      lease: lease,
      isSourceCurrent: () => !_disposed,
      search: (term) async {
        try {
          final session = AccountRequestSession(siteUrl, lease);
          final credential = _isConnected(siteUrl)
              ? await session.credentials(_credentials)
              : session.anonymousCredentials();
          if (!lease.isCurrent) return const FoundUsersAndGroups();
          final found = await credential.run(
            () => _search.searchUsersAndGroups(
              siteUrl: siteUrl,
              term: term,
              limit: 20,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          return lease.isCurrent ? found : const FoundUsersAndGroups();
        } catch (error) {
          return const FoundUsersAndGroups();
        }
      },
    );
  }

  Future<FoundUsersAndGroups> _searchMentions({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) => _resolutionFor(siteUrl).searchMentions(term, topicId);

  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) => _resolutionFor(siteUrl).searchUsers(term, topicId);

  void forget(String siteUrl) {
    _resolutions.remove(siteUrl)?.retire();
  }

  void dispose() {
    _disposed = true;
    for (final owner in _resolutions.values) {
      owner.retire();
    }
    _resolutions.clear();
  }
}

/// What a site last answered for each search term.
final class _RecentAnswers<K, V extends Object> {
  _RecentAnswers(this._clock);

  final DateTime Function() _clock;
  final _answers = BoundedLruCache<K, ({V answer, DateTime askedAt})>(
    _recentAnswerCapacity,
  );

  V? read(K key) {
    final held = _answers.read(key);
    if (held == null) return null;
    final age = elapsedSince(held.askedAt, now: _clock());
    return age > _recentAnswerLifetime ? null : held.answer;
  }

  /// Overlapping asks for one term can land out of order; the answer asked
  /// last is the one that stays.
  void remember(K key, V answer, DateTime askedAt) {
    final held = _answers.read(key);
    if (held != null && held.askedAt.isAfter(askedAt)) return;
    _answers.put(key, (answer: answer, askedAt: askedAt));
  }

  void clear() => _answers.clear();
}

final class _ComposerIdentityResolution {
  _ComposerIdentityResolution({
    required this._session,
    required this._credentials,
    required this._authenticated,
    required this._search,
    required this._lookups,
    required Iterable<String> pluginHashtagTypes,
    required this._onChanged,
    required this._clock,
  }) : _hashtagTypes = List.unmodifiable(
         {
           ...defaultDiscourseHashtagOrder,
           ...pluginHashtagTypes,
         }.take(maximumDiscourseHashtagsPerRequest),
       ),
       _recentHashtagAnswers = _RecentAnswers(_clock),
       _recentMentionAnswers = _RecentAnswers(_clock);

  final AccountRequestSession _session;
  final ApiCredentialReader _credentials;
  final bool _authenticated;
  final ShellSearchApi _search;
  final ShellLookupApi _lookups;
  final List<String> _hashtagTypes;
  final void Function(bool artwork) _onChanged;
  final DateTime Function() _clock;
  final _RecentAnswers<String, List<FoundHashtag>> _recentHashtagAnswers;
  final _RecentAnswers<(String, int?), FoundUsersAndGroups>
  _recentMentionAnswers;
  final _hashtags = BoundedLruCache<String, FoundHashtag?>(
    _identityCacheCapacity,
  );
  final _mentions = BoundedLruCache<String, bool>(_identityCacheCapacity);
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
              entry.key: _cookingIdentity(hashtag),
        };

  static Map<String, Object?> _cookingIdentity(FoundHashtag hashtag) => {
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
  };

  static bool _cooksAlike(FoundHashtag a, FoundHashtag b) =>
      jsonEncode(_cookingIdentity(a)) == jsonEncode(_cookingIdentity(b));

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
    final recent = isCurrent ? _recentHashtagAnswers.read(term) : null;
    if (recent != null) return recent;
    final askedAt = _clock();
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
    _recentHashtagAnswers.remember(term, List.unmodifiable(found), askedAt);
    var changed = false;
    for (final hashtag in found) {
      final known = _hashtags.read(hashtag.ref);
      _hashtags.put(hashtag.ref, hashtag);
      if (known == null || !_cooksAlike(known, hashtag)) changed = true;
    }
    if (changed) _onChanged(false);
    return found;
  }

  Future<FoundUsersAndGroups> searchMentions(String term, int? topicId) async {
    final key = (term, topicId);
    final recent = isCurrent ? _recentMentionAnswers.read(key) : null;
    if (recent != null) return recent;
    final askedAt = _clock();
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
    _recentMentionAnswers.remember(key, found, askedAt);
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
    var changed = false;
    for (final name in names) {
      if (_mentions.read(name) == true) continue;
      _mentions.put(name, true);
      changed = true;
    }
    if (changed) _onChanged(false);
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
    final requested = ask.toSet();
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
            _hashtags.put(
              ref,
              FoundHashtag.resolveRef(
                ref,
                candidates: found,
                order: _hashtagTypes,
                requestedRefs: requested,
              ),
            );
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
    _recentHashtagAnswers.clear();
    _recentMentionAnswers.clear();
    _hashtags.clear();
    _mentions.clear();
    _hashtagsInFlight.clear();
    _mentionsInFlight.clear();
  }
}
