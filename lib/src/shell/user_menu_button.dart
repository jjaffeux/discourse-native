import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/user_status.dart';
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

class UserMenuButton extends StatefulWidget {
  const UserMenuButton({super.key, this.size = 30, this.ringColor});

  final double size;

  final Color? ringColor;

  static const Key bellKey = ValueKey('user-menu-bell');

  static const Key avatarKey = ValueKey('user-menu-avatar');

  static const Key signUpKey = ValueKey('user-menu-sign-up');
  static const Key signInKey = ValueKey('user-menu-sign-in');

  static const Key unreadDotKey = ValueKey('user-menu-unread');

  @override
  State<UserMenuButton> createState() => _UserMenuButtonState();
}

class _UserMenuButtonState extends State<UserMenuButton> {
  final _notifications = DPopoverController();
  final _profile = DPopoverController();

  @override
  void dispose() {
    _notifications.dispose();
    _profile.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final controller = ShellScope.read(context);
    await controller.connectCurrentInstance();

    if (!mounted || !identical(ShellScope.read(context), controller)) return;
    final error = controller.connectError;
    if (error == null) return;
    DToast.show(context, error, type: DToastType.error);
  }

  Future<void> _signUp(String siteUrl) async {
    final opened = await openExternalLink('$siteUrl/signup');
    if (!mounted || opened) return;
    DToast.show(
      context,
      'Could not open the sign-up page.',
      type: DToastType.error,
    );
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
          final unreadCount =
              controller.accountActivity.totalsFor(siteUrl)?.coreBadge ?? 0;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AccountMenuPopover(
                view: UserMenuView.notifications,
                controller: _notifications,
                onOpen: _profile.close,
                connecting: connecting,
                tooltip: 'Notifications',
                semanticLabel: unreadCount > 0
                    ? 'Notifications, $unreadCount unread ${unreadCount == 1 ? 'item' : 'items'}'
                    : 'Notifications',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const DIcon(DIcons.bell, size: 20),
                    if (unreadCount > 0 && !connecting)
                      PositionedDirectional(
                        top: -10,
                        end: -12,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: DBadge(
                              key: UserMenuButton.unreadDotKey,
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AccountMenuPopover(
                view: UserMenuView.profile,
                controller: _profile,
                onOpen: _notifications.close,
                connecting: connecting,
                tooltip: 'Profile',
                semanticLabel:
                    '${account.displayName ?? account.username}, Profile',
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserMenuAvatar(
                      avatarUrl: account.avatarUrl,
                      initial: account.username?.characters.first.toUpperCase(),
                      connecting: connecting,
                      size: widget.size,
                    ),
                    if (account.userStatus != null && !connecting)
                      PositionedDirectional(
                        end: -5,
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
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _AccountMenuPopover extends StatelessWidget {
  const _AccountMenuPopover({
    required this.view,
    required this.controller,
    required this.onOpen,
    required this.connecting,
    required this.tooltip,
    required this.semanticLabel,
    required this.icon,
  });

  final UserMenuView view;
  final DPopoverController controller;
  final VoidCallback onOpen;
  final bool connecting;
  final String tooltip;
  final String semanticLabel;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    Widget buildTrigger(BuildContext context, DPopoverTriggerState trigger) =>
        DButton.iconOnly(
          key: view == UserMenuView.profile
              ? UserMenuButton.avatarKey
              : UserMenuButton.bellKey,
          icon: ExcludeSemantics(child: icon),
          tooltip: connecting ? 'Connecting…' : tooltip,
          semanticLabel: semanticLabel,
          variant: DButtonVariant.ghost,
          size: DButtonSize.large,
          hasPopup: true,
          expanded: trigger.open,
          focusNode: trigger.focusNode,
          onPressed: connecting
              ? null
              : () {
                  onOpen();
                  if (context.isTouch) {
                    unawaited(showUserMenuSheet(context, view: view));
                  } else {
                    trigger.toggle();
                  }
                },
        );
    if (view == UserMenuView.profile && !context.isTouch) {
      return DDropdownMenu(
        controller: controller,
        content: DDropdownMenuContent(
          semanticLabel: 'Profile',
          align: DPopoverAlign.end,
          width: 260,
          children: [UserProfileMenuItems(onDismiss: controller.close)],
        ),
        child: DDropdownMenuTrigger(builder: buildTrigger),
      );
    }
    return DPopover(
      controller: controller,
      content: DPopoverContent(
        semanticLabel: tooltip,
        align: DPopoverAlign.end,
        sideOffset: 6,
        collisionPadding: UserMenuPanel.margin,
        width: UserMenuPanel.width,
        padding: EdgeInsets.zero,
        scrollable: false,
        child: UserMenuPanel(onDismiss: controller.close),
      ),
      child: DPopoverTrigger(builder: buildTrigger),
    );
  }
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
          DTooltip(
            message: 'Sign up',
            labelTrigger: true,
            child: IconButton.filled(
              key: UserMenuButton.signUpKey,
              onPressed: connecting ? null : onSignUp,
              tooltip: '',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const DIcon(DIcons.userPlus, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          DTooltip(
            message: connecting ? 'Signing in…' : 'Sign in',
            labelTrigger: true,
            child: IconButton.filled(
              key: UserMenuButton.signInKey,
              onPressed: connecting ? null : onSignIn,
              tooltip: '',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: connecting
                  ? const SizedBox.square(dimension: 16, child: DSpinner())
                  : const DIcon(DIcons.user, size: 16),
            ),
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
              ? const SizedBox.square(dimension: 16, child: DSpinner())
              : const DIcon(DIcons.user, size: 16),
          label: Text(connecting ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}
