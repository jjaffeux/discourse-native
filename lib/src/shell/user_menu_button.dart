import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_status.dart';
import '../theme/app_theme.dart';
import '../theme/color_contrast.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu.dart';
import 'user_status.dart';

typedef _AccountAvatarSnapshot = ({
  bool showAccountControls,
  String? siteUrl,
  String? avatarUrl,
  String? username,
  String? displayName,
  int? userId,
  UserStatus? userStatus,
  bool connecting,
});

/// The account controls in the top right of whichever column reaches the top
/// right of the window, and the way into [UserMenuPanel].
///
/// Signed-out readers get explicit sign-up and sign-in actions. Once connected,
/// the avatar opens the menu: a pointer gets a popover under it, while a thumb
/// gets a sheet because a popover pinned to a phone corner is awkward to read.
class UserMenuButton extends StatefulWidget {
  const UserMenuButton({super.key, this.size = 30, this.ringColor});

  /// Diameter of the avatar. Smaller in the title bar, which is only as tall
  /// as the traffic lights beside it.
  final double size;

  /// The surface this sits on, which the unread dot rings itself in so it
  /// reads as separate from the avatar underneath it.
  ///
  /// Passed in rather than looked up because the two places the avatar appears
  /// sit on different colors — the window strip and a column header — and
  /// nothing can ask Flutter what is painted behind it.
  final Color? ringColor;

  /// The tappable avatar itself.
  static const Key avatarKey = ValueKey('user-menu-avatar');

  static const Key signUpKey = ValueKey('user-menu-sign-up');
  static const Key signInKey = ValueKey('user-menu-sign-in');

  /// The count saying there is something waiting behind the menu.
  static const Key unreadDotKey = ValueKey('user-menu-unread');

  @override
  State<UserMenuButton> createState() => _UserMenuButtonState();
}

class _UserMenuButtonState extends State<UserMenuButton> {
  final MenuController _menu = MenuController();

  /// Signing in happens in a browser we do not own, so the failure comes back
  /// long after the tap and has nowhere in the shell to live. A snack bar is
  /// what is left once the account card that used to carry it is gone.
  Future<void> _connect() async {
    final controller = ShellScope.read(context);
    final messenger = ScaffoldMessenger.of(context);

    await controller.connectCurrentInstance();

    if (!mounted || !identical(ShellScope.read(context), controller)) return;
    final error = controller.connectError;
    if (error == null) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _signUp(String siteUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await openExternalLink('$siteUrl/signup');
    if (!mounted || opened) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open the sign-up page.')),
    );
  }

  void _openMenu() {
    if (context.isTouch) {
      unawaited(showUserMenuSheet(context));
      return;
    }
    _menu.isOpen ? _menu.close() : _menu.open();
  }

  @override
  Widget build(BuildContext context) => ShellSelector<_AccountAvatarSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      final user = instance?.user;
      return (
        showAccountControls: controller.rootMode == ShellRootMode.forum,
        siteUrl: instance?.url,
        avatarUrl: user?.avatarUrl,
        username: user?.username,
        displayName: user?.displayName,
        userId: user?.id,
        userStatus: user?.status,
        connecting: controller.connecting,
      );
    },
    builder: (context, account, _) {
      final theme = Theme.of(context);
      if (!account.showAccountControls) return const SizedBox.shrink();
      final siteUrl = account.siteUrl;
      if (siteUrl == null) return const SizedBox.shrink();
      if (account.username == null) {
        return _SignedOutAccountActions(
          connecting: account.connecting,
          size: widget.size,
          onSignUp: () => unawaited(_signUp(siteUrl)),
          onSignIn: () => unawaited(_connect()),
        );
      }
      final controller = ShellScope.read(context);

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final connecting = account.connecting;

          // What the menu itself counts, which is things addressed to this account —
          // notifications, messages, chat, the review queue. Kept live by the site's
          // own `/notification/` channel, so it appears without the menu being
          // opened or the app being relaunched.
          final unreadCount =
              controller.accountActivity.totalsFor(siteUrl)?.badge ?? 0;
          final badgeBackground = theme.discourse.success;
          final badgeForeground = contrastSafeForeground(
            background: badgeBackground,
            backdrop: widget.ringColor ?? theme.scaffoldBackgroundColor,
            // Core draws high-priority counts with `--secondary` on
            // `--success`. These are the native equivalents for the current
            // forum's resolved palette.
            preferred: [theme.colorScheme.surface, theme.colorScheme.onSurface],
          );

          final tooltip = connecting
              ? 'Connecting…'
              : account.displayName ?? 'Not signed in';
          final semanticLabel = unreadCount > 0 && !connecting
              ? '$tooltip, $unreadCount unread '
                    '${unreadCount == 1 ? 'item' : 'items'}'
              : tooltip;

          final avatar = Padding(
            padding: const EdgeInsets.all(5),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserMenuAvatar(
                  avatarUrl: account.avatarUrl,
                  initial: account.username?.characters.first.toUpperCase(),
                  connecting: connecting,
                  size: widget.size,
                ),
                if (account.userStatus != null && !connecting)
                  Positioned(
                    right: -5,
                    bottom: -4,
                    child: UserStatusMessage(
                      siteUrl: siteUrl,
                      userId: account.userId,
                      status: account.userStatus,
                      size: 13,
                      badgeBackgroundColor:
                          widget.ringColor ?? theme.scaffoldBackgroundColor,
                      badgePadding: 2,
                    ),
                  ),
                // Core puts the count in a padded badge beside the avatar.
                // Keep the native header equally legible even though the rail
                // repeats the same total at the cross-forum level.
                if (unreadCount > 0 && !connecting)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: _UnreadBadge(
                      count: unreadCount,
                      background: badgeBackground,
                      foreground: badgeForeground,
                      ringColor:
                          widget.ringColor ?? theme.scaffoldBackgroundColor,
                    ),
                  ),
              ],
            ),
          );

          return MenuAnchor(
            controller: _menu,
            alignmentOffset: const Offset(0, 6),
            // The panel draws its own surface, so that it can hold a margin
            // between itself and the window edges the overlay would pin it to.
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
              shadowColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              side: WidgetStatePropertyAll(BorderSide.none),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            ),
            menuChildren: [UserMenuPanel(onDismiss: _menu.close)],
            child: Semantics(
              container: true,
              button: !connecting,
              enabled: !connecting,
              label: semanticLabel,
              child: Tooltip(
                message: tooltip,
                excludeFromSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: UserMenuButton.avatarKey,
                    onTap: connecting ? null : _openMenu,
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(
                      theme.discourseButtons.borderRadius,
                    ),
                    hoverColor: Colors.transparent,
                    focusColor: theme.shell.hover,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: ExcludeSemantics(child: avatar),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _SignedOutAccountActions extends StatelessWidget {
  const _SignedOutAccountActions({
    required this.connecting,
    required this.size,
    required this.onSignUp,
    required this.onSignIn,
  });

  final bool connecting;
  final double size;
  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final height = size + 6;
    if (MediaQuery.sizeOf(context).width < 900) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            key: UserMenuButton.signUpKey,
            onPressed: connecting ? null : onSignUp,
            tooltip: 'Sign up',
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const DIcon(DIcons.userPlus, size: 16),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            key: UserMenuButton.signInKey,
            onPressed: connecting ? null : onSignIn,
            tooltip: connecting ? 'Signing in…' : 'Sign in',
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: connecting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const DIcon(DIcons.user, size: 16),
          ),
        ],
      );
    }
    final style = FilledButton.styleFrom(
      minimumSize: Size(0, height),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          key: UserMenuButton.signUpKey,
          onPressed: connecting ? null : onSignUp,
          style: style,
          child: const Text('Sign up'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: UserMenuButton.signInKey,
          onPressed: connecting ? null : onSignIn,
          style: style,
          icon: connecting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const DIcon(DIcons.user, size: 16),
          label: Text(connecting ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}

/// The unread count on the avatar, following core's compact notification pill.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
    required this.background,
    required this.foreground,
    required this.ringColor,
  });

  final int count;
  final Color background;
  final Color foreground;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: UserMenuButton.unreadDotKey,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ringColor, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
