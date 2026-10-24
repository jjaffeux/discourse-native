import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:flutter/foundation.dart' show Listenable, VoidCallback;

import '../data/application_cooking.dart';
import '../data/store.dart';
import '../foundation/timezone_environment.dart';
import '../models/discourse_user.dart';
import '../models/post.dart';
import '../models/site_config.dart';
import '../models/user_card.dart';
import 'site_presentation_controller.dart';

typedef CookingIdentityMetadata = ({
  Map<String, Object?> mentions,
  Map<String, Object?> hashtags,
});

final class CookingContextOwner {
  CookingContextOwner({
    required this._cooking,
    required this._store,
    required this._presentation,
    required this._timezones,
    required this._currentUserFor,
    required this._identitiesFor,
  });

  final ApplicationCooking _cooking;
  final Store _store;
  final SitePresentationController _presentation;
  final TimezoneEnvironment _timezones;
  final DiscourseUser? Function(String siteUrl) _currentUserFor;
  final CookingIdentityMetadata Function(String siteUrl) _identitiesFor;
  final _requestStamps = Expando<_CookingSourceStamp>();
  final Set<_CookingWatch> _watches = {};
  bool _disposed = false;

  _CookingSourceStamp _stamp(String siteUrl) {
    final user = _currentUserFor(siteUrl);
    return (
      revision: _cooking.contextRevisionFor(siteUrl),
      config: _presentation.configFor(siteUrl),
      presentation: _presentation.presentationTokenFor(siteUrl),
      staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
      user: (user?.id, user?.username, user?.timezone),
      readerTimezone: _timezones.readerTimezone(user?.timezone),
      users: _store.generationOf<UserCard>(siteUrl),
      topics: _store.generationOf<TopicDetail>(siteUrl),
    );
  }

  /// Original request identity is retained for host preflight decisions.
  bool isCurrent(CookingRequest request) =>
      !_disposed &&
      _cooking.isCurrent(request) &&
      _requestStamps[request] == _stamp(request.snapshot.siteId);

  VoidCallback watch({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  }) {
    if (_disposed) return () {};
    final topicIds = raw.length <= 65536
        ? _topicIds(raw).toList(growable: false)
        : const <int>[];
    final usernames = raw.length <= 65536
        ? _usernames(raw).toList(growable: false)
        : const <String>[];
    final watch = _CookingWatch(
      siteUrl: siteUrl,
      read: () => _stamp(siteUrl),
      readReferences: () sync* {
        for (final id in topicIds) {
          yield _store.ref<TopicDetail>(siteUrl, id);
        }
        for (final name in usernames) {
          yield _store.ref<UserCard>(siteUrl, name.toLowerCase());
        }
      },
      onChanged: onChanged,
    );
    _watches.add(watch);
    watch.listen(_presentation);
    watch.listen(_timezones);
    watch.onRetire(_cooking.watchContext(siteUrl, watch.changed));
    watch.rebindReferences();
    return () {
      watch.retire();
      _watches.remove(watch);
    };
  }

  CookingRequest request({
    required String siteUrl,
    required String raw,
    CookingProfile profile = CookingProfile.post,
    CookingContext context = const CookingContext(),
    CookingCachedMetadata? cachedMetadata,
  }) {
    CookingRequest track(CookingRequest request) {
      _requestStamps[request] = _stamp(siteUrl);
      return request;
    }

    if (raw.length > 65536) {
      return track(
        _cooking.request(
          siteUrl: siteUrl,
          accountId: _currentUserFor(siteUrl)?.id.toString() ?? 'anonymous',
          raw: raw,
          profile: profile,
          config: const SiteConfig.unknown(),
        ),
      );
    }
    final identities = _identitiesFor(siteUrl);
    return track(
      _cooking.request(
        siteUrl: siteUrl,
        accountId: _currentUserFor(siteUrl)?.id.toString() ?? 'anonymous',
        raw: raw,
        profile: profile,
        context: context,
        cachedMetadata: cachedMetadata ?? _cachedMetadata(siteUrl, raw),
        config: _presentation.configFor(siteUrl),
        staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
        mentions: identities.mentions,
        hashtags: identities.hashtags,
        customEmoji: _presentation.cachedCustomEmojiFor(siteUrl),
      ),
    );
  }

  static Iterable<int> _topicIds(String raw) => RegExp(r'topic:(\d+)')
      .allMatches(raw)
      .take(128)
      .map((match) => int.tryParse(match[1]!))
      .whereType<int>()
      .toSet();

  static Set<String> _usernames(String raw) => {
    for (final match in RegExp(
      r'(?:@|quote="|\[quote=")([\w.-]+)',
    ).allMatches(raw).take(128))
      match[1]!,
  };

  CookingCachedMetadata _cachedMetadata(String siteUrl, String raw) {
    final topics = <String, CookingTopic>{};
    for (final id in _topicIds(raw)) {
      final topic = _store.read<TopicDetail>(siteUrl, id);
      if (topic != null) {
        topics['${topic.id}'] = CookingTopic(
          title: topic.title,
          href: '$siteUrl/t/${topic.id}',
        );
      }
    }
    final names = _usernames(raw);
    final mentions = <String, CookingMention>{};
    final avatars = <String, String>{};
    for (final name in names) {
      final card = _store.read<UserCard>(siteUrl, name.toLowerCase());
      if (card == null) continue;
      mentions[name] = CookingMention(
        username: card.username,
        href:
            '${Uri.parse(siteUrl).path.replaceFirst(RegExp(r'/+$'), '')}/u/${Uri.encodeComponent(card.username)}',
        kind: CookingMentionKind.user,
      );
      if (card.avatarUrl case final String url) {
        avatars[name] =
            '<img class="avatar" src="${const HtmlEscape().convert(url)}">';
      }
    }
    return CookingCachedMetadata(
      topics: topics,
      mentions: mentions,
      avatars: avatars,
    );
  }

  void rebindStoreReferences(String siteUrl) {
    for (final watch in _watches) {
      if (watch.siteUrl == siteUrl) watch.rebindReferences();
    }
  }

  void dispose() {
    _disposed = true;
    for (final watch in _watches) {
      watch.retire();
    }
    _watches.clear();
  }
}

typedef _CookingSourceStamp = ({
  int revision,
  SiteConfig config,
  Object presentation,
  bool staleSettings,
  (int?, String?, String?) user,
  String readerTimezone,
  int users,
  int topics,
});

final class _CookingWatch {
  _CookingWatch({
    required this.siteUrl,
    required this.read,
    required this.readReferences,
    required this.onChanged,
  }) : _stamp = read();

  final String siteUrl;
  final _CookingSourceStamp Function() read;
  final Iterable<Listenable> Function() readReferences;
  final VoidCallback onChanged;
  final List<VoidCallback> _retire = [];
  final List<Listenable> _references = [];
  _CookingSourceStamp _stamp;
  bool _active = true;
  bool _pending = false;

  void listen(Listenable source) {
    source.addListener(changed);
    onRetire(() => source.removeListener(changed));
  }

  void onRetire(VoidCallback callback) => _retire.add(callback);

  void rebindReferences() {
    if (!_active) return;
    _releaseReferences();
    for (final reference in readReferences()) {
      reference.addListener(changed);
      _references.add(reference);
    }
  }

  void _releaseReferences() {
    for (final reference in _references) {
      reference.removeListener(changed);
    }
    _references.clear();
  }

  void changed() {
    if (!_active) return;
    final next = read();
    if (next == _stamp) return;
    _stamp = next;
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_active) onChanged();
    });
  }

  void retire() {
    if (!_active) return;
    _active = false;
    _releaseReferences();
    for (final callback in _retire) {
      callback();
    }
    _retire.clear();
  }
}
