// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'post_reactors.dart';
import 'reaction.dart';
import 'reaction_toggle_result.dart';
import 'reactions_api.dart';
import 'reactions_settings.dart';

typedef _ReactionRequestKey = ({String siteUrl, int postId, String? filter});
typedef _ReactionPostKey = ({String siteUrl, int postId});

const _reactorStorePolicy = StorePolicy(
  maxEntries: 512,
  maxEntriesPerSite: 256,
  maxEntriesPerSiteAndType: 256,
);

/// Exposes picker currency without leaking the host lifecycle lease.
final class ReactionPickerSession {
  const ReactionPickerSession._({
    required this.siteUrl,
    required this.postId,
    required this._owner,
    required this._lease,
  });

  final String siteUrl;
  final int postId;
  final ReactionsController _owner;
  final PluginSiteLease _lease;
}

class ReactionsController extends FrameSafeNotifier {
  ReactionsController({
    required ReactionsApi api,
    ReactionsWriteApi? writes,
    required PluginRequestHost requests,
    required PluginPostHost posts,
    required PluginSiteStateHost siteState,
    required PluginSiteConfigResolver resolveSiteConfig,
    required PluginEmojiHost emoji,
    Store? cache,
  }) : _api = api,
       _writes =
           writes ??
           (api is ReactionsWriteApi ? api as ReactionsWriteApi : null),
       _requestHost = requests,
       _posts = posts,
       _siteState = siteState,
       _resolveSiteConfig = resolveSiteConfig,
       _emoji = emoji,
       _cache = cache ?? Store(policy: _reactorStorePolicy);

  final ReactionsApi _api;
  final ReactionsWriteApi? _writes;
  final PluginRequestHost _requestHost;
  final PluginPostHost _posts;
  final PluginSiteStateHost _siteState;
  final PluginSiteConfigResolver _resolveSiteConfig;
  final PluginEmojiHost _emoji;
  final Store _cache;

  final Map<_ReactionRequestKey, Object> _requests = {};
  final Map<_ReactionRequestKey, String> _errors = {};
  final Map<String, SiteEmojiCatalog> _emojiCatalogs = {};
  final Map<String, Object> _emojiCatalogRequests = {};
  final _postChanges = _KeyedChanges<_ReactionPostKey>();
  final _catalogChanges = _KeyedChanges<String>();

  static _ReactionRequestKey _key(String siteUrl, int postId, String? filter) =>
      (siteUrl: siteUrl, postId: postId, filter: filter);

  PostReactors? reactors(String siteUrl, int postId, {String? filter}) =>
      _cache.read<PostReactors>(siteUrl, PostReactors.key(postId, filter));

  String? error(String siteUrl, int postId, {String? filter}) =>
      _errors[_key(siteUrl, postId, filter)];

  /// Notifies when this post's reactor lists load, when its reaction write
  /// starts or ends, and when its site is forgotten. A post's row, react
  /// button and reactor lists listen here rather than to the controller,
  /// which notifies for every post on screen.
  Listenable postChanges(String siteUrl, int postId) =>
      _postChanges.listenable((siteUrl: siteUrl, postId: postId));

  /// Notifies when what [emojiUrlFor] answers for this site may have moved:
  /// its catalog arrived or was forgotten.
  Listenable emojiCatalogChanges(String siteUrl) =>
      _catalogChanges.listenable(siteUrl);

  /// The controller itself still notifies, for consumers that follow every
  /// post: the summary sheet and the reaction grid.
  void _changed(String siteUrl, int postId) {
    _postChanges.changed((siteUrl: siteUrl, postId: postId));
    notifySafely();
  }

  SiteConfig siteConfigFor(String siteUrl) => _siteState.siteConfigFor(siteUrl);

  Future<bool> allowsAnyEmoji(String siteUrl) async =>
      (await _resolveSiteConfig(siteUrl))?.reactionsSettings.allowAnyEmoji ==
      true;

  Post? post(String siteUrl, int postId) => _posts.readPost(siteUrl, postId);

  bool writeInFlight(String siteUrl, int postId) =>
      _posts.writeInFlight(siteUrl, postId);

  String emojiUrlFor(String siteUrl, String name) {
    final catalog = _emojiCatalogs[siteUrl];
    if (catalog == null) unawaited(_loadEmojiCatalog(siteUrl));
    return catalog?.emojiNamed(name)?.url ??
        siteConfigFor(siteUrl).emojiUrl(name, siteUrl: siteUrl);
  }

  /// Started from [emojiUrlFor], which runs inside builders listening to this
  /// controller or to [emojiCatalogChanges], so only a stored catalog may
  /// notify: waking them after a miss would have them read again and start
  /// the next load, every frame.
  /// A miss is not remembered here; the host keeps a failed site's answer
  /// without traffic until a refresh, and asking again on a later read is
  /// what picks up the catalog that refresh finds.
  Future<void> _loadEmojiCatalog(String siteUrl) async {
    if (isDisposed || _emojiCatalogRequests.containsKey(siteUrl)) return;
    final request = Object();
    final lease = _requestHost.capture(siteUrl);
    _emojiCatalogRequests[siteUrl] = request;
    try {
      final catalog = await _emoji.loadCatalog(siteUrl, refresh: false);
      if (!_ownsCatalogRequest(siteUrl, request) || !lease.isCurrent) return;
      if (catalog != null &&
          lease.commit(() => _emojiCatalogs[siteUrl] = catalog)) {
        _catalogChanges.changed(siteUrl);
        notifySafely();
      }
    } catch (error) {
    } finally {
      if (_ownsCatalogRequest(siteUrl, request)) {
        _emojiCatalogRequests.remove(siteUrl);
      }
    }
  }

  bool _ownsCatalogRequest(String siteUrl, Object request) =>
      !isDisposed && identical(_emojiCatalogRequests[siteUrl], request);

  ReactionPickerSession beginPicker(String siteUrl, Post post) =>
      ReactionPickerSession._(
        siteUrl: siteUrl,
        postId: post.id,
        owner: this,
        lease: _requestHost.capture(siteUrl),
      );

  bool isPickerCurrent(ReactionPickerSession session) =>
      !isDisposed &&
      identical(session._owner, this) &&
      session._lease.isCurrent;

  Post? pickerPost(ReactionPickerSession session, Post fallback) {
    if (!isPickerCurrent(session)) return null;
    final latest = _posts.readPost(session.siteUrl, session.postId);
    return latest ?? fallback;
  }

  Future<ReactionToggleResult> toggleFromPicker(
    ReactionPickerSession session,
    Post fallback,
    String reaction,
  ) {
    final latest = pickerPost(session, fallback);
    if (latest == null) {
      return Future.value(const ReactionToggleResult.inactive());
    }
    if (!latest.canReact) {
      return Future.value(const ReactionToggleResult.unchanged());
    }
    return toggle(
      latest.reactions == null ? fallback : latest,
      reaction,
      siteUrl: session.siteUrl,
    );
  }

  Future<void> load({
    required String siteUrl,
    required int postId,
    String? filter,
  }) async {
    if (isDisposed) return;
    final key = _key(siteUrl, postId, filter);
    if (_requests.containsKey(key)) return;
    final request = Object();
    final lease = _requestHost.capture(siteUrl);
    _requests[key] = request;
    _changed(siteUrl, postId);

    try {
      final credentials = await _requestHost.credentialsFor(siteUrl);
      if (!_canSend(lease, key, request)) return;
      final fetched = await credentials.run(
        () => _api.postReactors(
          siteUrl: siteUrl,
          postId: postId,
          reaction: filter,
          apiKey: credentials.apiKey,
          clientId: credentials.clientId,
        ),
      );
      if (!_canSend(lease, key, request)) return;
      lease.commit(() {
        _cache.put(siteUrl, fetched);
        _errors.remove(key);
      });
    } catch (error) {
      if (!_canSend(lease, key, request)) return;

      lease.commit(() {
        if (reactors(siteUrl, postId, filter: filter) == null) {
          _errors[key] = appL10n.couldNotFindOutWhoReacted;
        }
      });
    } finally {
      if (_isCurrentRequest(key, request)) {
        _requests.remove(key);
        _changed(siteUrl, postId);
      }
    }
  }

  Future<ReactionToggleResult> toggle(
    Post post,
    String reaction, {
    required String siteUrl,
  }) async {
    if (isDisposed) return const ReactionToggleResult.inactive();
    if (!post.canReact) return const ReactionToggleResult.unchanged();
    final lease = _requestHost.capture(siteUrl);
    bool current() => !isDisposed && lease.isCurrent;
    if (!current()) return const ReactionToggleResult.inactive();
    if (!_posts.beginWrite(siteUrl, post.id)) {
      return const ReactionToggleResult.busy();
    }
    _changed(siteUrl, post.id);

    try {
      PluginWriteCredential credential;
      try {
        credential = await _requestHost.writeCredentialFor(siteUrl);
      } on WriteException catch (error) {
        return ReactionToggleResult.notSent(error, isCurrent: current());
      } catch (error, stackTrace) {
        return ReactionToggleResult.notSent(
          WriteException(
            WriteFailure.unreachable,
            notSent: true,
            cause: error,
            causeStackTrace: stackTrace,
          ),
          isCurrent: current(),
        );
      }
      if (!current()) return const ReactionToggleResult.inactive();
      if (credential.failure case final failure?) {
        return failure.failure == WriteFailure.unreachable || failure.notSent
            ? ReactionToggleResult.notSent(failure, isCurrent: true)
            : ReactionToggleResult.refused(failure, isCurrent: true);
      }
      final apiKey = credential.credentials!.apiKey!;
      final latest = _posts.readPost(siteUrl, post.id) ?? post;
      if (!latest.canReact) return const ReactionToggleResult.unchanged();
      // Permission comes from the current post; an open picker retains the
      // plugin snapshot needed to apply or roll back after its pill vanishes.
      final held = latest.reactions ?? post.reactions;
      if (held == null) return const ReactionToggleResult.unchanged();

      final applied = lease.commit(() {
        _posts.updatePluginRecord(
          siteUrl,
          post.id,
          reactionsDataKey,
          (stored) => (stored ?? held)
              .withToggled(reaction)
              .withMainReaction(
                siteConfigFor(siteUrl).reactionsSettings.mainReaction,
              ),
        );
      });
      if (!applied || !current()) {
        return const ReactionToggleResult.inactive();
      }

      void revert() {
        if (!current()) return;
        lease.commit(() {
          _posts.updatePluginRecord(
            siteUrl,
            post.id,
            reactionsDataKey,
            (_) => held,
          );
        });
      }

      var dispatched = false;
      Post? fresh;
      try {
        final api = _writes;
        if (api == null) {
          throw StateError('Reactions write API is unavailable.');
        }
        fresh = await credential.credentials!.run(() {
          dispatched = true;
          return api.toggleReaction(
            siteUrl: siteUrl,
            apiKey: apiKey,
            postId: post.id,
            reaction: reaction,
          );
        });
      } on WriteException catch (error) {
        if (!dispatched || error.notSent) {
          revert();
          return ReactionToggleResult.notSent(error, isCurrent: current());
        }
        if (error.statusCode == 404) {
          if (current()) {
            lease.commit(() {
              _posts.updatePluginRecord(
                siteUrl,
                post.id,
                reactionsDataKey,
                (_) => null,
              );
            });
          }
          return ReactionToggleResult.unavailable(error, isCurrent: current());
        }
        revert();
        return error.failure == WriteFailure.unreachable
            ? ReactionToggleResult.uncertain(error, isCurrent: current())
            : ReactionToggleResult.refused(error, isCurrent: current());
      } catch (error, stackTrace) {
        revert();
        final failure = WriteException(
          WriteFailure.unreachable,
          notSent: !dispatched,
          cause: error,
          causeStackTrace: stackTrace,
        );
        return dispatched
            ? ReactionToggleResult.uncertain(failure, isCurrent: current())
            : ReactionToggleResult.notSent(failure, isCurrent: current());
      }
      if (!current()) return const ReactionToggleResult.acceptedRetired();
      if (fresh?.reactions case final answered?) {
        lease.commit(() {
          _posts.updatePluginRecord(
            siteUrl,
            post.id,
            reactionsDataKey,
            (stored) => stored?.withMineOf(answered),
          );
        });
      }
      return current()
          ? const ReactionToggleResult.applied()
          : const ReactionToggleResult.acceptedRetired();
    } finally {
      lease.commit(() => _posts.endWrite(siteUrl, post.id));
      _changed(siteUrl, post.id);
    }
  }

  void forget(String siteUrl) {
    _emojiCatalogs.remove(siteUrl);
    _emojiCatalogRequests.remove(siteUrl);
    _requests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _errors.removeWhere((key, _) => key.siteUrl == siteUrl);
    _cache.forget(siteUrl);
    // Retained rows keep listening to the same notifiers, so the next load or
    // write for their post still reaches them.
    _postChanges.changedWhere((key) => key.siteUrl == siteUrl);
    _catalogChanges.changed(siteUrl);
    notifySafely();
  }

  bool _canSend(
    PluginSiteLease lease,
    _ReactionRequestKey key,
    Object request,
  ) => lease.isCurrent && _isCurrentRequest(key, request);

  bool _isCurrentRequest(_ReactionRequestKey key, Object request) =>
      !isDisposed && identical(_requests[key], request);

  @override
  void dispose() {
    _requests.clear();
    _errors.clear();
    _emojiCatalogs.clear();
    _emojiCatalogRequests.clear();
    _postChanges.dispose();
    _catalogChanges.dispose();
    super.dispose();
  }
}

/// Notifiers answered by key: the same instance for as long as anything
/// listens to it, so a rebuild does not resubscribe, and dropped once nothing
/// does, so the posts of a topic scrolled past leave none behind.
final class _KeyedChanges<K> {
  final Map<K, _Changes> _held = {};

  Listenable listenable(K key) => _held[key] ??= _Changes(
    onUnused: (changes) {
      if (identical(_held[key], changes)) _held.remove(key);
      changes.dispose();
    },
  );

  void changed(K key) => _held[key]?.changed();

  void changedWhere(bool Function(K key) test) {
    for (final MapEntry(:key, :value) in _held.entries.toList()) {
      if (test(key)) value.changed();
    }
  }

  void dispose() {
    for (final changes in _held.values) {
      changes.dispose();
    }
    _held.clear();
  }
}

/// FrameSafe for the same reason the controller is: a load can start from a
/// build, and a notification there must wait for the frame.
final class _Changes extends FrameSafeNotifier {
  _Changes({required void Function(_Changes changes) onUnused})
    : _onUnused = onUnused {
    _checkUse();
  }

  final void Function(_Changes changes) _onUnused;
  bool _checking = false;

  void changed() => notifySafely();

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _checkUse();
  }

  /// Deferred rather than immediate: a builder that swaps listenables removes
  /// its listener before adding the next, and a merged or rebuilt listener
  /// may re-add this same instance in that gap. A listener may also leave
  /// from inside a notification, when disposing is not allowed.
  void _checkUse() {
    if (_checking || isDisposed) return;
    _checking = true;
    scheduleMicrotask(() {
      _checking = false;
      if (!isDisposed && !hasListeners) _onUnused(this);
    });
  }
}
