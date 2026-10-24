import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/post.dart';
import '../models/post_checklist.dart';
import 'post_checklist_write.dart';
import 'topic_data_owner.dart';

final class ChecklistTransactions {
  ChecklistTransactions({
    required this.api,
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.isConnected,
    required this.topicData,
    required this.bookmarkWriting,
  });

  final PostMutationsApi api;
  final Store store;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final bool Function(String) isConnected;
  final TopicDataSession? Function(String, SiteLease) topicData;
  final bool Function(String, SiteLease, int) bookmarkWriting;

  final Map<String, _ChecklistAccount> _accounts = {};
  int _mutationSequence = 0;
  bool _disposed = false;

  bool isWriting(String siteUrl, int postId) {
    final account = _accounts[siteUrl];
    return account != null &&
        account.isCurrent &&
        account._writes[postId]?.isCurrent() == true;
  }

  _ChecklistAccount? _forSite(String siteUrl) {
    if (_disposed) return null;
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?._retire();
    final lease = lifecycle.capture(siteUrl);
    final data = topicData(siteUrl, lease);
    if (data == null) return null;
    final account = _ChecklistAccount(this, siteUrl, lease, data);
    _accounts[siteUrl] = account;
    account._detach = lease.onRetire(() {
      account._retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  Future<String?> toggle({
    required String siteUrl,
    required int topicId,
    required Post post,
    required PostChecklistTarget target,
    required bool checked,
  }) async {
    final held = store.read<Post>(siteUrl, post.id);
    if (!isConnected(siteUrl) ||
        held?.canEdit != true ||
        held!.isLocalized ||
        held.isDeleted ||
        topicId <= 0) {
      return null;
    }
    return _forSite(siteUrl)?.toggle(
      topicId: topicId,
      post: post,
      held: held,
      target: target,
      checked: checked,
    );
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?._retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account._retire();
    }
    _accounts.clear();
  }
}

final class _ChecklistAccount {
  _ChecklistAccount(this._owner, this.siteUrl, this.lease, this._data);

  final ChecklistTransactions _owner;
  final String siteUrl;
  final SiteLease lease;
  final TopicDataSession _data;
  final Map<int, PostChecklistWrite> _writes = {};
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent => !_retired && !_owner._disposed && lease.isCurrent;

  void _retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    _writes.clear();
  }

  Future<String?> toggle({
    required int topicId,
    required Post post,
    required Post held,
    required PostChecklistTarget target,
    required bool checked,
  }) async {
    final active = _writes[post.id];
    if (active != null && active.isCurrent()) {
      active.toggle(post, target, checked);
      return null;
    }
    if (_data.postWriting(post.id) &&
        !_owner.bookmarkWriting(siteUrl, lease, post.id)) {
      return appL10n.anotherPostActionIsStillFinishing;
    }
    if (!isCurrent) return null;
    String? apiKey;
    AccountRequestCredentials? requestCredential;
    late final PostChecklistWrite operation;
    operation = PostChecklistWrite(
      post: held,
      isCurrent: () => isCurrent && identical(_writes[post.id], operation),
      publish: _data.publishChecklist,
      load: () async {
        final fresh = await _data.checklistPost(topicId, post.id, apiKey);
        if (fresh == null || fresh.raw == null || fresh.updatedAt == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
        return fresh;
      },
      save: (baseline, toggles) => requestCredential!.run(
        () => _owner.api.togglePostChecklist(
          siteUrl: siteUrl,
          apiKey: apiKey!,
          postId: post.id,
          toggles: toggles,
          expectedRaw: baseline.raw!,
          expectedUpdatedAt: baseline.updatedAt!,
          mutationId:
              'native-${DateTime.now().microsecondsSinceEpoch}-${_owner._mutationSequence++}',
        ),
      ),
    );
    _writes[post.id] = operation;
    final releasePost = _data.holdPostWrite(post.id);
    try {
      if (!operation.toggle(post, target, checked)) return null;
      if (!isCurrent) return null;
      AccountRequestCredentials credential;
      try {
        credential = await AccountRequestSession(
          siteUrl,
          lease,
        ).keyCredentials(_owner.credentials);
      } catch (_) {
        if (!isCurrent) return null;
        operation.reject();
        return const WriteException(WriteFailure.unreachable).message;
      }
      if (!isCurrent) return null;
      if (credential.apiKey == null) {
        operation.reject();
        return const WriteException(WriteFailure.forbidden).message;
      }
      apiKey = credential.apiKey!;
      requestCredential = credential;
      return await operation.run();
    } finally {
      if (identical(_writes[post.id], operation)) {
        _writes.remove(post.id);
      }
      lease.commit(releasePost);
    }
  }
}
