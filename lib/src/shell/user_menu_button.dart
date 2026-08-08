import 'dart:async';

import 'package:flutter/material.dart';

import 'platform.dart';
import 'shell_scope.dart';
import 'user_menu.dart';

typedef _AccountAvatarSnapshot = ({
  String? siteUrl,
  String? avatarUrl,
  String? username,
  String? displayName,
  bool connecting,
});

/// The account avatar in the top right of whichever column reaches the top
/// right of the window, and the way into [UserMenuPanel].
///
/// It stands in for the whole of the signed-in state: signed out it is the way
/// to connect, connecting it is the progress, and connected it opens the menu.
/// A pointer gets that menu as a popover under the avatar; a thumb gets it as a
/// sheet, because a popover pinned to the corner of a phone is a menu you have
/// to reach across the screen to read.
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

  /// The dot saying there is something waiting behind the menu.
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
        siteUrl: instance?.url,
        avatarUrl: user?.avatarUrl,
        username: user?.username,
        displayName: user?.displayName,
        connecting: controller.connecting,
      );
    },
    builder: (context, account, _) {
      final siteUrl = account.siteUrl;
      if (siteUrl == null) return const SizedBox.shrink();
      final controller = ShellScope.read(context);

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final connecting = account.connecting;

          // What the menu itself counts, which is things addressed to this account —
          // notifications, messages, chat, the review queue. Kept live by the site's
          // own `/notification/` channel, so it appears without the menu being
          // opened or the app being relaunched.
          final unread =
              (controller.accountActivity.totalsFor(siteUrl)?.badge ?? 0) > 0;

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
                // A dot rather than the number the web shows: the rail already
                // carries the count for every site, and repeating it here would
                // say the same thing twice at two different sizes.
                if (unread && !connecting)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: _UnreadDot(ringColor: widget.ringColor),
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
            ),
            menuChildren: [UserMenuPanel(onDismiss: _menu.close)],
            child: Tooltip(
              message: connecting
                  ? 'Connecting…'
                  : account.displayName ?? 'Not signed in',
              child: InkWell(
                key: UserMenuButton.avatarKey,
                onTap: connecting
                    ? null
                    : (account.username == null ? _connect : _openMenu),
                borderRadius: BorderRadius.circular(20),
                child: avatar,
              ),
            ),
          );
        },
      );
    },
  );
}

/// The unread mark on the avatar. Sized and coloured like the rail's badge, so
/// the two read as the same signal at two levels of detail.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({this.ringColor});

  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ring = ringColor;

    return Container(
      key: UserMenuButton.unreadDotKey,
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring, width: 2),
      ),
    );
  }
}
