import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// Applies the Native shared scroll policy to the mobile header and dock.
class MobileScrollDock extends StatelessWidget {
  const MobileScrollDock({
    super.key,
    required this.body,
    required this.dockBuilder,
    required this.identity,
    this.visible = true,
    this.hideOnScroll = true,
    this.keepActionVisible = false,
    this.floating = true,
  });

  final Widget body;

  /// The argument lets a composer hide destinations while keeping its action row.
  final Widget Function(bool hidden) dockBuilder;
  final Object identity;
  final bool visible;
  final bool hideOnScroll;

  /// An active composer must keep its Send/Save action reachable.
  final bool keepActionVisible;
  final bool floating;

  @override
  Widget build(BuildContext context) => DScrollChrome(
    identity: identity,
    visible: visible,
    enabled: hideOnScroll,
    keepFooterVisible: keepActionVisible,
    floatingFooter: floating,
    footerBuilder: (hidden) =>
        dockBuilder(floating ? hidden : hidden && keepActionVisible),
    child: body,
  );
}
