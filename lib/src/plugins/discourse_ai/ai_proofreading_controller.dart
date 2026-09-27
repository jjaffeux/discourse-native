// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'ai_proofreading_api.dart';
import 'ai_proofreading_data.dart';
import 'ai_proofreading_preferences.dart';

final class AiProofreadingController extends FrameSafeNotifier
    implements PluginComposerSubmitPreparer {
  AiProofreadingController({
    required this.api,
    required PluginRequestHost requests,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    this.preferences = const AiProofreadingPreferenceStore(),
    this.diagnostics = const PluginDiagnosticsReporter.noop(),
  }) : _requests = requests,
       _siteState = siteState,
       _freshAccount = freshAccount;

  final AiProofreadingApi api;
  final PluginRequestHost _requests;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final AiProofreadingPreferenceStore preferences;
  final PluginDiagnosticsReporter diagnostics;
  final Map<String, bool> _enabledBySite = {};
  final Set<String> _loadedSites = {};
  final Map<String, Future<void>> _siteLoads = {};
  final Map<String, int> _siteRevisions = {};

  /// Composers whose author has been told proofreading could not run, so their
  /// retries post without it, as that message promises. The site preference
  /// stays on: the next composer proofreads once the site offers it again.
  final Expando<bool> _postingWithout = Expando<bool>(
    'ai-proofreading-posting-without',
  );

  /// The site preference only ever applies to these composers: every other
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
    unawaited(_ensurePreferenceLoaded(composer.siteUrl));
    return _enabledFor(composer);
  }

  bool _enabledFor(ComposerEditorHost composer) =>
      _enabledBySite[composer.siteUrl] == true &&
      _postingWithout[composer] != true;

  void setEnabled(ComposerEditorHost composer, bool enabled) {
    if (!composer.isEditing || (enabled && !isAvailable(composer))) return;
    final resumed = enabled && _postingWithout[composer] == true;
    if (resumed) _postingWithout[composer] = null;
    final siteUrl = composer.siteUrl;
    if (_enabledBySite[siteUrl] == enabled && _loadedSites.contains(siteUrl)) {
      if (resumed) notifySafely();
      return;
    }
    _siteRevisions.update(
      siteUrl,
      (revision) => revision + 1,
      ifAbsent: () => 1,
    );
    _loadedSites.add(siteUrl);
    _enabledBySite[siteUrl] = enabled;
    notifySafely();
    unawaited(preferences.write(siteUrl: siteUrl, enabled: enabled));
  }

  @override
  Future<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  ) async {
    if (!_covers(composer)) {
      return const PluginComposerSubmitPreparation.proceed();
    }
    await _ensurePreferenceLoaded(composer.siteUrl);
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

  Future<void> _ensurePreferenceLoaded(String siteUrl) {
    if (_loadedSites.contains(siteUrl)) return Future<void>.value();
    final existing = _siteLoads[siteUrl];
    if (existing != null) return existing;

    final revision = _siteRevisions[siteUrl] ?? 0;
    late final Future<void> loading;
    loading = preferences
        .read(siteUrl: siteUrl)
        .then((enabled) {
          if (isDisposed || (_siteRevisions[siteUrl] ?? 0) != revision) return;
          final changed = _enabledBySite[siteUrl] != enabled;
          _loadedSites.add(siteUrl);
          _enabledBySite[siteUrl] = enabled;
          if (changed) notifySafely();
        })
        .whenComplete(() {
          if (identical(_siteLoads[siteUrl], loading)) {
            final _ = _siteLoads.remove(siteUrl);
          }
        });
    _siteLoads[siteUrl] = loading;
    return loading;
  }
}
