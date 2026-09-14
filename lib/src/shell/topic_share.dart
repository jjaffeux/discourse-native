import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../models/site_config.dart';
import '../theme/d_icons.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

String topicShareUrl({
  required String siteUrl,
  required int topicId,
  required SiteConfig config,
  String? slug,
  String? username,
}) {
  return config.shareUrl(
    _topicCanonicalUrl(siteUrl: siteUrl, topicId: topicId, slug: slug),
    username: username,
  );
}

String _topicCanonicalUrl({
  required String siteUrl,
  required int topicId,
  String? slug,
}) {
  final origin = siteUrl.endsWith('/')
      ? siteUrl.substring(0, siteUrl.length - 1)
      : siteUrl;
  final topicSlug = slug?.trim().isNotEmpty == true ? slug!.trim() : 'topic';
  return '$origin/t/$topicSlug/$topicId';
}

String postCanonicalUrl({
  required String siteUrl,
  required int topicId,
  required int postNumber,
  String? slug,
}) {
  final topicUrl = _topicCanonicalUrl(
    siteUrl: siteUrl,
    topicId: topicId,
    slug: slug,
  );
  return postNumber > 1 ? '$topicUrl/$postNumber' : topicUrl;
}

String postShareUrl({
  required String siteUrl,
  required int topicId,
  required int postNumber,
  required SiteConfig config,
  String? slug,
  String? username,
}) {
  final url = postCanonicalUrl(
    siteUrl: siteUrl,
    topicId: topicId,
    postNumber: postNumber,
    slug: slug,
  );
  return config.shareUrl(url, username: username);
}

String topicContinuationMarkdown({required String title, required String url}) {
  final escaped = title
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
  return 'Continue the discussion from [$escaped]($url)';
}

Future<void> Function()? captureShareReplyAsNewTopic({
  required BuildContext context,
  required String siteUrl,
  required int topicId,
  required String continuation,
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

  // Keep the sheet's delayed action tied to the source that opened it.
  // The controller owns composer creation and restoration after this check.
  return () async {
    if (!context.mounted ||
        !identical(ShellScope.maybeRead(context), controller) ||
        !lease.isCurrent ||
        controller.currentAccountIdentity != account ||
        controller.currentInstance?.url != siteUrl ||
        controller.activeTabId != tabId ||
        controller.currentContent?.topicId != topicId) {
      return;
    }
    await controller.openReplyAsNewTopic(continuation);
  };
}

Future<void> showTopicShareSheet({
  required BuildContext context,
  required String title,
  required String url,
  Future<void> Function()? onReplyAsNewTopic,
}) => _showShareSheet(
  context: context,
  heading: 'Share this topic',
  title: title,
  url: url,
  onReplyAsNewTopic: onReplyAsNewTopic,
);

Future<void> showPostShareSheet({
  required BuildContext context,
  required String topicTitle,
  required String url,
  required int postNumber,
  Future<void> Function()? onReplyAsNewTopic,
}) => _showShareSheet(
  context: context,
  heading: 'Share post #$postNumber',
  title: topicTitle,
  url: url,
  onReplyAsNewTopic: onReplyAsNewTopic,
);

Future<void> _showShareSheet({
  required BuildContext context,
  required String heading,
  required String title,
  required String url,
  Future<void> Function()? onReplyAsNewTopic,
}) => showShellSheet<void>(
  context: context,
  title: heading,
  dialogOnDesktop: true,
  showHeaderDivider: false,
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
  footerPadding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
  footerBuilder: onReplyAsNewTopic == null
      ? null
      : (context) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(),
            child: DButton(
              key: const ValueKey('topic-share-reply-as-new-topic'),
              label: const Text(
                'Reply as new topic',
                maxLines: 2,
                softWrap: true,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(onReplyAsNewTopic());
              },
              icon: const DIcon(DIcons.plus),
              size: DButtonSize.small,
              variant: DButtonVariant.ghost,
            ),
          ),
        ),
  builder: (context) => _TopicShareBody(title: title, url: url),
);

class _TopicShareBody extends StatefulWidget {
  const _TopicShareBody({required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<_TopicShareBody> createState() => _TopicShareBodyState();
}

class _TopicShareBodyState extends State<_TopicShareBody> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _notice(String message) {
    DToast.show(context, message);
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.url));
    } catch (_) {
      if (mounted) _notice("Couldn't copy link.");
      return;
    }
    if (!mounted) return;

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
    try {
      await sharing.SharePlus.instance.share(
        sharing.ShareParams(
          text: widget.url,
          subject: widget.title,
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) _notice("Couldn't open sharing.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('topic-share-url'),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final link = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    DIcon(
                      DIcons.link,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        widget.url,
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              final copy = ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: context.isTouch ? 44 : 36,
                ),
                child: DButton(
                  key: const ValueKey('topic-share-copy'),
                  label: Semantics(
                    liveRegion: true,
                    child: Text(_copied ? 'Copied!' : 'Copy link'),
                  ),
                  onPressed: () => unawaited(_copy()),
                  icon: DIcon(_copied ? DIcons.check : DIcons.copy),
                  size: DButtonSize.small,
                  variant: DButtonVariant.primary,
                ),
              );
              if (constraints.maxWidth <
                  MediaQuery.textScalerOf(context).scale(260)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    link,
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: copy,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: link),
                  const SizedBox(width: 4),
                  copy,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(),
            child: Builder(
              builder: (buttonContext) => DButton(
                key: const ValueKey('topic-share-system'),
                label: const Text(
                  'Share to another app',
                  maxLines: 2,
                  softWrap: true,
                ),
                onPressed: () => unawaited(_share(buttonContext)),
                icon: const DIcon(DIcons.upRightFromSquare),
                size: DButtonSize.small,
                variant: DButtonVariant.ghost,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
