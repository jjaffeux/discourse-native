import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/contracts.dart';
import 'package:flutter/foundation.dart'
    show Listenable, VoidCallback, listEquals;

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
  final _requestSources =
      Expando<({_CookingReferences references, _CookingSourceStamp stamp})>();
  final Set<_CookingWatch> _watches = {};
  bool _disposed = false;

  _CookingSourceStamp _stamp(String siteUrl, _CookingReferences references) {
    final user = _currentUserFor(siteUrl);
    return (
      revision: _cooking.contextRevisionFor(siteUrl),
      config: _presentation.configFor(siteUrl),
      presentation: _presentation.presentationTokenFor(siteUrl),
      staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
      user: (user?.id, user?.username, user?.timezone),
      readerTimezone: _timezones.readerTimezone(user?.timezone),
      entities: references.snapshot(_store, siteUrl),
    );
  }

  /// Original request identity is retained for host preflight decisions.
  bool isCurrent(CookingRequest request) {
    final source = _requestSources[request];
    return !_disposed &&
        _cooking.isCurrent(request) &&
        source != null &&
        source.stamp == _stamp(request.snapshot.siteId, source.references);
  }

  VoidCallback watch({
    required String siteUrl,
    required String raw,
    required VoidCallback onChanged,
  }) {
    if (_disposed) return () {};
    final references = _CookingReferences(raw);
    final watch = _CookingWatch(
      siteUrl: siteUrl,
      read: () => _stamp(siteUrl, references),
      readReferences: () sync* {
        for (final id in references.topics) {
          yield _store.ref<TopicDetail>(siteUrl, id);
        }
        for (final name in references.users) {
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
    final references = _CookingReferences(raw);
    CookingRequest track(CookingRequest request) {
      _requestSources[request] = (
        references: references,
        stamp: _stamp(siteUrl, references),
      );
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
        cachedMetadata: cachedMetadata ?? _cachedMetadata(siteUrl, references),
        config: _presentation.configFor(siteUrl),
        staleSettings: _presentation.cookingSettingsAreStale(siteUrl),
        mentions: identities.mentions,
        hashtags: identities.hashtags,
        customEmoji: _presentation.cachedCustomEmojiFor(siteUrl),
      ),
    );
  }

  CookingCachedMetadata _cachedMetadata(
    String siteUrl,
    _CookingReferences references,
  ) {
    final topics = <String, CookingTopic>{};
    for (final id in references.topics) {
      final topic = _store.read<TopicDetail>(siteUrl, id);
      if (topic != null) {
        topics['${topic.id}'] = CookingTopic(
          title: topic.title,
          href: '$siteUrl/t/${topic.id}',
        );
      }
    }
    final mentions = <String, CookingMention>{};
    final avatars = <String, String>{};
    for (final name in references.users) {
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
  _CookingEntityStamp entities,
});

/// The bounded source references shared by snapshot assembly and freshness.
final class _CookingReferences {
  _CookingReferences(String raw)
    : topics = raw.length <= 65536
          ? _topicIds(raw).toList(growable: false)
          : const [],
      users = raw.length <= 65536
          ? _usernames(raw).toList(growable: false)
          : const [];

  final List<int> topics;
  final List<String> users;

  _CookingEntityStamp snapshot(Store store, String siteUrl) =>
      _CookingEntityStamp(
        [
          for (final id in topics)
            (id, store.read<TopicDetail>(siteUrl, id)?.title),
        ],
        [for (final name in users) _userStamp(store, siteUrl, name)],
      );

  static (String, String?, String?) _userStamp(
    Store store,
    String siteUrl,
    String name,
  ) {
    final card = store.read<UserCard>(siteUrl, name.toLowerCase());
    return (name, card?.username, card?.avatarUrl);
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
}

final class _CookingEntityStamp {
  const _CookingEntityStamp(this.topics, this.users);

  final List<(int, String?)> topics;
  final List<(String, String?, String?)> users;

  @override
  bool operator ==(Object other) =>
      other is _CookingEntityStamp &&
      listEquals(topics, other.topics) &&
      listEquals(users, other.users);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(topics), Object.hashAll(users));
}

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
