import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final aspectRatioExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  notes:
      'DAspectRatio(ratio: width / height, child: ...) accepts any finite '
      'positive ratio. Flutter constraints take precedence; bound at least one '
      'axis. Compose sizing, clipping, color, imagery and captions as ordinary '
      'widgets, just as the reference composes className. The generic component '
      'does not load images, animate, create focus stops or own controllers. '
      'The first four examples match the frozen geometry, using the bundled '
      'Discourse image in place of the remote reference image. Covers use the '
      'live large radius, muted background, grayscale and 20% brightness in dark '
      'themes. Change Light, Dark, Forest or Plum, text scale and direction in '
      'the preview toolbar; only Reset reconstructs local example state.',
  examples: [
    StyleguideExample(
      title: 'Widescreen',
      description: 'The reference 16:9 cover, up to 384×216 logical pixels.',
      states: const ['16:9', 'Cover image', 'Grayscale', 'Live dark dimming'],
      code: _coverCode('16 / 9', 384),
      builder: (_) => const _Cover(ratio: 16 / 9, maxWidth: 384),
    ),
    StyleguideExample(
      title: 'Square',
      description: 'The reference square cover, up to 192×192 logical pixels.',
      states: const ['1:1', 'Center crop'],
      code: _coverCode('1', 192),
      builder: (_) => const _Cover(ratio: 1, maxWidth: 192),
    ),
    StyleguideExample(
      title: 'Portrait',
      description: 'The reference 9:16 cover, up to 160×284.44 logical pixels.',
      states: const ['9:16', 'Center crop'],
      code: _coverCode('9 / 16', 160),
      builder: (_) => const _Cover(ratio: 9 / 16, maxWidth: 160),
    ),
    StyleguideExample(
      title: 'RTL figure',
      description:
          'The reference Arabic figure: a 384px maximum cover, an 8px gap, '
          'and centered muted 14px/20px caption. The caption grows naturally '
          'with text scaling; it sits outside the ratio container.',
      states: const ['Arabic', 'RTL', 'Caption', 'Text scaling'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // The same cover composition as Widescreen.
      cover,
      const SizedBox(height: DSpacing.sm),
      const DText('منظر طبيعي جميل', variant: DTextVariant.muted,
        textAlign: TextAlign.center),
    ]),
  ),
)''',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: _Cover(ratio: 16 / 9, maxWidth: 384, caption: 'منظر طبيعي جميل'),
      ),
    ),
    StyleguideExample(
      title: 'Arbitrary ratio and composition',
      description:
          'Move the slider, including with arrow keys, to choose any ratio '
          'from 0.25 to 3.5. Switch crop and rounding independently. These '
          'choices belong to the caller; the ratio does not imply an image '
          'fit, border or background.',
      states: const ['Continuous ratio', 'Contain', 'Cover', 'Clipping'],
      code: '''// ratio, fit and rounded are local example state.
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 320),
  child: DAspectRatio(ratio: ratio, child: ClipRRect(
    borderRadius: rounded ? DTokens.of(context).borderRadius : BorderRadius.zero,
    child: ColoredBox(color: DTokens.of(context).muted,
      child: Image.asset('packages/discourse_native/src/styleguide/assets/discourse.png', fit: fit)),
  )),
)''',
      builder: (_) => const _ArbitraryRatio(),
    ),
    StyleguideExample(
      title: 'Parent constraints',
      description:
          'A bounded 260×100 region fits 16:9 at 177.78×100. With only a '
          'bounded height, 3:2 derives a 150px width. Tight 160×90 constraints '
          'override a requested square. An unbounded parent needs an explicit '
          'finite dimension. Empty ratio boxes also reserve layout space.',
      states: const [
        'Width bound',
        'Height bound',
        'Tight',
        'Unbounded parent',
      ],
      code: '''ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 260, maxHeight: 100),
  child: DAspectRatio(ratio: 16 / 9, child: content),
)
// A Row gives this non-flex child unbounded width, but a finite height.
const SizedBox(height: 100, child: Row(children: [DAspectRatio(ratio: 3 / 2)]))
// Tight parent constraints win: the actual size is 160 × 90.
const SizedBox(width: 160, height: 90, child: DAspectRatio(ratio: 1))
const UnconstrainedBox(child: SizedBox(width: 160, child: DAspectRatio(ratio: 2)))''',
      builder: (_) => const _Constraints(),
    ),
    StyleguideExample(
      title: 'Interactive content and retained state',
      description:
          'Edit the note and activate the button with touch or Tab and Enter. '
          'Resize the ratio and change preview theme or direction: the draft, '
          'counter and descendants survive. Content scrolls within its fixed '
          'ratio at large text sizes. The example owns and disposes its text '
          'controller. TextField remains a baseline native input until Input '
          'is implemented.',
      states: const ['State', 'Text input', 'Focus', 'Semantics', 'Scrolling'],
      code: '''// The caller owns and disposes controller; keep the child at a
// stable position in the tree when changing ratio or inherited themes.
DAspectRatio(ratio: ratio, child: SingleChildScrollView(
  padding: const EdgeInsets.all(DSpacing.lg),
  child: Column(children: [
    TextField(controller: controller),
    DButton(onPressed: increment, label: const Text('Increment')),
  ]),
))''',
      builder: (_) => const _InteractiveContent(),
    ),
  ],
);

String _coverCode(String ratio, int width) =>
    '''final tokens = DTokens.of(context);
final brightness = Theme.of(context).brightness == Brightness.dark ? 0.2 : 1.0;
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: $width),
  child: DAspectRatio(ratio: $ratio, child: ClipRRect(
    borderRadius: tokens.borderRadius, // Reference rounded-lg.
    child: ColoredBox(color: tokens.muted, child: ColorFiltered(
      colorFilter: ColorFilter.matrix([
        0.2126 * brightness, 0.7152 * brightness, 0.0722 * brightness, 0, 0,
        0.2126 * brightness, 0.7152 * brightness, 0.0722 * brightness, 0, 0,
        0.2126 * brightness, 0.7152 * brightness, 0.0722 * brightness, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: Image.asset('packages/discourse_native/src/styleguide/assets/discourse.png', fit: BoxFit.cover,
        semanticLabel: 'Discourse illustration'),
    )),
  )),
)''';

class _Cover extends StatelessWidget {
  const _Cover({
    required this.ratio,
    required this.maxWidth,
    this.caption,
    this.fit = BoxFit.cover,
    this.rounded = true,
  });

  final double ratio;
  final double maxWidth;
  final String? caption;
  final BoxFit fit;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final brightness = Theme.of(context).brightness == Brightness.dark
        ? 0.2
        : 1.0;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DAspectRatio(
              ratio: ratio,
              child: ClipRRect(
                borderRadius: rounded ? tokens.borderRadius : BorderRadius.zero,
                child: ColoredBox(
                  color: tokens.muted,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix([
                      0.2126 * brightness,
                      0.7152 * brightness,
                      0.0722 * brightness,
                      0,
                      0,
                      0.2126 * brightness,
                      0.7152 * brightness,
                      0.0722 * brightness,
                      0,
                      0,
                      0.2126 * brightness,
                      0.7152 * brightness,
                      0.0722 * brightness,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                    child: Image.asset(
                      'packages/discourse_native/src/styleguide/assets/discourse.png',
                      fit: fit,
                      semanticLabel: 'Discourse illustration',
                    ),
                  ),
                ),
              ),
            ),
            if (caption case final text?) ...[
              const SizedBox(height: DSpacing.sm),
              DText(
                text,
                variant: DTextVariant.muted,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArbitraryRatio extends StatefulWidget {
  const _ArbitraryRatio();

  @override
  State<_ArbitraryRatio> createState() => _ArbitraryRatioState();
}

class _ArbitraryRatioState extends State<_ArbitraryRatio> {
  double _ratio = 1.37;
  bool _cover = true;
  bool _rounded = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Width / height: ${_ratio.toStringAsFixed(2)}'),
      Slider(
        value: _ratio,
        min: 0.25,
        max: 3.5,
        semanticFormatterCallback: (value) =>
            '${value.toStringAsFixed(2)} to 1',
        onChanged: (value) => setState(() => _ratio = value),
      ),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          DButton(
            onPressed: () => setState(() => _cover = !_cover),
            label: _WrappingLabel(_cover ? 'Use contain' : 'Use cover'),
          ),
          DButton(
            onPressed: () => setState(() => _rounded = !_rounded),
            label: _WrappingLabel(
              _rounded ? 'Square corners' : 'Round corners',
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
      _Cover(
        ratio: _ratio,
        maxWidth: 320,
        fit: _cover ? BoxFit.cover : BoxFit.contain,
        rounded: _rounded,
      ),
    ],
  );
}

class _Constraints extends StatelessWidget {
  const _Constraints();

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(color: DTokens.of(context).muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Maximum 260 × 100; ratio 16:9'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260, maxHeight: 100),
          child: DAspectRatio(ratio: 16 / 9, child: content),
        ),
        const SizedBox(height: DSpacing.lg),
        const Text('Height 100; ratio 3:2'),
        SizedBox(
          height: 100,
          child: Row(
            children: [DAspectRatio(ratio: 3 / 2, child: content)],
          ),
        ),
        const SizedBox(height: DSpacing.lg),
        const Text('Tight 160 × 90; requested ratio 1:1'),
        SizedBox(
          width: 160,
          height: 90,
          child: DAspectRatio(ratio: 1, child: content),
        ),
        const SizedBox(height: DSpacing.lg),
        const Text('Unbounded parent; explicit width 160; ratio 2:1'),
        UnconstrainedBox(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 160,
            child: DAspectRatio(ratio: 2, child: content),
          ),
        ),
      ],
    );
  }
}

class _InteractiveContent extends StatefulWidget {
  const _InteractiveContent();

  @override
  State<_InteractiveContent> createState() => _InteractiveContentState();
}

class _InteractiveContentState extends State<_InteractiveContent> {
  final _controller = TextEditingController(text: 'A local draft');
  int _count = 0;
  bool _wide = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      DButton(
        key: const ValueKey('aspect-ratio-resize'),
        onPressed: () => setState(() => _wide = !_wide),
        label: _WrappingLabel(_wide ? 'Use square ratio' : 'Use wide ratio'),
      ),
      const SizedBox(height: DSpacing.lg),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DAspectRatio(
          ratio: _wide ? 3 / 2 : 1,
          child: ColoredBox(
            color: DTokens.of(context).muted,
            child: SingleChildScrollView(
              key: const ValueKey('aspect-ratio-content-scroll'),
              padding: const EdgeInsets.all(DSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'Local note'),
                  ),
                  const SizedBox(height: DSpacing.lg),
                  DButton(
                    key: const ValueKey('aspect-ratio-increment'),
                    onPressed: () => setState(() => _count++),
                    label: const _WrappingLabel(
                      'Increment the retained counter',
                    ),
                  ),
                  const SizedBox(height: DSpacing.sm),
                  Text(
                    'Count: $_count',
                    semanticsLabel: 'Retained count: $_count',
                  ),
                  const SizedBox(height: DSpacing.lg),
                  const DText(
                    'The content keeps its state as the frame changes. '
                    'At large text sizes, scroll here to keep every action reachable.',
                    variant: DTextVariant.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _WrappingLabel extends StatelessWidget {
  const _WrappingLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: DefaultTextStyle.of(context).style,
    child: Text(text),
  );
}
