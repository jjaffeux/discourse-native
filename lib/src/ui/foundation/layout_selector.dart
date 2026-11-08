import 'package:flutter/widgets.dart';

typedef DLayoutSelect<T> =
    T Function(BuildContext context, BoxConstraints constraints);
typedef DLayoutSelectedBuilder<T> =
    Widget Function(BuildContext context, T selected);

/// Builds for what its constraints decide rather than for the constraints.
///
/// Dragging a pane changes a descendant's width every pointer tick, and a
/// [LayoutBuilder] builds its whole subtree again each time even when the
/// breakpoint or fitted count it derives is unchanged. Here [builder] runs
/// again only when [select] answers with a different value, compared with `==`,
/// so [T] needs value equality.
///
/// [select] receives the context of the layout builder, so a value it reads
/// there updates the selection without rebuilding the caller. [builder] has
/// its own context, which keeps its inherited dependencies when the selection
/// is unchanged. Rebuilding this widget always builds [builder] again, because
/// a new [builder] closure can capture anything.
class DLayoutSelector<T> extends StatelessWidget {
  const DLayoutSelector({
    super.key,
    required this.select,
    required this.builder,
  });

  final DLayoutSelect<T> select;
  final DLayoutSelectedBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    late T selected;
    Widget? child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final next = select(context, constraints);
        if (child == null || next != selected) {
          selected = next;
          child = Builder(builder: (context) => builder(context, next));
        }
        return child!;
      },
    );
  }
}
