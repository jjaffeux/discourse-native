import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../styleguide_example.dart';

final navigationPillExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A passive arrow pill for a row that opens another page.',
  notes:
      'The containing Native row owns activation and semantics. The pill '
      'mirrors in RTL and grows with accessibility text.',
  examples: [
    StyleguideExample(
      title: 'Section navigation',
      description: 'One row and one target, including the decorative arrow.',
      code: 'DNavigationPill()',
      builder: (_) => navigationPillPreview(),
    ),
  ],
);

@Preview(name: 'Section navigation', group: 'Navigation pill')
Widget navigationPillPreview() => DItem(
  size: DItemSize.xs,
  shape: DItemShape.menu,
  onPressed: () {},
  children: const [
    DItemContent(children: [Text('Topics & posts')]),
    DNavigationPill(),
  ],
);
