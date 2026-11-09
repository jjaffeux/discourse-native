import 'package:discourse_native/src/foundation/icons/d_icon_data.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `find.byIcon` for [DIcon].
///
/// The icons are SVG rather than font glyphs, so `byIcon` — which matches on
/// [Icon.icon] — cannot see them.
extension DIconFinders on CommonFinders {
  Finder dIcon(DIconData icon) => byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == icon,
    description: 'DIcon(${icon.name})',
  );
}

/// The More or Less row, whichever the sidebar is drawing.
final Finder sidebarMoreToggle = find.byKey(
  const ValueKey('sidebar-more-toggle'),
);

/// The labels of the rows More gave way to, in order: everything from its
/// first destination down to the Less row beneath them.
List<String> sidebarMoreLabels(WidgetTester tester) {
  if (find.text('Less').evaluate().isEmpty) return const [];
  final foot = tester.getTopLeft(sidebarMoreToggle).dy;
  return find
      .descendant(
        of: find.byType(InstanceSidebar),
        matching: find.byType(SidebarDestinationTile),
      )
      .evaluate()
      .where(
        (row) =>
            (row.renderObject! as RenderBox).localToGlobal(Offset.zero).dy <
            foot,
      )
      .map((row) => (row.widget as SidebarDestinationTile).destination)
      .skipWhile((destination) => destination.id != 'all-categories')
      .map((destination) => destination.label)
      .toList();
}
