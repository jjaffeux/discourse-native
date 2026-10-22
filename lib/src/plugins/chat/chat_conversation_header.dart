import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The shared reading header for channels, direct messages and threads.
/// Both layouts use the page's reading lane and leave the panel visible.
class ChatConversationHeader extends StatelessWidget {
  const ChatConversationHeader({
    super.key,
    required this.title,
    required this.kindLabel,
    this.color,
    this.direct = false,
    this.messageCount,
    this.threadCount = 0,
    this.partial = false,
    this.latest,
    this.compact = false,
    this.titleBuilder,
    this.now,
  });

  final String title;
  final String kindLabel;
  final Color? color;
  final bool direct;

  /// Loaded messages; null leaves the count out, as before a first fetch.
  final int? messageCount;
  final int threadCount;
  final bool partial;
  final DateTime? latest;
  final bool compact;
  final Widget Function(Widget title)? titleBuilder;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final suffix = partial ? '+' : '';
    final count = messageCount;
    final messageLabel = count == 1 && !partial
        ? context.l10n.messageChatchannelheader
        : context.l10n.messagesChatchannelheader;
    final emphasis = TextStyle(
      color: theme.discourse.primaryHigh,
      fontWeight: FontWeight.w600,
    );
    final metadata = <InlineSpan>[
      TextSpan(text: kindLabel),
      if (count != null)
        TextSpan(
          children: [
            TextSpan(text: '$count$suffix', style: emphasis),
            TextSpan(text: messageLabel),
          ],
        ),
      if (threadCount > 0)
        TextSpan(
          children: [
            TextSpan(text: '$threadCount$suffix', style: emphasis),
            TextSpan(
              text: threadCount == 1 && !partial
                  ? context.l10n.threadChatchannelheader
                  : context.l10n.threadsChatchannelheader,
            ),
          ],
        ),
      if (latest case final date?)
        TextSpan(
          children: [
            TextSpan(
              text: context.l10n.lastAt(_dayLabel(date, now ?? DateTime.now())),
            ),
            TextSpan(
              text: clockTimeLabel(context, date.toLocal()).toLowerCase(),
              style: emphasis,
            ),
          ],
        ),
    ];
    final titleText = DText(
      title,
      variant: compact ? DTextVariant.small : DTextVariant.h3,
      headingLevel: 1,
      style: compact
          ? TextStyle(
              fontSize: DiscourseTypography.sm,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: tokens.foreground,
            )
          : null,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, compact ? 10 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                DAvatar(
                  key: const ValueKey('chat-channel-header-marker'),
                  dimension: compact ? 10 : 12,
                  border: false,
                  decorative: true,
                  borderRadius: BorderRadius.circular(
                    direct ? 6 : (compact ? 2 : 3),
                  ),
                  fallback: DAvatarFallback(
                    backgroundColor: color ?? tokens.mutedForeground,
                    child: const SizedBox.shrink(),
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: titleBuilder?.call(titleText) ?? titleText,
                  ),
                ),
                if (compact && count != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .5,
                    ),
                    child: DText(
                      '$count$suffix$messageLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      key: const ValueKey('chat-compact-message-count'),
                      style: TextStyle(
                        fontSize: DiscourseTypography.micro,
                        height: 1.5,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 16),
            Wrap(
              key: const ValueKey('chat-channel-header-metadata'),
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var index = 0; index < metadata.length; index++) ...[
                  if (index > 0)
                    DText(
                      '·',
                      style: TextStyle(
                        fontSize: DiscourseTypography.preview,
                        height: DiscourseTypography.lineHeightSmall,
                        color: theme.discourse.primaryLowMid,
                      ),
                    ),
                  DText.rich(
                    metadata[index],
                    style: TextStyle(
                      fontSize: DiscourseTypography.preview,
                      height: DiscourseTypography.lineHeightSmall,
                      color: tokens.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            DSeparator(
              key: const ValueKey('content-header-separator'),
              color: theme.shell.divider,
              space: 1,
            ),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime date, DateTime now) {
    final local = date.toLocal();
    final today = now.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (day == DateTime(today.year, today.month, today.day)) return 'today';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'yesterday';
    }
    return DateFormat(
      local.year == today.year ? 'MMM d' : 'MMM d, y',
    ).format(local);
  }
}
