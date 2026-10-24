import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/discourse_instance.dart';
import '../models/user_card.dart';
import 'preview_requests.dart';

final class PreviewLoadingOwner {
  PreviewLoadingOwner({
    required this.site,
    required this.topicContent,
    required this.credentials,
    required this.lifecycle,
    required this.store,
  });

  final ShellSiteApi site;
  final TopicContentApi topicContent;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final PreviewRequests<String> userCardRequests = PreviewRequests();
  final PreviewRequests<int> likerRequests = PreviewRequests();
  bool _disposed = false;

  Future<void> loadLikers(DiscourseInstance instance, int postId) async {
    final targetSite = instance.url;

    // Captured before the fetch is announced, so a listener that replaces
    // the account cannot hand this fetch the new one.
    final lease = lifecycle.capture(targetSite);
    if (!likerRequests.begin(targetSite, postId)) return;
    String? failure;

    try {
      final credential = await AccountRequestSession(
        targetSite,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final fetched = await credential.run(
        () => topicContent.postLikers(
          siteUrl: targetSite,
          postId: postId,
          // Keep credential reads inside the guarded try: macOS entitlement
          // failures must not strand the fetch in [likerRequests].
          apiKey: credential.apiKey,
        ),
      );
      lease.commit(() => store.put(targetSite, fetched));
    } on SiteLookupException catch (e) {
      if (_disposed ||
          !lease.isCurrent ||
          !likerRequests.isPending(targetSite, postId)) {
        return;
      }

      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeWhoLikedThis
          : appL10n.couldnTReach((instance.host).toString());
    } catch (error) {
      if (_disposed ||
          !lease.isCurrent ||
          !likerRequests.isPending(targetSite, postId)) {
        return;
      }

      failure = appL10n.couldnTLoadWhoLikedThis;
    } finally {
      lease.commit(
        () => likerRequests.finish(targetSite, postId, error: failure),
      );
    }
  }

  Future<void> loadUserCard(
    DiscourseInstance instance,
    String username, {
    bool force = false,
  }) async {
    if (username.isEmpty) return;
    final targetSite = instance.url;

    final key = username.toLowerCase();
    if (userCardRequests.isPending(targetSite, key)) return;
    if (!force) {
      if (userCardRequests.errorFor(targetSite, key) != null) return;
      if (store.read<UserCard>(targetSite, key) != null) return;
    }

    // Captured before the fetch is announced, so a listener that replaces
    // the account cannot hand this fetch the new one.
    final lease = lifecycle.capture(targetSite);
    userCardRequests.begin(targetSite, key);
    String? failure;

    try {
      final credential = await AccountRequestSession(
        targetSite,
        lease,
      ).keyCredentials(credentials);
      if (!lease.isCurrent) return;
      final card = await credential.run(
        () => site.userCard(
          siteUrl: targetSite,
          username: username,
          // Read inside the guard, the way `loadLikers` does: storage that
          // throws would otherwise strand the fetch in [userCardRequests].
          apiKey: credential.apiKey,
        ),
      );
      lease.commit(() => store.put(targetSite, card));
    } on SiteLookupException catch (e) {
      if (_disposed ||
          !lease.isCurrent ||
          !userCardRequests.isPending(targetSite, key)) {
        return;
      }

      failure = e.failure == SiteLookupFailure.notDiscourse
          ? appL10n.couldnTSeeThatProfile
          : appL10n.couldnTReach((instance.host).toString());
    } catch (error) {
      if (_disposed ||
          !lease.isCurrent ||
          !userCardRequests.isPending(targetSite, key)) {
        return;
      }

      failure = appL10n.couldnTLoadShellcontroller((username).toString());
    } finally {
      lease.commit(
        () => userCardRequests.finish(targetSite, key, error: failure),
      );
    }
  }

  void forget(String siteUrl) {
    likerRequests.forget(siteUrl);
    userCardRequests.forget(siteUrl);
  }

  void dispose() {
    _disposed = true;
    userCardRequests.dispose();
    likerRequests.dispose();
  }
}
