import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/shell_lookup_api.dart';
import '../data/site_lifecycle.dart';
import '../data/topic_feeds_api.dart';
import '../models/topic_filter.dart';

/// Site lookups behind the topic filter. A lookup answers empty rather than
/// failing, and answers empty once its account session retires, so a result
/// from before a sign-out or account switch never reaches the filter.
final class TopicFilterLookups {
  const TopicFilterLookups({
    required this._topicFeeds,
    required this._lookups,
    required this._credentials,
    required this._lifecycle,
    required this._isDisposed,
  });

  final TopicFeedsApi _topicFeeds;
  final ShellLookupApi _lookups;
  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final bool Function() _isDisposed;

  Future<List<TopicFilterOption>> loadOptions(String siteUrl) => run(
    siteUrl,
    (apiKey, clientId) async => (await _topicFeeds.topicList(
      siteUrl: siteUrl,
      path: '/filter.json',
      apiKey: apiKey,
      clientId: clientId,
    )).filterOptions,
  );

  Future<List<TopicFilterLookupValue>> searchTagGroups({
    required String siteUrl,
    required String term,
  }) => run(
    siteUrl,
    (apiKey, clientId) => _lookups.searchFilterTagGroups(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<List<TopicFilterLookupValue>> searchGroups({
    required String siteUrl,
    required String term,
  }) => run(
    siteUrl,
    (apiKey, clientId) => apiKey == null
        ? Future.value(const [])
        : _lookups.searchFilterGroups(
            siteUrl: siteUrl,
            term: term,
            apiKey: apiKey,
            clientId: clientId,
          ),
  );

  Future<List<TopicFilterLookupValue>> searchUsers({
    required String siteUrl,
    required String term,
  }) => run(
    siteUrl,
    (apiKey, clientId) async => [
      for (final user in await _lookups.searchUsers(
        siteUrl: siteUrl,
        term: term,
        apiKey: apiKey,
        clientId: clientId,
      ))
        TopicFilterLookupValue(name: user.username, description: user.name),
    ],
  );

  Future<List<T>> run<T>(
    String siteUrl,
    Future<List<T>> Function(String? apiKey, String? clientId) lookup,
  ) async {
    final lease = _lifecycle.capture(siteUrl);
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(_credentials);
      if (!lease.isCurrent) return const [];
      final found = await credential.run(
        () => lookup(credential.apiKey, credential.clientId),
      );
      return !_isDisposed() && lease.isCurrent ? found : const [];
    } catch (error) {
      return const [];
    }
  }
}
