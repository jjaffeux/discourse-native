import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

/// A section's visible rows and the count behind its expansion action.
final class ChatInboxSectionSlice<T> {
  ChatInboxSectionSlice(
    List<T> items, {
    required bool expanded,
    required bool alone,
    bool Function(T item)? keep,
  }) : canFold = !alone && items.length > 5 {
    var shown = expanded || !canFold ? items : items.take(4).toList();
    if (!expanded && canFold && keep != null) {
      final held = items.where(keep).firstOrNull;
      if (held != null && !shown.contains(held)) shown = [...shown, held];
    }
    visible = shown;
    hidden = items.length - shown.length;
  }

  final bool canFold;
  late final List<T> visible;
  late final int hidden;
}

class ChatInboxMore extends StatelessWidget {
  const ChatInboxMore({
    super.key,
    required this.hidden,
    required this.expanded,
    required this.onPressed,
    this.compact = false,
  });

  final int hidden;
  final bool expanded;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      expanded: expanded,
      child: DButton(
        variant: DButtonVariant.ghost,
        size: DControlSize.filter,
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: DTokens.of(context).mutedForeground,
        semanticLabel: expanded
            ? context.l10n.chatViewLess
            : context.l10n.chatViewMore(hidden),
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
            Flexible(
              child: Text(
                expanded
                    ? context.l10n.chatViewLess
                    : context.l10n.chatViewMore(hidden),
              ),
            ),
          ],
        ),
        onPressed: onPressed,
      ),
    ),
  );
}
