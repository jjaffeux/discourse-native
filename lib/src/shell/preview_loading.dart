part of 'preview_requests.dart';

final class PreviewLoadingOwner {
  PreviewLoadingOwner({
    required this._site,
    required this._topicContent,
    required this._credentials,
    required this._lifecycle,
    required this._store,
    this.userStatuses,
    this.onStatusAccepted,
  });

  final ShellSiteApi _site;
  final TopicContentApi _topicContent;
  final SiteApiKeyReader _credentials;
  final SiteLifecycle _lifecycle;
  final Store _store;
  final UserStatusOverrides? userStatuses;
  final void Function(String siteUrl, int userId, UserStatus? status)?
  onStatusAccepted;
  final PreviewRequests<String> userCardRequests = PreviewRequests();
  final PreviewRequests<int> likerRequests = PreviewRequests();
  final Map<String, _PreviewAccount> _accounts = {};
  bool _disposed = false;

  _PreviewAccount? _account(String siteUrl) {
    if (_disposed) return null;
    final lease = _lifecycle.capture(siteUrl);
    final account = _accounts[siteUrl];
    if (account != null) {
      if (identical(account.lease.session, lease.session)) return account;
      _retire(account);
    }
    if (_disposed || !lease.isCurrent) return null;
    final successor = _accounts[siteUrl];
    if (successor != null) return successor;
    final created = _PreviewAccount(siteUrl, lease);
    _accounts[siteUrl] = created;
    created.detach = lease.onRetire(() => _retire(created));
    return created;
  }

  bool _owns(_PreviewAccount account) =>
      !_disposed &&
      account.lease.isCurrent &&
      identical(_accounts[account.siteUrl], account);

  bool _ownsCard(_PreviewAccount account, String key, Object request) =>
      _owns(account) && identical(account.cards[key], request);

  bool _ownsLikers(_PreviewAccount account, int postId, Object request) =>
      _owns(account) && identical(account.likers[postId], request);

  Future<void> loadLikers(DiscourseInstance instance, int postId) async {
    if (_disposed) return;
    final targetSite = instance.url;
    final account = _account(targetSite);
    if (account == null || account.likers.containsKey(postId)) return;
    final request = Object();
    account.likers[postId] = request;
    if (!likerRequests.begin(targetSite, postId)) {
      account.likers.remove(postId);
      return;
    }
    String? failure;
    try {
      if (!_ownsLikers(account, postId, request)) return;
      final credential = await AccountRequestSession(
        targetSite,
        account.lease,
      ).keyCredentials(_credentials);
      if (!_ownsLikers(account, postId, request)) return;
      final fetched = await credential.run(
        () => _topicContent.postLikers(
          siteUrl: targetSite,
          postId: postId,
          apiKey: credential.apiKey,
        ),
      );
      if (!_ownsLikers(account, postId, request)) return;
      _store.put(targetSite, fetched);
    } on SiteLookupException catch (e) {
      if (!_ownsLikers(account, postId, request)) return;
      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeWhoLikedThis
          : appL10n.couldnTReach(instance.host);
    } catch (_) {
      if (!_ownsLikers(account, postId, request)) return;
      failure = appL10n.couldnTLoadWhoLikedThis;
    } finally {
      if (_ownsLikers(account, postId, request)) {
        account.likers.remove(postId);
        likerRequests.finish(targetSite, postId, error: failure);
      }
    }
  }

  Future<void> loadUserCard(
    DiscourseInstance instance,
    String username, {
    bool force = false,
  }) async {
    if (_disposed || username.isEmpty) return;
    final targetSite = instance.url;
    final account = _account(targetSite);
    final key = username.toLowerCase();
    if (account == null || account.cards.containsKey(key)) return;
    if (!force) {
      if (userCardRequests.errorFor(targetSite, key) != null) return;
      if (_store.read<UserCard>(targetSite, key) != null) return;
    }
    final request = Object();
    account.cards[key] = request;
    if (!userCardRequests.begin(targetSite, key)) {
      account.cards.remove(key);
      return;
    }
    String? failure;
    try {
      if (!_ownsCard(account, key, request)) return;
      final credential = await AccountRequestSession(
        targetSite,
        account.lease,
      ).keyCredentials(_credentials);
      if (!_ownsCard(account, key, request)) return;
      final statusTicket = userStatuses?.beginSnapshot(targetSite);
      final card = await credential.run(
        () => _site.userCard(
          siteUrl: targetSite,
          username: username,
          apiKey: credential.apiKey,
        ),
      );
      if (!_ownsCard(account, key, request)) return;
      final userId = card.id;
      final status = userId != null && statusTicket != null
          ? userStatuses!.acceptSnapshot(
              targetSite,
              statusTicket,
              userId,
              card.status,
              onAccepted: (status) {
                if (_ownsCard(account, key, request)) {
                  onStatusAccepted?.call(targetSite, userId, status);
                }
              },
            )
          : card.status;
      if (!_ownsCard(account, key, request)) return;
      _store.put(
        targetSite,
        card.status == status ? card : card.withStatus(status),
      );
    } on SiteLookupException catch (e) {
      if (!_ownsCard(account, key, request)) return;
      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeThatProfile
          : appL10n.couldnTReach(instance.host);
    } catch (_) {
      if (!_ownsCard(account, key, request)) return;
      failure = appL10n.couldnTLoadShellcontroller(username);
    } finally {
      if (_ownsCard(account, key, request)) {
        account.cards.remove(key);
        userCardRequests.finish(targetSite, key, error: failure);
      }
    }
  }

  void _retire(_PreviewAccount account) {
    if (!identical(_accounts[account.siteUrl], account)) return;
    _accounts.remove(account.siteUrl);
    account.detach();
    account.cards.clear();
    account.likers.clear();
    final notifyCards = userCardRequests._clearSite(account.siteUrl);
    final notifyLikers = likerRequests._clearSite(account.siteUrl);
    notifyCards?.call();
    notifyLikers?.call();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values) {
      account.detach();
      account.cards.clear();
      account.likers.clear();
    }
    _accounts.clear();
    userCardRequests.dispose();
    likerRequests.dispose();
  }
}

final class _PreviewAccount {
  _PreviewAccount(this.siteUrl, this.lease);

  final String siteUrl;
  final SiteLease lease;
  final Map<String, Object> cards = {};
  final Map<int, Object> likers = {};
  void Function() detach = () {};
}
