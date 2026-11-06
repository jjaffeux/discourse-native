import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar's Notifications place, fixed before the action once signed in. A
/// phone's header has no bell: this place is how a person opens the
/// notifications menu there, and pressing it again puts the menu away.
final dockNotifications = find.byKey(
  const ValueKey('mobile-mode-notifications'),
);

/// What opens the notifications menu in the shell on screen: the bar's
/// Notifications place on a phone, and the header's bell on a desktop.
Finder notificationsMenuTrigger() =>
    find.byType(MobileForumRoot).evaluate().isEmpty
    ? find.byKey(UserMenuButton.bellKey)
    : dockNotifications;
