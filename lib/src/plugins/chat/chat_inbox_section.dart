import 'package:discourse_native/discourse_plugin_contracts.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

export 'chat_inbox_order.dart' show ChatInboxSectionSlice;

class ChatInboxMore extends StatelessWidget {
  const ChatInboxMore({
    super.key,
    required this.hidden,
    required this.expanded,
    required this.onPressed,
    this.hiddenUnread,
    this.compact = false,
  });

  final int hidden;

  /// How many of the [hidden] rows are new, for a group of chats, whose way
  /// to the rest says what is folded. Null for rows that are never new.
  final int? hiddenUnread;
  final bool expanded;
  final VoidCallback onPressed;
  final bool compact;

  String _label(BuildContext context) {
    if (expanded) return context.l10n.chatViewLess;
    final unread = hiddenUnread;
    if (unread == null) return context.l10n.chatViewMore(hidden);
    final read = hidden - unread;
    return unread > 0
        ? context.l10n.chatViewUnreadAndRead(unread, read)
        : context.l10n.chatViewRead(read);
  }

  @override
  Widget build(BuildContext context) => DReferenceTextScale(
    child: MergeSemantics(
      child: Semantics(
        expanded: expanded,
        child: DButton(
          variant: DButtonVariant.ghost,
          size: DControlSize.filter,
          alignment: AlignmentDirectional.centerStart,
          foregroundColor: DTokens.of(context).mutedForeground,
          semanticLabel: _label(context),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DSpacing.controlGap,
            children: [
              SizedBox(
                width: compact ? 32 : 40,
                child: RotatedBox(
                  quarterTurns: expanded ? 2 : 0,
                  child: const DIcon(DIcons.chevronDown),
                ),
              ),
              Flexible(child: Text(_label(context))),
            ],
          ),
          onPressed: onPressed,
        ),
      ),
    ),
  );
}
