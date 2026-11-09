import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../styleguide_example.dart';

final threadExamples = ComponentExamples(
  description:
      'Connects nested replies with decorative branches and interactive rails.',
  status: ComponentStatus.implemented,
  notes:
      'Give rails and connectors a finite height. The rail centers its two-pixel stroke in its slot. On phones DTouchTargets supplies the touch area.',
  examples: [
    StyleguideExample(
      title: 'Usage',
      description: 'An expanded branch and its interactive body rail.',
      states: const ['Expanded', 'Interactive'],
      code:
          'DThreadRail(onPressed: collapse, semanticLabel: "Collapse replies")',
      builder: (_) => const _ThreadPreview(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Branch geometry mirrors with the reading direction.',
      states: const ['RTL', 'Collapsed'],
      code: 'DThreadConnector(width: 32, junction: 20)',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _ThreadPreview(),
      ),
    ),
  ],
);

class _ThreadPreview extends StatefulWidget {
  const _ThreadPreview();
  @override
  State<_ThreadPreview> createState() => _ThreadPreviewState();
}

class _ThreadPreviewState extends State<_ThreadPreview> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DToggle.iconOnly(
        semanticLabel: 'Toggle replies',
        icon: DIcon(expanded ? DIcons.minus : DIcons.plus),
        pressed: expanded,
        onPressedChanged: (_) => setState(() => expanded = !expanded),
      ),
      if (expanded)
        SizedBox(
          height: 60,
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: DThreadRail(
                  onPressed: () => setState(() => expanded = false),
                  semanticLabel: 'Collapse replies',
                ),
              ),
              const Text('Reply'),
            ],
          ),
        ),
      const SizedBox(
        height: 40,
        child: Row(
          children: [
            DThreadConnector(width: 32, junction: 20),
            Text('Nested reply'),
          ],
        ),
      ),
    ],
  );
}
