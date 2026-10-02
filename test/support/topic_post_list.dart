import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

typedef TopicPostListHandle = ({
  ScrollController? controller,
  ListController? listController,
  EdgeInsetsGeometry? padding,
  Key? key,
});

Finder topicPostListFinder() => find.ancestor(
  of: find.descendant(
    of: find.byType(TopicView),
    matching: find.bySubtype<SuperSliverList>(),
  ),
  matching: find.byType(CustomScrollView),
);

/// The portion of the stable viewport below the overlaid reader header.
Rect topicReadingViewportRect(WidgetTester tester) {
  final finder = topicPostListFinder();
  final rect = tester.getRect(finder);
  final header = DPageSurface.headerGeometryOf(tester.element(finder));
  return Rect.fromLTRB(
    rect.left,
    rect.top + (header?.visibleExtent ?? 0),
    rect.right,
    rect.bottom,
  );
}

TopicPostListHandle topicPostList(WidgetTester tester) {
  final viewport = topicPostListFinder();
  final scroll = tester.widget<CustomScrollView>(viewport);
  final sliver = tester.widget<SuperSliverList>(
    find.descendant(of: viewport, matching: find.bySubtype<SuperSliverList>()),
  );
  final padding = tester.widget<SliverPadding>(
    find.ancestor(
      of: find.descendant(
        of: viewport,
        matching: find.bySubtype<SuperSliverList>(),
      ),
      matching: find.byType(SliverPadding),
    ),
  );
  return (
    controller: scroll.controller,
    listController: sliver.listController,
    padding: padding.padding,
    key: scroll.key,
  );
}
