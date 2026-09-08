import 'package:discourse_native/src/shell/anchored_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderConstrainedBox;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('anchorRect', () {
    testWidgets('reports the anchor in the overlay\'s coordinates', (
      tester,
    ) async {
      final key = GlobalKey();
      late BuildContext overlayContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) {
                  overlayContext = context;
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 30, top: 40),
                      child: SizedBox(key: key, width: 100, height: 20),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

      final rect = anchorRect(
        anchor: key.currentContext!.findRenderObject() as RenderBox?,
        overlay:
            Overlay.of(overlayContext).context.findRenderObject() as RenderBox?,
      );

      expect(rect, const Rect.fromLTWH(30, 40, 100, 20));
    });

    testWidgets('answers null once the anchor has left the tree', (
      tester,
    ) async {
      final anchorKey = GlobalKey();
      final rootKey = GlobalKey();

      Widget frame({required bool showAnchor}) => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          key: rootKey,
          width: 800,
          height: 600,
          // A different widget type when the anchor goes, so the element is
          // unmounted and its render object genuinely let go of rather than
          // updated in place the way a same-type rebuild would.
          child: showAnchor
              ? SizedBox(key: anchorKey, width: 100, height: 20)
              : const Placeholder(),
        ),
      );

      await tester.pumpWidget(frame(showAnchor: true));
      final anchor = anchorKey.currentContext!.findRenderObject() as RenderBox;
      final root = rootKey.currentContext!.findRenderObject() as RenderBox;
      expect(anchorRect(anchor: anchor, overlay: root), isNotNull);

      await tester.pumpWidget(frame(showAnchor: false));
      expect(anchor.attached, isFalse);
      // The frame after whatever a panel hangs off has gone. `localToGlobal`
      // walks from here up to the overlay and there is no longer a path.
      expect(anchorRect(anchor: anchor, overlay: root), isNull);
    });

    test('answers null when either box is missing', () {
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(
          width: 1,
          height: 1,
        ),
      );

      expect(anchorRect(anchor: null, overlay: box), isNull);
      expect(anchorRect(anchor: box, overlay: null), isNull);
    });
  });

  group('AnchoredLayout', () {
    test('centers a panel with nothing to point at', () {
      const layout = AnchoredLayout(anchor: null, maxWidth: 300);
      expect(
        layout.getPositionForChild(const Size(800, 600), const Size(200, 100)),
        const Offset(300, 250),
      );
    });

    test('drops below the anchor when there is room', () {
      const layout = AnchoredLayout(
        anchor: Rect.fromLTWH(40, 100, 120, 20),
        maxWidth: 300,
      );
      expect(
        layout.getPositionForChild(const Size(800, 600), const Size(200, 100)),
        const Offset(40, 128),
      );
    });

    test('flips above rather than off the bottom', () {
      const layout = AnchoredLayout(
        anchor: Rect.fromLTWH(40, 540, 120, 20),
        maxWidth: 300,
      );
      expect(
        layout
            .getPositionForChild(const Size(800, 600), const Size(200, 100))
            .dy,
        432,
      );
    });

    test('keeps a preferred-above panel on that side as it grows', () {
      const layout = AnchoredLayout(
        anchor: Rect.fromLTWH(40, 180, 120, 20),
        maxWidth: 300,
        preferAbove: true,
        keepPreferredPlacement: true,
      );

      final constraints = layout.getConstraintsForChild(
        const BoxConstraints(maxWidth: 800, maxHeight: 600),
      );
      expect(constraints.maxHeight, 160);

      final compact = layout.getPositionForChild(
        const Size(800, 600),
        const Size(200, 44),
      );
      final expanded = layout.getPositionForChild(
        const Size(800, 600),
        const Size(200, 160),
      );
      expect(compact.dy + 44, 172);
      expect(expanded.dy + 160, 172);
    });

    test('prefers above and falls below when there is not enough room', () {
      for (final anchorTop in [40.0, 300.0]) {
        final layout = AnchoredLayout(
          anchor: Rect.fromLTWH(40, anchorTop, 120, 20),
          maxWidth: 300,
          preferAbove: true,
        );
        expect(
          layout.getPositionForChild(
            const Size(800, 600),
            const Size(200, 100),
          ),
          Offset(40, anchorTop == 40 ? 68 : 192),
        );
      }
    });

    for (final anchorTop in [-300.0, 750.0]) {
      for (final preferAbove in [false, true]) {
        for (final keepPreferredPlacement in [false, true]) {
          test('clamps an offscreen anchor at $anchorTop '
              '(preferAbove: $preferAbove, '
              'keepPreferredPlacement: $keepPreferredPlacement)', () {
            const viewport = Size(800, 480);
            final layout = AnchoredLayout(
              anchor: Rect.fromLTWH(40, anchorTop, 120, 20),
              maxWidth: 300,
              preferAbove: preferAbove,
              keepPreferredPlacement: keepPreferredPlacement,
            );
            final constraints = layout.getConstraintsForChild(
              BoxConstraints.tight(viewport),
            );
            final childSize = constraints.constrain(const Size(200, 200));

            expect(
              layout.getPositionForChild(viewport, childSize),
              Offset(40, anchorTop < 0 ? 12 : 268),
            );
            expect(
              childSize.height,
              anchorTop < 0 && preferAbove && keepPreferredPlacement ? 0 : 200,
            );
          });
        }
      }
    }

    test('keeps constraints and clamp ranges valid in tiny viewports', () {
      for (final viewport in [
        Size.zero,
        const Size(10, 10),
        const Size(24, 24),
      ]) {
        for (final anchorTop in [-300.0, 750.0]) {
          for (final preferAbove in [false, true]) {
            for (final keepPreferredPlacement in [false, true]) {
              final layout = AnchoredLayout(
                anchor: Rect.fromLTWH(40, anchorTop, 120, 20),
                maxWidth: 300,
                preferAbove: preferAbove,
                keepPreferredPlacement: keepPreferredPlacement,
              );
              final constraints = layout.getConstraintsForChild(
                BoxConstraints.tight(viewport),
              );

              expect(constraints.isNormalized, isTrue);
              expect(constraints.biggest, Size.zero);
              expect(
                layout.getPositionForChild(viewport, constraints.biggest),
                const Offset(12, 12),
              );
            }
          }
        }
      }
    });

    test('slides along the edge rather than past it', () {
      const layout = AnchoredLayout(
        anchor: Rect.fromLTWH(700, 100, 80, 20),
        maxWidth: 300,
      );
      expect(
        layout
            .getPositionForChild(const Size(800, 600), const Size(200, 100))
            .dx,
        588,
      );
    });
  });
}
