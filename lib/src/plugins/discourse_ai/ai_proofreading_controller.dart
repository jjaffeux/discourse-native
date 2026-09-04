// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';

import '../../data/discourse_api_contracts.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/site_plugin_api.dart';
import 'ai_proofreading_api.dart';
import 'ai_proofreading_data.dart';

final class AiProofreadingController extends FrameSafeNotifier
    implements PluginComposerSubmitPreparer {
  AiProofreadingController({
    required this.api,
    required PluginRequestHost requests,
    required PluginSiteStateHost siteState,
    required PluginFreshAccountHost freshAccount,
    this.diagnostics = const PluginDiagnosticsReporter.noop(),
  }) : _requests = requests,
       _siteState = siteState,
       _freshAccount = freshAccount;

  final AiProofreadingApi api;
  final PluginRequestHost _requests;
  final PluginSiteStateHost _siteState;
  final PluginFreshAccountHost _freshAccount;
  final PluginDiagnosticsReporter diagnostics;
  final Expando<bool> _enabled = Expando<bool>('ai-proofreading-enabled');

  bool isAvailable(ComposerEditorHost composer) {
    if (!composer.isCurrent || composer.isPluginTarget) return false;
    if (!composer.isNewTopic && !composer.isReply) return false;
    final settings = _siteState
        .siteConfigFor(composer.siteUrl)
        .plugins
        .discourseAiSettings;
    final currentUser = _freshAccount.recordFor(
      composer.siteUrl,
      discourseAiCurrentUserDataKey,
    );
    return settings?.proofreadingAvailable == true &&
        currentUser?.canUseAssistant == true;
  }

  bool isEnabled(ComposerEditorHost composer) => _enabled[composer] == true;

  void setEnabled(ComposerEditorHost composer, bool enabled) {
    if (!composer.isEditing || (enabled && !isAvailable(composer))) return;
    if (isEnabled(composer) == enabled) return;
    _enabled[composer] = enabled;
    notifySafely();
  }

  @override
  Future<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  ) async {
    if (!isEnabled(composer)) {
      return const PluginComposerSubmitPreparation.proceed();
    }
    if (!isAvailable(composer)) {
      _enabled[composer] = false;
      notifySafely();
      return const PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.validation,
          errors: [
            'Proofreading is no longer available. Nothing was posted. Try again to post without it.',
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

    final String suggestion;
    try {
      suggestion = await api.proofread(
        siteUrl: composer.siteUrl,
        apiKey: credential.apiKey!,
        text: source,
      );
    } on WriteException catch (error) {
      return PluginComposerSubmitPreparation.failed(
        _proofreadingFailure(error),
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
      return const PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.unreachable,
          errors: ["Couldn't proofread this post. Nothing was posted."],
        ),
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

  static WriteException _proofreadingFailure(WriteException error) =>
      WriteException(
        error.failure,
        errors: error.errors.isEmpty
            ? const ["Couldn't proofread this post. Nothing was posted."]
            : error.errors,
        statusCode: error.statusCode,
        retryAfter: error.retryAfter,
        cause: error.cause,
        causeStackTrace: error.causeStackTrace,
      );
}
