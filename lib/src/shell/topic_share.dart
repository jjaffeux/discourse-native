import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import '../models/site_config.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_sheet.dart';

/// Builds the same topic link as core's `Topic#shareUrl`.
///
/// Core substitutes `topic` only when a topic has no usable slug and appends
/// the reader referral only when both badge-related site settings allow it.
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

Future<void> showTopicShareSheet({
  required BuildContext context,
  required String title,
  required String url,
  Future<void> Function()? onReplyAsNewTopic,
}) => showShellSheet<void>(
  context: context,
  title: 'Share this topic',
  dialogOnDesktop: true,
  builder: (context) => _TopicShareBody(
    title: title,
    url: url,
    onReplyAsNewTopic: onReplyAsNewTopic,
  ),
);

Future<void> showPostShareSheet({
  required BuildContext context,
  required String topicTitle,
  required String url,
  required int postNumber,
  Future<void> Function()? onReplyAsNewTopic,
}) => showShellSheet<void>(
  context: context,
  title: 'Share post #$postNumber',
  dialogOnDesktop: true,
  builder: (context) => _TopicShareBody(
    title: topicTitle,
    url: url,
    onReplyAsNewTopic: onReplyAsNewTopic,
  ),
);

class _TopicShareBody extends StatelessWidget {
  const _TopicShareBody({
    required this.title,
    required this.url,
    this.onReplyAsNewTopic,
  });

  final String title;
  final String url;
  final Future<void> Function()? onReplyAsNewTopic;

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) _notice(context, 'Link copied!');
    } catch (_) {
      if (context.mounted) _notice(context, "Couldn't copy link.");
    }
  }

  Future<void> _share(BuildContext context) async {
    final renderObject = context.findRenderObject();
    final origin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    try {
      await sharing.SharePlus.instance.share(
        sharing.ShareParams(
          text: url,
          subject: title,
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (context.mounted) _notice(context, "Couldn't open sharing.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Copy this link, or share it with another app.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('topic-share-url'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(url),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onReplyAsNewTopic != null)
              OutlinedButton.icon(
                key: const ValueKey('topic-share-reply-as-new-topic'),
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(onReplyAsNewTopic!());
                },
                icon: const DIcon(DIcons.plus, size: 16),
                label: const Text('Reply as new topic'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('topic-share-copy'),
              onPressed: () => unawaited(_copy(context)),
              icon: const DIcon(DIcons.copy, size: 16),
              label: const Text('Copy link'),
            ),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                key: const ValueKey('topic-share-system'),
                onPressed: () => unawaited(_share(buttonContext)),
                icon: const DIcon(DIcons.upRightFromSquare, size: 16),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
