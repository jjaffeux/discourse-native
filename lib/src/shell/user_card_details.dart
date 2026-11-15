import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/calendar_day.dart';

/// A labelled fact about a person, such as when they joined.
class UserCardMetadata extends StatelessWidget {
  const UserCardMetadata({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextSpan(text: value),
            ],
          ),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A person's website or location; a website opens when pressed.
class UserCardDetail extends StatelessWidget {
  const UserCardDetail({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(
          data: IconThemeData(color: color),
          child: icon,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return child;
    return DItem(
      fitContent: true,
      size: DItemSize.artwork,
      highlightOnInteraction: false,
      link: true,
      onPressed: onTap!,
      semanticLabel: label,
      children: [ExcludeSemantics(child: child)],
    );
  }
}

String userCardMonth(DateTime when) {
  final day = calendarDay(when)!;
  return '${shortMonthName(day.month)} ${day.year}';
}

String userCardWebsiteLabel(String website) {
  final uri = Uri.tryParse(website);
  if (uri?.host case final String host when host.isNotEmpty) {
    return '${host.startsWith('www.') ? host.substring(4) : host}${uri!.path == '/' ? '' : uri.path}';
  }
  return website;
}
