import 'api_credentials.dart';

final class SiteAssetAccount {
  SiteAssetAccount._(this._siteUrl, this._apiKey, this._clientId);

  final String _siteUrl;
  final String? _apiKey;
  final String? _clientId;
  late final String? _origin = Uri.tryParse(_siteUrl)?.origin;

  static Future<SiteAssetAccount> open({
    required String siteUrl,
    required ApiCredentialReader credentials,
    required void Function() requireCurrent,
    Future<T> Function<T>(Future<T>) waitForCredential = _waitForCredential,
  }) async {
    final apiKey = await waitForCredential(credentials.apiKeyFor(siteUrl));
    requireCurrent();
    if (apiKey == null) return SiteAssetAccount._(siteUrl, null, null);

    final clientId = await waitForCredential(credentials.clientId());
    requireCurrent();
    return SiteAssetAccount._(siteUrl, apiKey, clientId);
  }

  bool get hasOrigin => _origin?.isNotEmpty ?? false;

  bool get hasCredentials => _apiKey != null;

  bool isForumHop(Uri url) => url.origin == _origin;

  Map<String, String> headersFor(Uri url) {
    final key = _apiKey;
    if (key == null || !isForumHop(url)) return const {};
    return {
      'User-Api-Key': key,
      if (_clientId case final id? when id.isNotEmpty) 'User-Api-Client-Id': id,
    };
  }
}

Future<T> _waitForCredential<T>(Future<T> operation) => operation;
