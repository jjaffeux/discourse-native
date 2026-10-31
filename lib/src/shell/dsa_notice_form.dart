import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_request_session.dart';
import '../models/dsa_notice.dart';
import 'anonymous_flag_dialog.dart';
import 'dsa_notice_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

Future<void> showIllegalContentReport({
  required BuildContext context,
  required String siteUrl,
  required String contentUrl,
  required String title,
}) async {
  final shell = ShellScope.read(context);
  final config = shell.siteConfigFor(siteUrl);
  if (!config.dsaReportingEnabled) {
    final email = config.anonymousFlagReportEmail;
    if (config.allowAllUsersToFlagIllegalContent && email != null) {
      await showAnonymousIllegalContentDialog(
        context: context,
        email: email,
        topicTitle: title,
        postUrl: contentUrl,
      );
    }
    return;
  }
  final instance = shell.instanceFor(siteUrl);
  if (instance == null) return;
  final lease = shell.lifecycle.capture(siteUrl);
  final account = AccountRequestSession(siteUrl, lease);
  final AccountRequestCredentials credentials;
  try {
    credentials = instance.isConnected
        ? await account.credentials(shell.credentials)
        : account.anonymousCredentials();
  } catch (_) {
    if (lease.isCurrent && context.mounted) {
      DToast.show(
        context,
        appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain,
        type: DToastType.error,
      );
    }
    return;
  }
  if (!lease.isCurrent || !context.mounted) return;
  if (instance.isConnected && credentials.apiKey == null) return;
  final controller = DsaNoticeController(
    connection: shell.api.dsaNotices.dsaNoticeConnection(
      siteUrl: siteUrl,
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    ),
    execute: credentials.run,
    sessionIsCurrent: () => lease.isCurrent,
    useAccountEmail: instance.user?.canUseDsaAccountEmail == true,
  );
  final detach = lease.onRetire(controller.retire);
  try {
    await showShellSheet<void>(
      context: context,
      title: appL10n.reportIllegalContent,
      dialogOnDesktop: true,
      surfaceBuilder: (_, sheet) => DsaNoticeForm(
        sheet: sheet,
        controller: controller,
        contentUrl: contentUrl,
        initialName: instance.user?.name ?? instance.user?.username ?? '',
      ),
      builder: (context) =>
          ShellSheetForm.of<_DsaNoticeFormState>(context)._body(context),
      footerBuilder: (context) =>
          ShellSheetForm.of<_DsaNoticeFormState>(context)._footer(context),
    );
  } finally {
    detach();
    controller.dispose();
  }
}

class DsaNoticeForm extends StatefulWidget {
  const DsaNoticeForm({
    super.key,
    required this.controller,
    required this.contentUrl,
    this.initialName = '',
    this.sheet,
  });

  final DsaNoticeController controller;
  final String contentUrl;
  final String initialName;
  final Widget? sheet;

  @override
  State<DsaNoticeForm> createState() => _DsaNoticeFormState();
}

class _DsaNoticeFormState extends State<DsaNoticeForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _email = TextEditingController();
  final _explanation = TextEditingController();
  final _code = TextEditingController();
  bool _declaration = false;

  @override
  void initState() {
    super.initState();
    for (final field in [_name, _email, _explanation, _code]) {
      field.addListener(_changed);
    }
  }

  void _changed() {
    widget.controller.emailChanged(_email.text);
    setState(() {});
  }

  @override
  void dispose() {
    for (final field in [_name, _email, _explanation, _code]) {
      field.removeListener(_changed);
      field.dispose();
    }
    super.dispose();
  }

  DsaNoticeDraft get _draft => DsaNoticeDraft(
    contentUrl: widget.contentUrl,
    explanation: _explanation.text,
    name: _name.text,
    email: _email.text,
    declaration: _declaration,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !widget.controller.busy,
      child: widget.sheet == null
          ? _body(context)
          : ShellSheetForm(state: this, child: widget.sheet!),
    ),
  );

  Widget _body(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.reference case final reference?) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(appL10n.dsaReportReceived),
            Text(appL10n.dsaReportReference(reference)),
          ],
        );
      }
      final enabled = controller.isCurrent && !controller.busy;
      return PopScope(
        canPop: !controller.busy,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(appL10n.dsaReportDescription),
            DInput(
              value: widget.contentUrl,
              labelText: appL10n.dsaContentUrl,
              readOnly: true,
            ),
            DTextarea(
              key: const ValueKey('dsa-explanation'),
              controller: _explanation,
              labelText: appL10n.describeTheIllegalContent,
              minLines: 3,
              maxLines: 6,
              maxLength: 20000,
              enabled: enabled,
            ),
            Text(appL10n.dsaExplanationHelp),
            DInput(
              key: const ValueKey('dsa-name'),
              controller: _name,
              labelText: appL10n.dsaYourName,
              maxLength: 200,
              enabled: enabled,
            ),
            if (controller.useAccountEmail)
              Text(appL10n.dsaAccountEmail)
            else ...[
              DInput(
                key: const ValueKey('dsa-email'),
                controller: _email,
                labelText: appL10n.dsaContactEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                maxLength: 254,
                enabled: enabled,
              ),
              if (!controller.emailVerified)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DButton(
                    key: const ValueKey('dsa-send-code'),
                    label: Text(
                      controller.codeRequested
                          ? appL10n.dsaResendCode
                          : appL10n.dsaSendCode,
                    ),
                    loading:
                        controller.activity ==
                        DsaNoticeActivity.requestingEmail,
                    onPressed: enabled && DsaNoticeDraft.validEmail(_email.text)
                        ? controller.requestCode
                        : null,
                  ),
                ),
              if (controller.codeRequested && !controller.emailVerified) ...[
                DInput(
                  key: const ValueKey('dsa-code'),
                  controller: _code,
                  labelText: appL10n.dsaVerificationCode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  enabled: enabled,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DButton(
                    key: const ValueKey('dsa-verify-code'),
                    label: Text(appL10n.dsaVerifyEmail),
                    loading:
                        controller.activity == DsaNoticeActivity.verifyingEmail,
                    onPressed: enabled && _code.text.length == 6
                        ? () => controller.verifyCode(_code.text)
                        : null,
                  ),
                ),
              ],
              if (controller.emailVerified) Text(appL10n.dsaEmailVerified),
            ],
            DCheckbox(
              key: const ValueKey('dsa-declaration'),
              value: _declaration,
              enabled: enabled,
              onChanged: enabled
                  ? (value) => setState(() => _declaration = value == true)
                  : null,
              title: DLabel(
                child: Text(appL10n.whatIVeWrittenAboveIsAccurateAndComplete),
              ),
            ),
            if (controller.error case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('dsa-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (widget.sheet == null) _footer(context),
          ],
        ),
      );
    },
  );

  Widget _footer(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: controller.reference != null
            ? DButton(
                label: Text(appL10n.close),
                onPressed: () => DDialogClose.close<void>(context),
              )
            : DButton(
                key: const ValueKey('dsa-submit'),
                variant: DButtonVariant.primary,
                label: Text(appL10n.dsaSubmitReport),
                loading: controller.activity == DsaNoticeActivity.submitting,
                onPressed: controller.canSubmit(_draft)
                    ? () => controller.submit(_draft)
                    : null,
              ),
      );
    },
  );
}
