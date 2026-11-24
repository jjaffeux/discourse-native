import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/frame_safe_notifier.dart';
import '../foundation/icons/d_icons.dart';

typedef PostTextSelectionActions = ({
  VoidCallback copy,
  VoidCallback? quote,
  VoidCallback? copyQuote,
  VoidCallback? edit,
});

typedef MobilePostSelection = ({
  Object owner,
  ({Object history, Object entry}) visit,
  PostTextSelectionActions actions,
});

class MobilePostSelectionScope extends InheritedWidget {
  const MobilePostSelectionScope({
    super.key,
    required this.selection,
    required super.child,
  });

  final FrameSafeValueNotifier<MobilePostSelection?> selection;

  static FrameSafeValueNotifier<MobilePostSelection?>? maybeOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<MobilePostSelectionScope>()
      ?.selection;

  @override
  bool updateShouldNotify(MobilePostSelectionScope oldWidget) =>
      !identical(selection, oldWidget.selection);
}

typedef PostTextSelectionItem = ({
  String id,
  String label,
  DIconData icon,
  VoidCallback onPressed,
});

List<PostTextSelectionItem> postTextSelectionItems(
  BuildContext context,
  PostTextSelectionActions actions, {
  bool editLast = false,
}) {
  final strings = context.l10n;
  final edit = ('edit-selection', strings.edit, DIcons.pencil, actions.edit);
  return [
    for (final (id, label, icon, action) in [
      ('copy-selection', strings.copy, DIcons.copy, actions.copy),
      ('quote-selection', strings.quote, DIcons.quoteLeft, actions.quote),
      if (!editLast) edit,
      (
        'copy-quote-selection',
        strings.copyQuote,
        DIcons.copy,
        actions.copyQuote,
      ),
      if (editLast) edit,
    ])
      if (action != null) (id: id, label: label, icon: icon, onPressed: action),
  ];
}

class MobilePostSelectionTray extends StatelessWidget {
  const MobilePostSelectionTray({
    super.key,
    required this.geometry,
    required this.actions,
  });

  final DMobileDockGeometry geometry;
  final PostTextSelectionActions actions;

  @override
  Widget build(BuildContext context) {
    final items = postTextSelectionItems(context, actions, editLast: true);
    final tokens = DTokens.of(context);
    final primary = tokens.buttonTheme.primary;
    return Semantics(
      container: true,
      label: context.l10n.selectedText,
      child: DScrollFootCover(
        margin: geometry.margin.vertical,
        child: DCard(
          spacing: 0,
          depth: DSurfaceDepth.menu,
          backgroundColor: tokens.surface,
          borderRadius: geometry.borderRadius,
          child: Padding(
            padding: geometry.padding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = _columns(context, constraints.maxWidth, items);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DSpacing.xs,
                  children: [
                    for (var start = 0; start < items.length; start += columns)
                      Row(
                        spacing: DSpacing.xs,
                        children: [
                          for (final item in items.skip(start).take(columns))
                            Expanded(
                              child: DButton(
                                key: ValueKey(item.id),
                                semanticLabel: item.label,
                                variant: item == items.first
                                    ? DButtonVariant.primary
                                    : DButtonVariant.ghost,
                                density: DButtonDensity.mobileDockTile,
                                shape: DButtonShape.pill,
                                foregroundColor: item == items.first
                                    ? primary.foreground
                                    : null,
                                backgroundColor: item == items.first
                                    ? primary.background
                                    : null,
                                interactiveBackgroundColor: item == items.first
                                    ? primary.hover
                                    : null,
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: DSpacing.xxs,
                                  children: [
                                    DIcon(item.icon),
                                    Text(
                                      item.label,
                                      softWrap: true,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                                onPressed: item.onPressed,
                              ),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  int _columns(
    BuildContext context,
    double width,
    List<PostTextSelectionItem> items,
  ) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 11, fontWeight: FontWeight.w500);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    var cellWidth = geometry.rowHeight;
    for (final item in items) {
      painter.text = TextSpan(text: item.label, style: labelStyle);
      painter.layout();
      cellWidth = math.max(cellWidth, painter.width + 2 * DSpacing.xs);
    }
    painter.dispose();
    final capacity = (width + DSpacing.xs) ~/ (cellWidth + DSpacing.xs);
    if (capacity >= items.length) return items.length;
    return width >= 2 * geometry.rowHeight + DSpacing.xs ? 2 : 1;
  }
}
