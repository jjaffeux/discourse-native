// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'policies_api.dart';
import 'policy_data.dart';

enum PolicyWritePhase { idle, sending, refreshing, uncertain }

enum PolicyMutationKind { confirmed, busy, inactive, refused, uncertain }

@immutable
final class PolicyInteractionState {
  const PolicyInteractionState({
    this.phase = PolicyWritePhase.idle,
    this.error,
  });
  final PolicyWritePhase phase;
  final Object? error;
  bool get pending =>
      phase == PolicyWritePhase.sending || phase == PolicyWritePhase.refreshing;
}

typedef _PolicyTarget = ({String siteUrl, int postId});

class PolicyController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  PolicyController({
    required PoliciesApi api,
    required PluginRequestHost requests,
    required PluginPostHost posts,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    required PluginAccountConnectionHost accounts,
  }) : _api = api,
       _requests = requests,
       _posts = posts,
       _siteState = siteState,
       _freshAccount = freshAccount,
       _accounts = accounts;

  final PoliciesApi _api;
  final PluginRequestHost _requests;
  final PluginPostHost _posts;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final PluginAccountConnectionHost _accounts;
  final _interactions = <_PolicyTarget, PolicyInteractionState>{};
  final _retained = <_PolicyTarget, Map<PluginSiteLease, int>>{};
  final _epochs = <String, int>{};
  final _writeOwners = <_PolicyTarget, PluginSiteLease>{};

  PluginSiteLease captureSiteSession(String siteUrl) =>
      _requests.capture(siteUrl);
  Post? readPost(String siteUrl, int postId) =>
      _posts.readPost(siteUrl, postId);
  bool enabled(String siteUrl) {
    final config = _siteState.siteConfigFor(siteUrl);
    return config.cookingSettingsStale ||
        config.plugins.policySettings?.enabled != false;
  }

  bool isConnected(String siteUrl) => _accounts.isConnected(siteUrl);
  Future<String?> connect(String siteUrl) => _accounts.connect(siteUrl);
  bool canCreate(String siteUrl) =>
      !_siteState.siteConfigFor(siteUrl).cookingSettingsStale &&
      _siteState.siteConfigFor(siteUrl).plugins.policySettings?.enabled ==
          true &&
      _freshAccount.recordFor(siteUrl, policyCurrentUserKey)?.canCreate == true;
  bool canManage(String siteUrl, Post post) {
    final user = _siteState.currentUserFor(siteUrl);
    return post.canEdit &&
        canCreate(siteUrl) &&
        user != null &&
        (user.staff || (user.id != null && user.id == post.userId));
  }

  PolicyInteractionState interaction(String siteUrl, int postId) =>
      _interactions[(siteUrl: siteUrl, postId: postId)] ??
      const PolicyInteractionState();

  bool _current(String siteUrl, PluginSiteLease lease, int epoch) =>
      !isDisposed && lease.isCurrent && (_epochs[siteUrl] ?? 0) == epoch;

  void _set(_PolicyTarget target, PolicyWritePhase phase, [Object? error]) {
    _interactions[target] = PolicyInteractionState(phase: phase, error: error);
    notifySafely();
  }

  Future<PolicyMutationKind> act({
    required String siteUrl,
    required int topicId,
    required int postId,
    required PolicyAction action,
    required PluginSiteLease lease,
  }) async {
    final epoch = _epochs[siteUrl] ?? 0;
    final target = (siteUrl: siteUrl, postId: postId);
    if (!_current(siteUrl, lease, epoch) || !enabled(siteUrl)) {
      return PolicyMutationKind.inactive;
    }
    final data = readPost(siteUrl, postId)?.plugins.policy;
    if (data == null ||
        !(action == PolicyAction.accept ? data.canAccept : data.canRevoke)) {
      return PolicyMutationKind.inactive;
    }
    final held = interaction(siteUrl, postId);
    if (held.pending ||
        held.phase == PolicyWritePhase.uncertain ||
        !_posts.beginWrite(siteUrl, postId)) {
      return PolicyMutationKind.busy;
    }
    if (!_current(siteUrl, lease, epoch)) {
      lease.commit(() => _posts.endWrite(siteUrl, postId));
      return PolicyMutationKind.inactive;
    }
    _writeOwners[target] = lease;
    var dispatched = false;
    _set(target, PolicyWritePhase.sending);
    try {
      if (!_current(siteUrl, lease, epoch)) return PolicyMutationKind.inactive;
      final credential = await _requests.writeCredentialFor(siteUrl);
      if (!_current(siteUrl, lease, epoch) || !enabled(siteUrl)) {
        return PolicyMutationKind.inactive;
      }
      if (credential.failure case final failure?) throw failure;
      final credentials = credential.credentials;
      if (credentials?.apiKey == null) {
        throw const WriteException(WriteFailure.forbidden, notSent: true);
      }
      final latest = readPost(siteUrl, postId)?.plugins.policy;
      if (latest == null ||
          !(action == PolicyAction.accept
              ? latest.canAccept
              : latest.canRevoke)) {
        return PolicyMutationKind.inactive;
      }
      await credentials!.run(() {
        if (!_current(siteUrl, lease, epoch)) {
          throw const WriteException(WriteFailure.forbidden, notSent: true);
        }
        dispatched = true;
        return _api.mutate(
          siteUrl: siteUrl,
          apiKey: credentials.apiKey!,
          clientId: credentials.clientId,
          postId: postId,
          action: action,
        );
      });
      if (!_current(siteUrl, lease, epoch)) return PolicyMutationKind.inactive;
      _set(target, PolicyWritePhase.refreshing);
      final refreshed = await _refresh(
        siteUrl,
        topicId,
        postId,
        credentials.apiKey,
        lease,
        epoch,
      );
      if (!_current(siteUrl, lease, epoch)) return PolicyMutationKind.inactive;
      if (!refreshed) {
        _set(target, PolicyWritePhase.uncertain);
        return PolicyMutationKind.uncertain;
      }
      _set(target, PolicyWritePhase.idle);
      return PolicyMutationKind.confirmed;
    } catch (error) {
      if (!_current(siteUrl, lease, epoch)) return PolicyMutationKind.inactive;
      final ambiguous =
          dispatched &&
          !(error is WriteException &&
              (error.notSent || error.failure != WriteFailure.unreachable));
      if (ambiguous) {
        _set(target, PolicyWritePhase.refreshing, error);
        try {
          final credentials = await _requests.credentialsFor(siteUrl);
          if (!_current(siteUrl, lease, epoch)) {
            return PolicyMutationKind.inactive;
          }
          final refreshed = await credentials.run(
            () => _refresh(
              siteUrl,
              topicId,
              postId,
              credentials.apiKey,
              lease,
              epoch,
            ),
          );
          if (!_current(siteUrl, lease, epoch)) {
            return PolicyMutationKind.inactive;
          }
          if (refreshed) {
            _set(target, PolicyWritePhase.idle);
            return PolicyMutationKind.confirmed;
          }
        } catch (_) {
          if (!_current(siteUrl, lease, epoch)) {
            return PolicyMutationKind.inactive;
          }
        }
        _set(target, PolicyWritePhase.uncertain, error);
        return PolicyMutationKind.uncertain;
      }
      _set(target, PolicyWritePhase.idle, error);
      return PolicyMutationKind.refused;
    } finally {
      if (identical(_writeOwners[target], lease)) {
        _writeOwners.remove(target);
        lease.commit(() => _posts.endWrite(siteUrl, postId));
      }
      if (_current(siteUrl, lease, epoch) &&
          interaction(siteUrl, postId).pending) {
        _set(target, PolicyWritePhase.idle);
      }
    }
  }

  Future<bool> _refresh(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    PluginSiteLease lease,
    int epoch,
  ) async {
    if (!_current(siteUrl, lease, epoch)) return false;
    final fresh = await _posts.refreshPost(
      siteUrl: siteUrl,
      topicId: topicId,
      postId: postId,
      apiKey: apiKey,
      lease: lease,
    );
    return _current(siteUrl, lease, epoch) && fresh;
  }

  Future<void> checkStatus({
    required String siteUrl,
    required int topicId,
    required int postId,
    required PluginSiteLease lease,
  }) async {
    final epoch = _epochs[siteUrl] ?? 0;
    final target = (siteUrl: siteUrl, postId: postId);
    if (!_current(siteUrl, lease, epoch) ||
        !enabled(siteUrl) ||
        interaction(siteUrl, postId).pending) {
      return;
    }
    _set(target, PolicyWritePhase.refreshing);
    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!_current(siteUrl, lease, epoch)) return;
      final fresh = await credentials.run(
        () => _refresh(
          siteUrl,
          topicId,
          postId,
          credentials.apiKey,
          lease,
          epoch,
        ),
      );
      if (_current(siteUrl, lease, epoch)) {
        _set(
          target,
          fresh ? PolicyWritePhase.idle : PolicyWritePhase.uncertain,
        );
      }
    } catch (error) {
      if (_current(siteUrl, lease, epoch)) {
        _set(target, PolicyWritePhase.uncertain, error);
      }
    }
  }

  Future<PolicyUsersPage?> participants({
    required String siteUrl,
    required int postId,
    required PolicyParticipantList list,
    required int offset,
    required PluginSiteLease lease,
  }) async {
    final epoch = _epochs[siteUrl] ?? 0;
    bool allowed() =>
        _current(siteUrl, lease, epoch) &&
        enabled(siteUrl) &&
        readPost(siteUrl, postId)?.plugins.policy?.statistics
            is PolicyStatisticsVisible;
    if (!allowed()) return null;
    final credentials = await _requests.credentialsFor(siteUrl);
    if (!allowed()) return null;
    if (credentials.apiKey == null) {
      throw const WriteException(WriteFailure.forbidden, notSent: true);
    }
    final page = await credentials.run(
      () => _api.participants(
        siteUrl: siteUrl,
        apiKey: credentials.apiKey!,
        clientId: credentials.clientId,
        postId: postId,
        list: list,
        offset: offset,
      ),
    );
    return allowed() ? page : null;
  }

  VoidCallback retain({
    required String siteUrl,
    required int topicId,
    required int postId,
  }) {
    final target = (siteUrl: siteUrl, postId: postId);
    final lease = _requests.capture(siteUrl);
    (_retained[target] ??= {})[lease] = topicId;
    return () {
      _retained[target]?.remove(lease);
      if (_retained[target]?.isEmpty == true) _retained.remove(target);
    };
  }

  void setForeground(bool foreground) {
    if (!foreground || isDisposed) return;
    for (final entry in _retained.entries.toList()) {
      final valid = entry.value.entries
          .where((e) => e.key.isCurrent)
          .firstOrNull;
      if (valid == null) continue;
      unawaited(
        checkStatus(
          siteUrl: entry.key.siteUrl,
          topicId: valid.value,
          postId: entry.key.postId,
          lease: valid.key,
        ),
      );
    }
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) => notifySafely();

  void forget(String siteUrl) {
    _epochs[siteUrl] = (_epochs[siteUrl] ?? 0) + 1;
    for (final target
        in _writeOwners.keys
            .where((target) => target.siteUrl == siteUrl)
            .toList()) {
      _writeOwners
          .remove(target)!
          .commit(() => _posts.endWrite(target.siteUrl, target.postId));
    }
    _interactions.removeWhere((target, _) => target.siteUrl == siteUrl);
    _retained.removeWhere((target, _) => target.siteUrl == siteUrl);
    notifySafely();
  }

  @override
  void dispose() {
    for (final entry in _writeOwners.entries.toList()) {
      entry.value.commit(
        () => _posts.endWrite(entry.key.siteUrl, entry.key.postId),
      );
    }
    _writeOwners.clear();
    _interactions.clear();
    _retained.clear();
    super.dispose();
  }
}
