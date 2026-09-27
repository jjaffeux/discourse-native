// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'ai_proofreading_api.dart';
import 'ai_proofreading_data.dart';
import 'ai_proofreading_preferences.dart';

typedef _Account = ({String siteUrl, int userId});

final class AiProofreadingController extends FrameSafeNotifier
    implements PluginComposerSubmitPreparer {
  AiProofreadingController({
    required this.api,
    required PluginRequestHost requests,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    required PluginUserIdReader currentUserId,
    this.preferences = const AiProofreadingPreferenceStore(),
    this.diagnostics = const PluginDiagnosticsReporter.noop(),
  }) : _requests = requests,
       _siteState = siteState,
       _freshAccount = freshAccount,
       _currentUserId = currentUserId;

  final AiProofreadingApi api;
  final PluginRequestHost _requests;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final PluginUserIdReader _currentUserId;
  final AiProofreadingPreferenceStore preferences;
  final PluginDiagnosticsReporter diagnostics;

  /// The choice belongs to the signed-in account: another account on the same
  /// forum has not agreed to send its posts to the helper.
  final Map<_Account, bool> _enabledByAccount = {};
  final Set<_Account> _loadedAccounts = {};
  final Map<_Account, Future<void>> _accountLoads = {};

  /// Advanced by every choice made and every [forget], and never reset, so a
  /// read started before either cannot commit after it.
  final Map<String, int> _siteRevisions = {};

  /// Composers whose author has been told proofreading could not run, so their
  /// retries post without it, as that message promises. The account's choice
  /// stays on: the next composer proofreads once the site offers it again.
  final Expando<bool> _postingWithout = Expando<bool>(
    'ai-proofreading-posting-without',
  );

  /// The preference only ever applies to these composers: every other
  /// one posts exactly as written. A reply in a message topic is covered only
  /// where the site lets the helper into messages; the site does not enforce
  /// that itself, and a preference set on a public reply must not carry
  /// message text there.
  bool _covers(ComposerEditorHost composer) =>
      !composer.isPluginTarget &&
      (composer.isNewTopic || composer.isReply) &&
      (!composer.isPrivateMessage ||
          _settingsFor(composer.siteUrl)?.helperAllowedInPrivateMessages ==
              true);

  DiscourseAiSettings? _settingsFor(String siteUrl) =>
      _siteState.siteConfigFor(siteUrl).plugins.discourseAiSettings;

  bool isAvailable(ComposerEditorHost composer) {
    if (!composer.isCurrent || !_covers(composer)) return false;
    final currentUser = _freshAccount.recordFor(
      composer.siteUrl,
      discourseAiCurrentUserDataKey,
    );
    return _settingsFor(composer.siteUrl)?.proofreadingAvailable == true &&
        currentUser?.canUseAssistant == true &&
        currentUser?.canProofread == true;
  }

  bool isEnabled(ComposerEditorHost composer) {
    final account = _accountFor(composer.siteUrl);
    if (account != null) unawaited(_ensurePreferenceLoaded(account));
    return _enabledFor(composer);
  }

  _Account? _accountFor(String siteUrl) => switch (_currentUserId(siteUrl)) {
    final userId? => (siteUrl: siteUrl, userId: userId),
    null => null,
  };

  bool _enabledFor(ComposerEditorHost composer) {
    final account = _accountFor(composer.siteUrl);
    return account != null &&
        _enabledByAccount[account] == true &&
        _postingWithout[composer] != true;
  }

  void setEnabled(ComposerEditorHost composer, bool enabled) {
    if (!composer.isEditing || (enabled && !isAvailable(composer))) return;
    final account = _accountFor(composer.siteUrl);
    if (account == null) return;
    final resumed = enabled && _postingWithout[composer] == true;
    if (resumed) _postingWithout[composer] = null;
    if (_enabledByAccount[account] == enabled &&
        _loadedAccounts.contains(account)) {
      if (resumed) notifySafely();
      return;
    }
    _advanceRevision(account.siteUrl);
    _loadedAccounts.add(account);
    _enabledByAccount[account] = enabled;
    notifySafely();
    unawaited(
      preferences.write(
        siteUrl: account.siteUrl,
        userId: account.userId,
        enabled: enabled,
      ),
    );
  }

  /// Drops what was read for the forum's accounts when its account changes or
  /// it is removed. Each account's stored choice stays for its return.
  void forget(String siteUrl) {
    _advanceRevision(siteUrl);
    bool onSite(_Account account) => account.siteUrl == siteUrl;
    _enabledByAccount.removeWhere((account, _) => onSite(account));
    _loadedAccounts.removeWhere(onSite);
    _accountLoads.removeWhere((account, _) => onSite(account));
  }

  void _advanceRevision(String siteUrl) => _siteRevisions.update(
    siteUrl,
    (revision) => revision + 1,
    ifAbsent: () => 1,
  );

  @override
  Future<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  ) async {
    final account = _accountFor(composer.siteUrl);
    if (!_covers(composer) || account == null) {
      return const PluginComposerSubmitPreparation.proceed();
    }
    await _ensurePreferenceLoaded(account);
    // The forum's account may have changed while loading; only the choice of
    // the account now signed in applies.
    if (!_enabledFor(composer)) {
      return const PluginComposerSubmitPreparation.proceed();
    }
    // Availability that is only unknown so far (the account record refreshes
    // after launch) is treated like withdrawn availability: an explicit
    // preference is never skipped silently, and saying so costs one tap.
    if (!isAvailable(composer)) {
      _postingWithout[composer] = true;
      notifySafely();
      return const PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.validation,
          errors: [
            "Proofreading isn't available right now. Nothing was posted. Try again to post without it.",
          ],
        ),
      );
    }

    final expectedValue = composer.value;
    final source = expectedValue.text;
    final lease = _requests.capture(composer.siteUrl);
    final credential = await _requests.writeCredentialFor(composer.siteUrl);
    if (!lease.isCurrent) {
      return const PluginComposerSubmitPreparation.failed(
        WriteException(WriteFailure.conflict),
      );
    }
    if (credential.failure case final failure?) {
      return PluginComposerSubmitPreparation.failed(failure);
    }

    // Proofreading is optional; keep the original text if the request fails.
    var suggestion = source;
    try {
      suggestion = await api.proofread(
        siteUrl: composer.siteUrl,
        apiKey: credential.apiKey!,
        text: source,
      );
    } catch (error, stackTrace) {
      diagnostics.reportError(
        error,
        stackTrace,
        operation: 'ai.proofreadComposer',
        source: 'discourse-ai',
        handled: true,
        degraded: true,
      );
    }

    if (!lease.isCurrent) {
      return const PluginComposerSubmitPreparation.failed(
        WriteException(WriteFailure.conflict),
      );
    }
    if (suggestion == source) {
      return const PluginComposerSubmitPreparation.proceed();
    }
    final committed = composer.commit(
      expectedValue: expectedValue,
      value: TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      ),
    );
    if (!committed) {
      return const PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.conflict,
          errors: [
            'The post changed while it was being proofread. Nothing was posted. Review it and try again.',
          ],
        ),
      );
    }
    return const PluginComposerSubmitPreparation.proceed(changed: true);
  }

  Future<void> _ensurePreferenceLoaded(_Account account) {
    if (_loadedAccounts.contains(account)) return Future<void>.value();
    final existing = _accountLoads[account];
    if (existing != null) return existing;

    final siteUrl = account.siteUrl;
    final revision = _siteRevisions[siteUrl] ?? 0;
    late final Future<void> loading;
    loading = preferences
        .read(siteUrl: siteUrl, userId: account.userId)
        .then((enabled) {
          if (isDisposed || (_siteRevisions[siteUrl] ?? 0) != revision) return;
          final changed = _enabledByAccount[account] != enabled;
          _loadedAccounts.add(account);
          _enabledByAccount[account] = enabled;
          if (changed) notifySafely();
        })
        .whenComplete(() {
          if (identical(_accountLoads[account], loading)) {
            final _ = _accountLoads.remove(account);
          }
        });
    _accountLoads[account] = loading;
    return loading;
  }
}
