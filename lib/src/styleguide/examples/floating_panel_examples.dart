import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final floatingPanelExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Movable surfaces that snap to an edge and tuck into a restore tab.',
  notes:
      'Only visible content receives pointer input. The caller supplies safe areas and navigation insets. Tucking preserves the child and does not close its session.',
  examples: [
    StyleguideExample(
      title: 'Drag, tuck and restore',
      description:
          'Drag to either edge. Move beyond the edge to tuck away. Buttons provide the same actions without dragging.',
      code:
          'DFloatingPanel(controller: controller, restoreLabel: restoreLabel, child: DCard(child: content))',
      states: const [
        'Touch',
        'Keyboard',
        'RTL',
        'Large text',
        'Reduced motion',
      ],
      builder: (_) => const _FloatingPanelExample(),
    ),
  ],
);

class _FloatingPanelExample extends StatefulWidget {
  const _FloatingPanelExample();
  @override
  State<_FloatingPanelExample> createState() => _FloatingPanelExampleState();
}

class _FloatingPanelExampleState extends State<_FloatingPanelExample> {
  final controller = DFloatingPanelController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.controlGap,
        children: [
          DButton(
            label: Text(context.l10n.floatingPanelMoveLeft),
            onPressed: () => controller.moveToEdge(right: false),
          ),
          DButton(
            label: Text(context.l10n.floatingPanelMoveRight),
            onPressed: () => controller.moveToEdge(right: true),
          ),
          DButton(
            label: Text(context.l10n.floatingPanelHide),
            onPressed: controller.tuck,
          ),
        ],
      ),
      SizedBox(
        height: 360,
        child: DFloatingPanel(
          controller: controller,
          restoreLabel: context.l10n.floatingPanelRestore,
          child: const DCard(
            child: Padding(
              padding: EdgeInsets.all(DSpacing.lg),
              child: Text('Watercooler'),
            ),
          ),
        ),
      ),
    ],
  );
}
