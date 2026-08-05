import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/discourse_user.dart';
import '../theme/app_theme.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

/// The account card floating at the bottom of the rail and the sidebar.
///
/// It is drawn *over* those columns rather than below them — they run to the
/// bottom edge behind it — so this widget paints no background of its own and
/// the columns show through its margins. [AdaptiveShell] stacks it; the columns
/// reserve [reservedHeight] so their contents stay clear of it.
///
/// Placeholder until there is an authenticated user to show.
class UserBar extends StatelessWidget {
  const UserBar({super.key});

  /// Identifies the card itself, as opposed to the full-width slot it sits in.
  static const Key cardKey = ValueKey('user-bar-card');

  static const double cardHeight = 52;
  static const double margin = 8;

  /// Horizontal inset on iOS. The default [margin] leaves the card stretching
  /// nearly the full width of a phone screen, where it reads as a toolbar
  /// rather than something floating; desktop windows are wide enough that it
  /// already looks inset at [margin].
  static const double iosHorizontalMargin = 20;

  static double _horizontalMargin(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.iOS
      ? iosHorizontalMargin
      : margin;

  /// Most the card lifts itself off the bottom edge for the home indicator.
  ///
  /// Honouring the full system inset (20pt on iPad, 34pt on a phone) leaves the
  /// card visibly stranded above the edge, unlike on desktop where it sits at
  /// [margin]. Capping it keeps the same hugging-the-bottom look everywhere
  /// while staying clear of the indicator itself.
  static const double maxBottomInset = 12;

  static double _bottomInset(BuildContext context) =>
      math.min(MediaQuery.paddingOf(context).bottom, maxBottomInset);

  /// Vertical space the card covers, including the inset it absorbs.
  static double reservedHeight(BuildContext context) =>
      cardHeight + margin * 2 + _bottomInset(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);
    final instance = controller.currentInstance;
    final user = instance?.user;

    final String title;
    final String subtitle;
    if (controller.connecting) {
      title = 'Connecting…';
      subtitle = instance?.host ?? '';
    } else if (user != null) {
      title = user.displayName;
      subtitle = instance!.host;
    } else {
      title = 'Not signed in';
      subtitle = instance == null
          ? 'Add a site to begin'
          : controller.connectError ?? 'Tap to connect';
    }

    return SafeArea(
      top: false,
      right: false,
      // Bottom is handled below so the card can sit lower than the full inset.
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _horizontalMargin(context),
          0,
          _horizontalMargin(context),
          margin + _bottomInset(context),
        ),
        child: Material(
          key: cardKey,
          color: theme.shell.floating,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: InkWell(
            onTap: instance == null || controller.connecting
                ? null
                : () => user == null
                      ? controller.connectCurrentInstance()
                      : _showAccountSheet(context),
            child: SizedBox(
              height: cardHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _Avatar(user: user, connecting: controller.connecting),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: controller.connectError != null
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        tooltip: 'Settings',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The connected user's avatar, a spinner while connecting, or a neutral
/// placeholder when signed out.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.connecting});

  final DiscourseUser? user;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (connecting) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final avatarUrl = user?.avatarUrl;
    return CircleAvatar(
      radius: 15,
      backgroundColor: user == null
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primary,
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      child: user == null
          ? Icon(
              Icons.person_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Text(
              user!.username.characters.first.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// Account actions for a connected site.
Future<void> _showAccountSheet(BuildContext context) {
  final controller = ShellScope.of(context);
  final instance = controller.currentInstance;
  final user = instance?.user;
  if (instance == null || user == null) return Future.value();

  return showShellSheet<void>(
    context: context,
    title: user.displayName,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Connected to ${instance.host} as @${user.username}.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            controller.disconnectCurrentInstance();
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Disconnect'),
        ),
      ],
    ),
  );
}
