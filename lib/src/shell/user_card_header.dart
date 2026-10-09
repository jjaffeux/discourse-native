import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/user_card.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'user_status.dart';

/// Identity shared by the profile card and its status editor preview.
class UserCardHeader extends StatelessWidget {
  const UserCardHeader({
    super.key,
    required this.card,
    required this.siteUrl,
    this.statusContent,
  });

  final UserCard card;
  final String siteUrl;
  final Widget? statusContent;
  static const double avatarSize = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One reading for the whole card: a suspension that lapses between two
    // reads would open the badge row and then draw nothing in it.
    final suspended = card.isSuspendedAt(DateTime.now());
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 48),
          child:
              statusContent ??
              LayoutBuilder(
                builder: (context, constraints) => UserStatusMessage(
                  siteUrl: siteUrl,
                  userId: card.id,
                  status: card.status,
                  showDescription: true,
                  asBubble: true,
                  size: 15,
                  descriptionMaxWidth: (constraints.maxWidth - 42).clamp(
                    0,
                    double.infinity,
                  ),
                ),
              ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DAvatar.frame(
              child: SizedBox.square(
                dimension: avatarSize,
                child: AvatarImage(
                  url: card.avatarUrl,
                  size: avatarSize,
                  fallback: ColoredBox(
                    color: theme.shell.panel,
                    child: Center(
                      child: Text(
                        card.username.isEmpty
                            ? '?'
                            : card.username.characters.first.toUpperCase(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '@${card.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (card.title case final title?)
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  if (card.isStaff || suspended) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (card.isStaff)
                          DBadge(
                            variant: DBadgeVariant.secondary,
                            child: Text(
                              card.isAdmin
                                  ? context.l10n.admin
                                  : card.isModerator
                                  ? context.l10n.moderator
                                  : context.l10n.staffChatmessagetile,
                            ),
                          ),
                        if (suspended)
                          DBadge(
                            variant: DBadgeVariant.destructive,
                            child: Text(context.l10n.suspended),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
    final content = Padding(padding: const EdgeInsets.all(16), child: identity);
    if (card.cardBackgroundUrl == null) return content;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    card.cardBackgroundUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          DTokens.of(context).background.withValues(alpha: .55),
                          DTokens.of(context).background.withValues(alpha: 1),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        content,
      ],
    );
  }
}
