import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/native_media_download_environment.dart';
import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import 'platform.dart';
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

/// What a share surface is about: both the sheet and the anchored menu render
/// from one of these, so they cannot disagree on what is being shared.
class _ShareSubject {
  const _ShareSubject({
    required this.heading,
    required this.title,
    required this.url,
    required this.privateMessage,
    required this.onReplyAsNewTopic,
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

Future<void> showTopicShareSheet({
  required BuildContext context,
  required String title,
  required String url,
  Future<void> Function()? onReplyAsNewTopic,
  Future<void> Function()? onInvite,
  bool privateMessage = false,
  Rect? anchor,
}) => _showShare(
  context,
  _ShareSubject(
    heading: appL10n.shareThisTopic,
    title: title,
    url: url,
    privateMessage: privateMessage,
    onReplyAsNewTopic: onReplyAsNewTopic,
    onInvite: onInvite,
  ),
  anchor,
);

Future<void> showPostShareSheet({
  required BuildContext context,
  required String topicTitle,
  required String url,
  required int postNumber,
  Future<void> Function()? onReplyAsNewTopic,
  bool privateMessage = false,
  Rect? anchor,
}) => _showShare(
  context,
  _ShareSubject(
    heading: appL10n.sharePost((postNumber).toString()),
    title: topicTitle,
    url: url,
    privateMessage: privateMessage,
    onReplyAsNewTopic: onReplyAsNewTopic,
  ),
  anchor,
);

Future<void> _showShare(
  BuildContext context,
  _ShareSubject subject,
  Rect? anchor,
) {
  if (anchor == null || context.isTouch) {
    return showShellSheet<void>(
      context: context,
      title: subject.heading,
      dialogOnDesktop: true,
      builder: (context) => _ShareSheetBody(subject: subject),
    );
  }
  return _showShareMenu(context, subject, anchor);
}

enum _ShareMenuChoice { copy, system, invite, reply }

Future<void> _showShareMenu(
  BuildContext context,
  _ShareSubject subject,
  Rect anchor,
) async {
  _ShareMenuChoice? choice;
  await showDDropdownMenu<void>(
    context: context,
    anchorRect: anchor,
    restoreFocus: false,
    builder: (menuContext) {
      final muted = DTokens.of(menuContext).mutedForeground;
      Widget icon(DIconData data) => DIcon(data, size: 13, color: muted);
      return DDropdownMenuContent(
        semanticLabel: subject.heading,
        width: 280,
        children: [
          DDropdownMenuLabel(child: Text(subject.heading)),
          DDropdownMenuItem(
            key: const ValueKey('topic-share-copy'),
            leading: icon(DIcons.link),
            leadingGap: 9,
            semanticLabel: appL10n.copyLink,
            onPressed: () => choice = _ShareMenuChoice.copy,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appL10n.copyLink),
                Text(
                  subject.url,
                  key: const ValueKey('topic-share-url'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: DiscourseTypography.xs,
                  ),
                ),
              ],
            ),
          ),
          DDropdownMenuItem(
            key: const ValueKey('topic-share-system'),
            leading: icon(DIcons.upRightFromSquare),
            leadingGap: 9,
            onPressed: () => choice = _ShareMenuChoice.system,
            child: Text(appL10n.shareToAnotherApp),
          ),
          if (subject.onInvite != null)
            DDropdownMenuItem(
              key: const ValueKey('topic-share-invite'),
              leading: icon(DIcons.userPlus),
              leadingGap: 9,
              onPressed: () => choice = _ShareMenuChoice.invite,
              child: Text(appL10n.inviteToTopicEntry),
            ),
          if (subject.onReplyAsNewTopic != null) ...[
            const DDropdownMenuSeparator(),
            DDropdownMenuItem(
              key: const ValueKey('topic-share-reply-as-new-topic'),
              leading: icon(DIcons.plus),
              leadingGap: 9,
              onPressed: () => choice = _ShareMenuChoice.reply,
              child: Text(subject.replyLabel),
            ),
          ],
        ],
      );
    },
  );
  switch (choice) {
    case null:
      return;
    case _ShareMenuChoice.copy:
      final copied = await _copyUrl(subject.url);
      if (!context.mounted) return;
      DToast.show(
        context,
        copied ? appL10n.linkCopied : appL10n.couldnTCopyLink,
        type: copied ? DToastType.success : DToastType.error,
      );
    case _ShareMenuChoice.system:
      if (await _shareSystem(subject, anchor) || !context.mounted) return;
      DToast.show(context, appL10n.couldnTOpenSharing);
    case _ShareMenuChoice.invite:
      await subject.onInvite!();
    case _ShareMenuChoice.reply:
      await subject.onReplyAsNewTopic!();
  }
}

class _ShareSheetBody extends StatefulWidget {
  const _ShareSheetBody({required this.subject});

  final _ShareSubject subject;

  @override
  State<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends State<_ShareSheetBody> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final copied = await _copyUrl(widget.subject.url);
    if (!mounted) return;
    if (!copied) {
      DToast.show(context, appL10n.couldnTCopyLink);
      return;
    }
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _share(BuildContext context) async {
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    if (await _shareSystem(widget.subject, origin) || !mounted) return;
    DToast.show(this.context, appL10n.couldnTOpenSharing);
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final reply = subject.onReplyAsNewTopic;
    final invite = subject.onInvite;
    final copy = DButton(
      key: const ValueKey('topic-share-copy'),
      label: Semantics(
        liveRegion: true,
        child: Text(
          _copied ? context.l10n.copiedInviteeditor : context.l10n.copyLink,
        ),
      ),
      onPressed: () => unawaited(_copy()),
      icon: DIcon(_copied ? DIcons.check : DIcons.copy),
      variant: DButtonVariant.primary,
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
        DCard(
          key: const ValueKey('topic-share-url'),
          variant: DCardVariant.well,
          children: [
            DCardContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DCardTitle(
                    child: Text(
                      subject.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: DSpacing.xs),
                  DCardDescription(child: SelectableText(subject.url)),
                ],
              ),
            ),
          ],
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
          DItem(
            key: const ValueKey('topic-share-invite'),
            variant: DItemVariant.outline,
            onPressed: () {
              DDialogClose.close<void>(context);
              unawaited(invite());
            },
            children: [
              const DItemMedia(
                variant: DItemMediaVariant.icon,
                child: DIcon(DIcons.userPlus),
              ),
              DItemContent(
                children: [
                  DItemTitle(child: Text(context.l10n.inviteToTopicEntry)),
                ],
              ),
            ],
          ),
        ],
        if (reply != null) ...[
          const SizedBox(height: 8),
          DItem(
            key: const ValueKey('topic-share-reply-as-new-topic'),
            variant: DItemVariant.outline,
            onPressed: () {
              DDialogClose.close<void>(context);
              unawaited(reply());
            },
            children: [
              const DItemMedia(
                variant: DItemMediaVariant.icon,
                child: DIcon(DIcons.plus),
              ),
              DItemContent(
                children: [DItemTitle(child: Text(subject.replyLabel))],
              ),
            ],
          ),
        ],
      ],
    );
  }
}
