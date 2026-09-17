import 'package:flutter/widgets.dart';

/// Topic lists fill their pane; reading-width preferences apply to prose only.
const double topicListContentWidth = double.infinity;
const double topicListHorizontalPadding = 8;
const double topicInboxDividerInset = 8;
const double topicListCardBreakpoint = 320;

/// Shares the list pane's breakpoint with its rows, headings and display menu.
class TopicListLayout extends StatelessWidget {
  const TopicListLayout({super.key, required this.child});

  final Widget child;

  static bool forceCardOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TopicListLayoutScope>()
          ?.forceCard ??
      false;

  @override
  Widget build(BuildContext context) {
    // Rows can also appear on their own. Inside a list, use the pane width
    // rather than measuring again after the list's horizontal padding.
    if (context.dependOnInheritedWidgetOfExactType<_TopicListLayoutScope>() !=
        null) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) => _TopicListLayoutScope(
        forceCard: constraints.maxWidth < topicListCardBreakpoint,
        child: child,
      ),
    );
  }
}

class _TopicListLayoutScope extends InheritedWidget {
  const _TopicListLayoutScope({required this.forceCard, required super.child});

  final bool forceCard;

  @override
  bool updateShouldNotify(_TopicListLayoutScope oldWidget) =>
      forceCard != oldWidget.forceCard;
}
