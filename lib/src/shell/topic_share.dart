import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/native_media_download_environment.dart';
import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'topic_invite.dart';

Future<void> Function()? captureShareReplyAsNewTopic({
  required BuildContext context,
  required String siteUrl,
  required int topicId,
  required String continuation,
}) => _captureShareAction(
  context: context,
  siteUrl: siteUrl,
  topicId: topicId,
  run: (shell, _) => shell.openReplyAsNewTopic(continuation),
);

Future<void> Function()? captureShareInvite({
  required BuildContext context,
  required String siteUrl,
  required int topicId,
}) => _captureShareAction(
  context: context,
  siteUrl: siteUrl,
  topicId: topicId,
  run: (shell, instance) => showTopicInviteSheet(
    context: context,
    shell: shell,
    instance: instance,
    topicId: topicId,
  ),
);

/// Ties a share surface's delayed action to the account, site, tab and topic
/// that opened it: a choice made after any of them moved on does nothing.
Future<void> Function()? _captureShareAction({
  required BuildContext context,
  required String siteUrl,
  required int topicId,
  required Future<void> Function(
    ShellController shell,
    DiscourseInstance instance,
  )
  run,
}) {
  final controller = ShellScope.read(context);
  final tabId = controller.activeTabId;
  final account = controller.currentAccountIdentity;
  if (controller.currentInstance?.url != siteUrl ||
      controller.currentContent?.topicId != topicId ||
      tabId == null) {
    return null;
  }
  final lease = controller.lifecycle.capture(siteUrl);

  return () async {
    final instance = controller.currentInstance;
    if (!context.mounted ||
        !identical(ShellScope.maybeRead(context), controller) ||
        !lease.isCurrent ||
        controller.currentAccountIdentity != account ||
        instance == null ||
        instance.url != siteUrl ||
        controller.activeTabId != tabId ||
        controller.currentContent?.topicId != topicId) {
      return;
    }
    await run(controller, instance);
  };
}

/// What a share sheet is about: what is being shared, its title and link,
/// and what else can be done from there.
class _ShareSubject {
  const _ShareSubject({
    required this.heading,
    required this.title,
    required this.url,
    required this.privateMessage,
    this.onReplyAsNewTopic,
    this.onInvite,
  });

  final String heading;
  final String title;
  final String url;
  final bool privateMessage;
  final Future<void> Function()? onReplyAsNewTopic;
  final Future<void> Function()? onInvite;

  String get replyLabel =>
      privateMessage ? appL10n.replyAsNewMessage : appL10n.replyAsNewTopic;
}

/// Whether the platform clipboard took [url].
Future<bool> _copyUrl(String url) async {
  try {
    await Clipboard.setData(ClipboardData(text: url));
    return true;
  } catch (_) {
    return false;
  }
}

/// Whether the system share sheet could be opened for [subject].
Future<bool> _shareSystem(_ShareSubject subject, Rect? origin) async {
  try {
    await const NativeMediaDownloadEnvironment().shareText(
      subject.url,
      subject: subject.title,
      sharePositionOrigin: origin,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// The topic shared from its own menu. Inviting stays here, as the one way
/// into the invite editor.
Future<void> showTopicShareSheet({
  required BuildContext context,
  required String title,
  required String url,
  Future<void> Function()? onInvite,
  bool privateMessage = false,
}) => _showShare(
  context,
  _ShareSubject(
    heading: appL10n.shareTopic,
    title: title,
    url: url,
    privateMessage: privateMessage,
    onInvite: onInvite,
  ),
);

/// A post shared from its menu or its date. The opening post is the topic,
/// so it is shared as the topic is, with nothing to continue elsewhere.
Future<void> showPostShareSheet({
  required BuildContext context,
  required String topicTitle,
  required String url,
  required int postNumber,
  Future<void> Function()? onReplyAsNewTopic,
  bool privateMessage = false,
}) => _showShare(
  context,
  _ShareSubject(
    heading: postNumber == 1
        ? appL10n.shareTopic
        : appL10n.sharePost('$postNumber'),
    title: topicTitle,
    url: url,
    privateMessage: privateMessage,
    onReplyAsNewTopic: postNumber == 1 ? null : onReplyAsNewTopic,
  ),
);

Future<void> _showShare(BuildContext context, _ShareSubject subject) =>
    showShellSheet<void>(
      context: context,
      title: subject.heading,
      dialogOnDesktop: true,
      builder: (context) => _ShareSheetBody(subject: subject),
    );

class _ShareSheetBody extends StatelessWidget {
  const _ShareSheetBody({required this.subject});

  final _ShareSubject subject;

  Future<void> _copy(BuildContext context) async {
    final copied = await _copyUrl(subject.url);
    if (!context.mounted) return;
    if (copied) DDialogClose.close<void>(context);
    DToast.show(
      context,
      copied ? appL10n.linkCopied : appL10n.couldnTCopyLink,
      type: copied ? DToastType.success : DToastType.error,
    );
  }

  Future<void> _share(BuildContext context) async {
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    if (!await _shareSystem(subject, origin)) {
      if (context.mounted) DToast.show(context, appL10n.couldnTOpenSharing);
      return;
    }
    if (context.mounted) DDialogClose.close<void>(context);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final reply = subject.onReplyAsNewTopic;
    final invite = subject.onInvite;
    Widget onward(
      Key key,
      DIconData icon,
      String label,
      Future<void> Function() run,
    ) => DButton(
      key: key,
      variant: DButtonVariant.secondary,
      icon: DIcon(icon),
      label: Text(label),
      onPressed: () {
        DDialogClose.close<void>(context);
        unawaited(run());
      },
    );
    final copy = Builder(
      builder: (buttonContext) => DButton(
        key: const ValueKey('topic-share-copy'),
        label: Text(context.l10n.copyLink),
        onPressed: () => unawaited(_copy(buttonContext)),
        icon: const DIcon(DIcons.copy),
        variant: DButtonVariant.primary,
      ),
    );
    final share = Builder(
      builder: (buttonContext) => DButton(
        key: const ValueKey('topic-share-system'),
        label: Text(context.l10n.share),
        onPressed: () => unawaited(_share(buttonContext)),
        icon: const DIcon(DIcons.upRightFromSquare),
        variant: DButtonVariant.secondary,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subject.title,
            key: const ValueKey('topic-share-title'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: DiscourseTypography.lg,
              fontWeight: FontWeight.w700,
              height: 1.3,
              letterSpacing: 0,
              color: tokens.foreground,
            ),
          ),
        ),
        const SizedBox(height: 10),
        DCard(
          key: const ValueKey('topic-share-url'),
          variant: DCardVariant.well,
          spacing: 0,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SelectableText(
              subject.url,
              style: TextStyle(
                fontSize: DiscourseTypography.xs,
                height: 1.45,
                color: tokens.mutedForeground,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < MediaQuery.textScalerOf(context).scale(200)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [copy, const SizedBox(height: 8), share],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 8),
                    Expanded(child: share),
                  ],
                ),
        ),
        if (invite != null) ...[
          const SizedBox(height: 8),
          onward(
            const ValueKey('topic-share-invite'),
            DIcons.userPlus,
            context.l10n.inviteToTopicEntry,
            invite,
          ),
        ],
        if (reply != null) ...[
          const SizedBox(height: 8),
          onward(
            const ValueKey('topic-share-reply-as-new-topic'),
            DIcons.plus,
            subject.replyLabel,
            reply,
          ),
        ],
      ],
    );
  }
}
