import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final gradientBlurExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Progressive backdrop blur behind floating controls.',
  notes:
      'Place DGradientBlur in a bounded stack after the scrolling content and '
      'before the controls. The opposite edge stays clear, with no surface-color '
      'overlay. Use fullStrengthExtent to continue the blur beneath a keyboard '
      'without stretching the fade. The blur ignores pointer input and '
      'contributes no semantics.',
  examples: [
    StyleguideExample(
      title: 'Floating controls',
      description:
          'Scroll the text beneath the top and bottom blur. The floating '
          'actions stay sharp and the bottom action scrolls to the last line.',
      states: const ['Light', 'Dark', 'Touch', 'Large text', 'RTL'],
      code: '''Stack(children: [
  content,
  const Positioned(
    top: 0, left: 0, right: 0, height: 72,
    child: DGradientBlur(),
  ),
  const Positioned(
    bottom: 0, left: 0, right: 0, height: 72,
    child: DGradientBlur(edge: DGradientBlurEdge.bottom),
  ),
  controls,
])''',
      builder: (_) => const _GradientBlurExample(),
    ),
    StyleguideExample(
      title: 'Continued blur',
      description:
          'The bottom blur fades in behind the action, then stays at full '
          'strength below it. A composer uses the keyboard inset for this region.',
      code: '''Positioned(
  bottom: 0, left: 0, right: 0, height: 72 + keyboardInset,
  child: DGradientBlur(
    edge: DGradientBlurEdge.bottom,
    fullStrengthExtent: keyboardInset,
  ),
)''',
      builder: (_) => const _GradientBlurExample(fullStrengthExtent: 64),
    ),
  ],
);

class _GradientBlurExample extends StatefulWidget {
  const _GradientBlurExample({this.fullStrengthExtent = 0});

  final double fullStrengthExtent;

  @override
  State<_GradientBlurExample> createState() => _GradientBlurExampleState();
}

class _GradientBlurExampleState extends State<_GradientBlurExample> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    child: ClipRect(
      child: Stack(
        children: [
          DScrollArea(
            controller: _scroll,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                72,
                16,
                72 + widget.fullStrengthExtent,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  for (var line = 1; line <= 20; line++)
                    Text('$line. Text becomes softer behind the controls.'),
                ],
              ),
            ),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 72,
            child: DGradientBlur(),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 72 + widget.fullStrengthExtent,
            child: DGradientBlur(
              edge: DGradientBlurEdge.bottom,
              fullStrengthExtent: widget.fullStrengthExtent,
            ),
          ),
          PositionedDirectional(
            top: 12,
            start: 16,
            child: DButton.iconOnly(
              shape: DButtonShape.pill,
              variant: DButtonVariant.secondary,
              icon: const DIcon(DIcons.arrowUp),
              tooltip: 'Scroll to top',
              onPressed: () => _scroll.jumpTo(0),
            ),
          ),
          PositionedDirectional(
            bottom: 12 + widget.fullStrengthExtent,
            end: 16,
            child: DButton.iconOnly(
              shape: DButtonShape.pill,
              variant: DButtonVariant.secondary,
              icon: const DIcon(DIcons.chevronDown),
              tooltip: 'Scroll to bottom',
              onPressed: () => _scroll.jumpTo(_scroll.position.maxScrollExtent),
            ),
          ),
        ],
      ),
    ),
  );
}
