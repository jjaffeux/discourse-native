import 'package:discourse_native/l10n/strings.dart';

import '../../data/account_request_session.dart';
import '../../data/api_credentials.dart';
import '../../data/composer_media_optimizer.dart';
import '../../data/composer_persistence_api.dart';
import '../../data/site_lifecycle.dart';
import '../../data/write_credential.dart';
import '../../models/composer_upload.dart';
import '../../models/site_config.dart';
import '../../plugin_api/composer_target.dart';

/// What one composer may upload and how each file reaches the site.
///
/// The configuration the composer opened with decides which files it offers,
/// while the size limit of a sent file reads the site's configuration at that
/// moment. A request starts only for the account session captured when it was
/// asked for.
final class ComposerUploads {
  const ComposerUploads({
    required this._target,
    required this._composerConfig,
    required this._api,
    required this._credentials,
    required this._lifecycle,
    required this._currentConfig,
    required this._isStaff,
    required this._isDisposed,
  });

  final ComposerTarget _target;
  final SiteConfig _composerConfig;
  final ComposerPersistenceApi _api;
  final ApiCredentialReader _credentials;
  final SiteLifecycle _lifecycle;
  final SiteConfig Function() _currentConfig;
  final bool Function() _isStaff;
  final bool Function() _isDisposed;

  /// The web composer's `privateMessage`: a reply to or edit of a post in a
  /// message is as private as a new one.
  bool get _forPrivateMessage =>
      _target.isPrivateMessage || _target.privateMessageTopic;

  bool canUploadImage(String filename) => _composerConfig.canUploadImage(
    filename,
    staff: _isStaff(),
    privateMessage: _forPrivateMessage,
  );

  bool canUploadFile(String filename) => _composerConfig.canUploadFile(
    filename,
    staff: _isStaff(),
    privateMessage: _forPrivateMessage,
  );

  Future<PreparedComposerUpload> prepare(
    ComposerUploadFile file, {
    required Future<void> abortTrigger,
  }) => ComposerMediaOptimizer().prepare(
    file,
    imageSettings: _composerConfig.composerImageOptimization,
    canUpload: canUploadFile,
    abortTrigger: abortTrigger,
  );

  Future<ComposerUploadResult> upload(
    ComposerUploadFile file, {
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
  }) async {
    if (_isDisposed()) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    final siteUrl = _target.siteUrl;
    final lease = _lifecycle.capture(siteUrl);
    final held = await readWriteCredential(
      AccountRequestSession(siteUrl, lease),
      _credentials,
      withClientId: true,
    );
    if (_isDisposed() || !lease.isCurrent) {
      throw ComposerUploadException(appL10n.uploadCancelled);
    }
    if (held.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    final target = _target;
    return held.request!.run(
      () => _api.uploadComposerImage(
        siteUrl: siteUrl,
        apiKey: held.apiKey!,
        clientId: held.request!.clientId,
        file: file,
        onProgress: onProgress,
        abortTrigger: abortTrigger,
        uploadType: target is PluginComposerTarget
            ? target.policy.uploadType
            : ComposerUploadType.composer,
        forPrivateMessage: _forPrivateMessage,
        sizeLimit: _currentConfig().uploadSizeLimit(
          file.name,
          staff: _isStaff(),
          privateMessage: _forPrivateMessage,
        ),
      ),
    );
  }

  Future<Map<String, String>> resolveUrls(Iterable<String> urls) async {
    final siteUrl = _target.siteUrl;
    final lease = _lifecycle.capture(siteUrl);
    final held = await readWriteCredential(
      AccountRequestSession(siteUrl, lease),
      _credentials,
      withClientId: true,
    );
    if (_isDisposed() || !lease.isCurrent) return const {};
    if (held.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    return held.request!.run(
      () => _api.lookupUploadUrls(
        siteUrl: siteUrl,
        apiKey: held.apiKey!,
        clientId: held.request!.clientId,
        shortUrls: urls,
      ),
    );
  }
}
