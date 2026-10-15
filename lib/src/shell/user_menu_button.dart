import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/user_status.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'desktop_header_menu.dart';
import 'external_link.dart';
import 'header_notification_button.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu.dart';
import 'user_status.dart';

typedef _AccountAvatarSnapshot = ({
  bool showAccountControls,
  String? siteUrl,
  Object? session,
  String? avatarUrl,
  String? username,
  String? displayName,
  int? userId,
  UserStatus? userStatus,
  bool connecting,
});

class UserMenuButton extends StatefulWidget {
  const UserMenuButton({
    super.key,
    this.ringColor,
    this.compact = false,
    this.leadingActions,
  });

  final Color? ringColor;

  final bool compact;

  /// Header shortcuts share the notification group's inner spacing.
  final List<Widget>? leadingActions;

  static const Key bellKey = ValueKey('user-menu-bell');

  static const Key avatarKey = ValueKey('user-menu-avatar');

  static const Key signUpKey = ValueKey('user-menu-sign-up');
  static const Key signInKey = ValueKey('user-menu-sign-in');

  static const Key unreadDotKey = ValueKey('user-menu-unread');

  @override
  State<UserMenuButton> createState() => _UserMenuButtonState();
}

typedef _AccountMenuOwner = ({
  ShellRootMode rootMode,
  String? siteUrl,
  int? userId,
  Object? session,
});

class _UserMenuButtonState extends State<UserMenuButton> {
  final _notifications = DPopoverController();
  final _profile = DPopoverController();
  _AccountMenuOwner? _menuOwner;
  var _menuGeneration = 0;
  ShellController? _shell;

  _AccountMenuOwner _owner(ShellController shell) {
    final instance = shell.currentInstance;
    return (
      rootMode: shell.rootMode,
      siteUrl: instance?.url,
      userId: instance?.user?.id,
      session: instance == null
          ? null
          : shell.lifecycle.capture(instance.url).session,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (identical(shell, _shell)) return;
    _shell?.removeListener(_handleShellChanged);
    _shell = shell;
    shell.addListener(_handleShellChanged);
    _handleShellChanged();
  }

  void _handleShellChanged() {
    final owner = _owner(_shell!);
    if (_menuOwner == owner) return;
    final previous = _menuOwner;
    final retired =
        previous != null &&
        (previous.rootMode != owner.rootMode ||
            previous.siteUrl == owner.siteUrl &&
                (previous.userId != owner.userId ||
                    previous.session != owner.session));
    if (retired) {
      // Site navigation keeps the selected menu section. A retired account
      // removes its content before the dismissal animation can reload it.
      _menuGeneration++;
      _notifications.close();
      _profile.close();
    }
    _menuOwner = owner;
  }

  @override
  void dispose() {
    _shell?.removeListener(_handleShellChanged);
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
      appL10n.couldNotOpenTheSignUpPage,
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
        session: instance == null
            ? null
            : controller.lifecycle.capture(instance.url).session,
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
          onSignUp: () => unawaited(_signUp(siteUrl)),
          onSignIn: () => unawaited(_connect()),
        );
      }
      final controller = ShellScope.read(context);

      return ListenableBuilder(
        listenable: controller.accountActivity.totalsListenable,
        builder: (context, _) {
          final connecting = account.connecting;
          final totals = controller.accountActivity.totalsFor(siteUrl);
          final unreadCount = totals?.coreBadge ?? 0;
          return Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: context.isTouch ? DSpacing.controlGap : 10,
            runSpacing: 10,
            children: [
              Padding(
                padding: widget.leadingActions != null && !context.isTouch
                    ? const EdgeInsets.symmetric(horizontal: 1, vertical: 4)
                    : EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...?widget.leadingActions,
                    _AccountMenuPopover(
                      key: ValueKey((
                        UserMenuView.notifications,
                        _menuGeneration,
                      )),
                      view: UserMenuView.notifications,
                      controller: _notifications,
                      onOpen: _profile.close,
                      connecting: connecting,
                      tooltip: context.l10n.notifications,
                      semanticLabel: unreadCount > 0
                          ? context.l10n.notificationsUnread(unreadCount)
                          : context.l10n.notifications,
                      notificationCount: unreadCount,
                      notificationColor: theme.discourse.notificationIndicator,
                      notificationSurface:
                          widget.ringColor ?? theme.shell.content,
                      icon: DIcon(DIcons.bell, size: context.isTouch ? 20 : 17),
                      compact: widget.compact,
                    ),
                  ],
                ),
              ),
              _AccountMenuPopover(
                key: context.isTouch
                    ? null
                    : ValueKey((UserMenuView.profile, _menuGeneration)),
                view: UserMenuView.profile,
                controller: _profile,
                onOpen: _notifications.close,
                connecting: connecting,
                tooltip: context.l10n.profile,
                semanticLabel: context.l10n.profileUsermenubutton(
                  (account.displayName ?? account.username).toString(),
                ),
                icon: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    UserMenuAvatar(
                      avatarUrl: account.avatarUrl,
                      initial: account.username?.characters.first.toUpperCase(),
                      connecting: connecting,
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
                compact: widget.compact,
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
    super.key,
    required this.view,
    required this.controller,
    required this.onOpen,
    required this.connecting,
    required this.tooltip,
    required this.semanticLabel,
    required this.icon,
    required this.compact,
    this.notificationCount = 0,
    this.notificationColor,
    this.notificationSurface,
  });

  final UserMenuView view;
  final DPopoverController controller;
  final VoidCallback onOpen;
  final bool connecting;
  final String tooltip;
  final String semanticLabel;
  final Widget icon;
  final bool compact;
  final int notificationCount;
  final Color? notificationColor;
  final Color? notificationSurface;

  @override
  Widget build(BuildContext context) {
    void activate(BuildContext context, DPopoverTriggerState trigger) {
      onOpen();
      trigger.toggle();
    }

    Widget buildTrigger(BuildContext context, DPopoverTriggerState trigger) {
      final isProfile = view == UserMenuView.profile;
      final tokens = DTokens.of(context);
      if (notificationCount > 0 && !connecting) {
        return headerNotificationButton(
          context,
          key: UserMenuButton.bellKey,
          countKey: UserMenuButton.unreadDotKey,
          icon: icon,
          count: notificationCount,
          color: notificationColor!,
          surface: notificationSurface!,
          tooltip: tooltip,
          semanticLabel: semanticLabel,
          focusNode: trigger.focusNode,
          hasPopup: true,
          expanded: trigger.open,
          overlayCount: true,
          size: compact ? DButtonSize.regular : DButtonSize.large,
          onPressed: () => activate(context, trigger),
        );
      }
      return DButton.iconOnly(
        key: isProfile ? UserMenuButton.avatarKey : UserMenuButton.bellKey,
        icon: ExcludeSemantics(child: icon),
        tooltip: connecting ? context.l10n.connecting : tooltip,
        semanticLabel: semanticLabel,
        variant: !isProfile && trigger.open
            ? DButtonVariant.primary
            : DButtonVariant.ghost,
        density: isProfile
            ? DButtonDensity.avatar
            : context.isTouch
            ? DButtonDensity.standard
            : DButtonDensity.header,
        size: compact || isProfile ? DButtonSize.regular : DButtonSize.large,
        shape: DButtonShape.pill,
        backgroundColor: isProfile ? Colors.transparent : null,
        interactiveBackgroundColor: isProfile ? Colors.transparent : null,
        // The mockup uses --border (22%), rather than the divider's subtle 12%.
        borderColor: isProfile
            ? Color.lerp(tokens.background, tokens.foreground, .22)
            : null,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: connecting ? null : () => activate(context, trigger),
      );
    }

    if (view == UserMenuView.profile) {
      // Header SafeArea has consumed the local padding. Placement still needs
      // the physical view's safe area so large menus avoid the home indicator.
      final media = MediaQueryData.fromView(View.of(context));
      return DDropdownMenu(
        controller: controller,
        sheetOnMobile: true,
        mobileSheetVariant: DSheetVariant.adaptiveMenu,
        content: DDropdownMenuContent(
          semanticLabel: context.l10n.profile,
          align: DPopoverAlign.end,
          sideOffset: 8,
          collisionBoundary: Rect.fromLTRB(
            media.padding.left,
            media.padding.top,
            media.size.width - media.padding.right,
            media.size.height - media.padding.bottom - media.viewInsets.bottom,
          ),
          width: 216,
          padding: const EdgeInsets.all(7),
          variant: DPopoverVariant.timeline,
          highlightInitialFocus: false,
          children: [UserProfileMenuItems(onDismiss: controller.close)],
        ),
        child: DDropdownMenuTrigger(builder: buildTrigger),
      );
    }
    if (view == UserMenuView.notifications) {
      final media = MediaQueryData.fromView(View.of(context));
      return DDropdownMenu(
        controller: controller,
        sheetOnMobile: true,
        mobileSheetVariant: DSheetVariant.adaptiveMenu,
        mobileSheetFloatOnContentEnd: false,
        content: DDropdownMenuContent(
          semanticLabel: tooltip,
          align: DPopoverAlign.end,
          width: MediaQuery.sizeOf(context).width < 600
              ? UserMenuPanel.mobileWidth
              : DesktopHeaderMenu.width,
          sideOffset: 8,
          collisionPadding: 0,
          collisionBoundary: Rect.fromLTRB(
            media.padding.left + 12,
            media.padding.top + 6,
            media.size.width - media.padding.right - 12,
            media.size.height -
                media.padding.bottom -
                media.viewInsets.bottom -
                6,
          ),
          cornerRadius: 12,
          variant: DPopoverVariant.timeline,
          padding: EdgeInsets.zero,
          scrollable: false,
          autofocus: false,
          children: [UserMenuPanel(onDismiss: controller.close)],
        ),
        child: DDropdownMenuTrigger(builder: buildTrigger),
      );
    }
    return DPopover(
      controller: controller,
      focusContentOnOpen: false,
      content: DPopoverContent(
        semanticLabel: tooltip,
        align: DPopoverAlign.end,
        sideOffset: 6,
        collisionPadding: UserMenuPanel.margin,
        width: MediaQuery.sizeOf(context).width < 600
            ? UserMenuPanel.mobileWidth
            : UserMenuPanel.width,
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
    required this.onSignUp,
    required this.onSignIn,
  });

  final bool connecting;
  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 900) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            key: UserMenuButton.signUpKey,
            onPressed: connecting ? null : onSignUp,
            tooltip: context.l10n.signUp,
            size: DButtonSize.large,
            icon: const DIcon(DIcons.userPlus),
          ),
          const SizedBox(width: DSpacing.controlGap),
          DButton.iconOnly(
            key: UserMenuButton.signInKey,
            onPressed: connecting ? null : onSignIn,
            tooltip: context.l10n.signIn,
            size: DButtonSize.large,
            icon: const DIcon(DIcons.user),
            loading: connecting,
            loadingSemanticLabel: context.l10n.signingIn,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DButton(
          key: UserMenuButton.signUpKey,
          onPressed: connecting ? null : onSignUp,
          size: DButtonSize.large,
          label: Text(context.l10n.signUp),
        ),
        const SizedBox(width: DSpacing.controlGap),
        DButton(
          key: UserMenuButton.signInKey,
          onPressed: connecting ? null : onSignIn,
          size: DButtonSize.large,
          icon: const DIcon(DIcons.user),
          label: Text(context.l10n.signIn),
          loading: connecting,
          loadingLabel: Text(context.l10n.signingIn),
          loadingSemanticLabel: context.l10n.signingIn,
        ),
      ],
    );
  }
}
