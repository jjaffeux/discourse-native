// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../data/discourse_api_contracts.dart';
import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/post.dart';
import '../../models/site_config.dart';
import '../../models/site_emoji.dart';
import '../../plugin_api/core_plugin_host.dart';
import 'post_reactors.dart';
import 'reaction.dart';
import 'reactions_api.dart';
import 'reactions_settings.dart';

typedef _ReactionRequestKey = ({String siteUrl, int postId, String? filter});

/// An opaque interaction generation retained by an open reaction picker.
///
/// Widgets can ask [ReactionsController] whether it is still current, but they
/// never receive the host's lifecycle authority.
final class ReactionPickerSession {
  const ReactionPickerSession._({
    required this.siteUrl,
    required this.postId,
    required this.storeBacked,
    required this._owner,
    required this._lease,
  });

  final String siteUrl;
  final int postId;
  final bool storeBacked;
  final ReactionsController _owner;
  final PluginSiteLease _lease;
}

/// Reactions-owned cache, picker state, and post interaction workflows.
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
    this.diagnostics = const PluginDiagnosticsReporter.noop(),
  }) : _api = api,
       _writes =
           writes ??
           (api is ReactionsWriteApi ? api as ReactionsWriteApi : null),
       _requestHost = requests,
       _posts = posts,
       _siteState = siteState,
       _resolveSiteConfig = resolveSiteConfig,
       _emoji = emoji,
       _cache = cache ?? Store();

  final ReactionsApi _api;
  final ReactionsWriteApi? _writes;
  final PluginRequestHost _requestHost;
  final PluginPostHost _posts;
  final PluginSiteStateHost _siteState;
  final PluginSiteConfigResolver _resolveSiteConfig;
  final PluginEmojiHost _emoji;
  final Store _cache;
  final PluginDiagnosticsReporter diagnostics;

  final Map<_ReactionRequestKey, Object> _requests = {};
  final Map<_ReactionRequestKey, String> _errors = {};
  final Map<String, SiteEmojiCatalog> _emojiCatalogs = {};
  final Map<String, Object> _emojiCatalogRequests = {};

  static _ReactionRequestKey _key(String siteUrl, int postId, String? filter) =>
      (siteUrl: siteUrl, postId: postId, filter: filter);

  PostReactors? reactors(String siteUrl, int postId, {String? filter}) =>
      _cache.read<PostReactors>(siteUrl, PostReactors.key(postId, filter));

  String? error(String siteUrl, int postId, {String? filter}) =>
      _errors[_key(siteUrl, postId, filter)];

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

  Future<void> _loadEmojiCatalog(String siteUrl) async {
    if (isDisposed || _emojiCatalogRequests.containsKey(siteUrl)) return;
    final request = Object();
    final lease = _requestHost.capture(siteUrl);
    _emojiCatalogRequests[siteUrl] = request;
    try {
      final catalog = await _emoji.loadCatalog(siteUrl, refresh: false);
      if (!_ownsCatalogRequest(siteUrl, request) || !lease.isCurrent) return;
      if (catalog != null) {
        lease.commit(() => _emojiCatalogs[siteUrl] = catalog);
      }
    } catch (error, stackTrace) {
      if (lease.isCurrent && _ownsCatalogRequest(siteUrl, request)) {
        _report(error, stackTrace, 'reactions.loadEmojiCatalog');
      }
    } finally {
      if (_ownsCatalogRequest(siteUrl, request)) {
        _emojiCatalogRequests.remove(siteUrl);
        notifySafely();
      }
    }
  }

  bool _ownsCatalogRequest(String siteUrl, Object request) =>
      !isDisposed && identical(_emojiCatalogRequests[siteUrl], request);

  ReactionPickerSession beginPicker(String siteUrl, Post post) =>
      ReactionPickerSession._(
        siteUrl: siteUrl,
        postId: post.id,
        storeBacked: _posts.readPost(siteUrl, post.id) != null,
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
    return latest ?? (session.storeBacked ? null : fallback);
  }

  Future<String?> toggleFromPicker(
    ReactionPickerSession session,
    Post fallback,
    String reaction,
  ) {
    final latest = pickerPost(session, fallback);
    if (latest == null || !latest.canReact) return Future.value(null);
    return toggle(latest, reaction, siteUrl: session.siteUrl);
  }

  /// Fetches who reacted to a post, or who gave it one particular emoji.
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
    notifySafely();

    try {
      final credentials = await _requestHost.credentialsFor(siteUrl);
      if (!_canSend(lease, key, request)) return;
      final fetched = await _api.postReactors(
        siteUrl: siteUrl,
        postId: postId,
        reaction: filter,
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
      if (!_canSend(lease, key, request)) return;
      lease.commit(() {
        _cache.put(siteUrl, fetched);
        _errors.remove(key);
      });
    } catch (error, stackTrace) {
      if (!_canSend(lease, key, request)) return;
      diagnostics.reportError(
        error,
        stackTrace,
        operation: 'reactions.loadUsers',
        source: 'reactions',
        handled: true,
        degraded: true,
      );
      lease.commit(() {
        if (reactors(siteUrl, postId, filter: filter) == null) {
          _errors[key] = 'Could not find out who reacted.';
        }
      });
    } finally {
      if (_isCurrentRequest(key, request)) {
        _requests.remove(key);
        notifySafely();
      }
    }
  }

  /// Optimistically toggles one reaction through the plugin-owned endpoint.
  Future<String?> toggle(
    Post post,
    String reaction, {
    required String siteUrl,
  }) async {
    if (isDisposed || !post.canReact) return null;
    if (!_posts.beginWrite(siteUrl, post.id)) return null;
    notifySafely();
    final lease = _requestHost.capture(siteUrl);

    try {
      final credential = await _requestHost.writeCredentialFor(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final apiKey = credential.apiKey!;
      final current = _posts.readPost(siteUrl, post.id) ?? post;
      if (!current.canReact) return null;
      final held = current.reactions;
      if (held == null) return null;

      final applied = lease.commit(() {
        _posts.updatePluginRecord(
          siteUrl,
          post.id,
          reactionsDataKey,
          (stored) => stored
              ?.withToggled(reaction)
              .withMainReaction(
                siteConfigFor(siteUrl).reactionsSettings.mainReaction,
              ),
        );
      });
      if (!applied) return null;

      void revert() {
        lease.commit(() {
          _posts.updatePluginRecord(
            siteUrl,
            post.id,
            reactionsDataKey,
            (_) => held,
          );
        });
      }

      try {
        final api = _writes;
        if (api == null) {
          throw StateError('Reactions write API is unavailable.');
        }
        final fresh = await api.toggleReaction(
          siteUrl: siteUrl,
          apiKey: apiKey,
          postId: post.id,
          reaction: reaction,
        );
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
      } on WriteException catch (error) {
        if (error.statusCode == 404) {
          lease.commit(() {
            _posts.updatePluginRecord(
              siteUrl,
              post.id,
              reactionsDataKey,
              (_) => null,
            );
          });
          return null;
        }
        revert();
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _report(error, stackTrace, 'post.toggleReaction');
        }
        revert();
        return const WriteException(WriteFailure.unreachable).message;
      }
      return null;
    } finally {
      lease.commit(() => _posts.endWrite(siteUrl, post.id));
      notifySafely();
    }
  }

  void forget(String siteUrl) {
    _emojiCatalogs.remove(siteUrl);
    _emojiCatalogRequests.remove(siteUrl);
    _requests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _errors.removeWhere((key, _) => key.siteUrl == siteUrl);
    _cache.forget(siteUrl);
    notifySafely();
  }

  bool _canSend(
    PluginSiteLease lease,
    _ReactionRequestKey key,
    Object request,
  ) => lease.isCurrent && _isCurrentRequest(key, request);

  bool _isCurrentRequest(_ReactionRequestKey key, Object request) =>
      !isDisposed && identical(_requests[key], request);

  void _report(Object error, StackTrace stackTrace, String operation) {
    diagnostics.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'reactions',
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    _requests.clear();
    _errors.clear();
    _emojiCatalogs.clear();
    _emojiCatalogRequests.clear();
    super.dispose();
  }
}
