import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/site_lookup_failure.dart';
import '../models/discourse_instance.dart';
import '../models/forum_about.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';

/// Reads a site serves to members and visitors alike.
///
/// Key presence is not account identity: a failed credential deletion can
/// leave an orphaned key in secure storage. The stored instance is the account
/// boundary, so a signed-out site is read publicly and never receives that key.
final class SiteReadPolicy {
  const SiteReadPolicy({
    required this._siteAppearance,
    required this._siteConfig,
    required this._customEmojis,
    required this._emojiCatalog,
    required this._emojiSearchAliases,
    required this._forumAbout,
    required this._credentials,
    required this._lifecycle,
    required this._instanceFor,
    required this._isDisposed,
  });

  final Future<SiteAppearance?> Function({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  })
  _siteAppearance;
  final Future<SiteConfig> Function({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  })
  _siteConfig;
  final Future<Map<String, String>> Function({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  })
  _customEmojis;
  final Future<SiteEmojiCatalog> Function({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  })
  _emojiCatalog;
  final Future<Map<String, List<String>>> Function({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  })
  _emojiSearchAliases;
  final Future<ForumAbout> Function({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  })
  _forumAbout;
  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final DiscourseInstance? Function(String siteUrl) _instanceFor;
  final bool Function() _isDisposed;

  Future<SiteAppearance?> loadAppearance({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final forwarded = _forwarded(siteUrl, apiKey, clientId);
    return _siteAppearance(
      siteUrl: siteUrl,
      username: forwarded.username,
      apiKey: forwarded.apiKey,
      clientId: forwarded.clientId,
    );
  }

  Future<SiteConfig> loadConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final forwarded = _forwarded(siteUrl, apiKey, clientId);
    return _siteConfig(
      siteUrl: siteUrl,
      apiKey: forwarded.apiKey,
      clientId: forwarded.clientId,
    );
  }

  Future<Map<String, String>> loadCustomEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final forwarded = _forwarded(siteUrl, apiKey, clientId);
    return _customEmojis(
      siteUrl: siteUrl,
      apiKey: forwarded.apiKey,
      clientId: forwarded.clientId,
    );
  }

  Future<SiteEmojiCatalog> loadEmojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final forwarded = _forwarded(siteUrl, apiKey, clientId);
    return _emojiCatalog(
      siteUrl: siteUrl,
      apiKey: forwarded.apiKey,
      clientId: forwarded.clientId,
    );
  }

  Future<Map<String, List<String>>> loadEmojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final forwarded = _forwarded(siteUrl, apiKey, clientId);
    return _emojiSearchAliases(
      siteUrl: siteUrl,
      apiKey: forwarded.apiKey,
      clientId: forwarded.clientId,
    );
  }

  Future<ForumAbout> loadForumAbout(String siteUrl) async {
    final instance = _instanceFor(siteUrl);
    final lease = _lifecycle.capture(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    final session = AccountRequestSession(siteUrl, lease);
    final credential = instance.isConnected
        ? await session.credentials(_credentials)
        : session.anonymousCredentials();
    if (instance.isConnected && credential.apiKey == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    final about = await credential.run(
      () => _forumAbout(
        siteUrl: siteUrl,
        apiKey: credential.apiKey,
        clientId: credential.clientId,
      ),
    );
    if (_isDisposed() || !lease.isCurrent) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return about;
  }

  ({String? username, String? apiKey, String? clientId}) _forwarded(
    String siteUrl,
    String? apiKey,
    String? clientId,
  ) {
    final instance = _instanceFor(siteUrl);
    if (apiKey == null || instance?.isConnected != true) {
      return (username: null, apiKey: null, clientId: null);
    }
    return (
      username: instance!.user!.username,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
