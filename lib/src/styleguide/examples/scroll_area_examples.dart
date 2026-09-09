import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final scrollAreaExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Native scrolling with compact, themed draggable scrollbars.',
  notes:
      'Reference/native comparison is queued. Controllers are borrowed when supplied. DScrollBar decorates an existing viewport without replacing virtualization or restoration. Tab into an area, then use arrows, Page Up/Down, Home/End or Space. Thumb artwork uses the live border token.',
  examples: [
    StyleguideExample(
      title: 'Tags',
      description:
          'The reference 192 × 288px list with 16px padding and separators.',
      code: '''SizedBox(width: 192, height: 288,
  child: DScrollArea(padding: EdgeInsets.all(16),
    child: Column(children: [Text('Tags'), ...tags])),
)''',
      builder: (_) => const _Tags(),
    ),
    StyleguideExample(
      title: 'Horizontal',
      description:
          'The reference photographs, 300 × 400px, 16px gaps and padding in a 384px area. Drag the bottom thumb or use a trackpad.',
      code:
          "SizedBox(width: 384, child: DScrollArea(axes: DScrollAxes.horizontal, padding: EdgeInsets.all(16), child: Row(children: photographs)))",
      builder: (_) => const _Artworks(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The reference tags composition with an Arabic heading and a leading scrollbar.',
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: SizedBox(width: 192, height: 288,
    child: DScrollArea(child: tags)),
)''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _Tags(rtl: true),
      ),
    ),
    StyleguideExample(
      title: 'Combined overflow',
      description:
          'Independent native positions on two axes. Resize and change themes without losing local text or scroll position.',
      code: '''DScrollArea(axes: DScrollAxes.both,
  child: SizedBox(width: 800, height: 800,
    child: TextField(decoration: InputDecoration(labelText: 'Retained note'))),
)''',
      builder: (_) => const SizedBox(
        height: 280,
        child: DScrollArea(
          axes: DScrollAxes.both,
          child: SizedBox(
            width: 800,
            height: 800,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      decoration: InputDecoration(labelText: 'Retained note'),
                    ),
                  ),
                  SizedBox(height: 550),
                  Text('Far corner'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Lazy viewport and thumb composition',
      description:
          'A borrowed controller and a virtualized list. Toggle fading or remove rows while scrolled; Flutter retains and clamps the same position.',
      code:
          "DScrollBar(controller: controller, thumb: DScrollThumb(), child: ListView.builder(controller: controller, itemCount: count, itemBuilder: (_, i) => Text('Row \$i')))",
      builder: (_) => const _LazyComposition(),
    ),
  ],
);

class _Tags extends StatelessWidget {
  const _Tags({this.rtl = false});
  final bool rtl;
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return SizedBox(
      width: 192,
      height: 288,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: tokens.borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: DScrollArea(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: 14,
                height: 20 / 14,
                color: tokens.foreground,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    rtl ? 'العلامات' : 'Tags',
                    style: const TextStyle(
                      height: 1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 50; i > 0; i--) ...[
                    Text('v1.2.0-beta.$i'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: DSeparator(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Artworks extends StatelessWidget {
  const _Artworks();
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return SizedBox(
      width: 384,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: tokens.borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: DScrollArea(
            axes: DScrollAxes.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in const [
                  ('ornella', 'Ornella Binni'),
                  ('tom', 'Tom Byrom'),
                  ('vladimir', 'Vladimir Malyavko'),
                ]) ...[
                  if (entry.$1 != 'ornella') const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: tokens.borderRadius,
                        child: Image.asset(
                          'packages/discourse_native/src/styleguide/assets/scroll_area/${entry.$1}.jpg',
                          width: 300,
                          height: 400,
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo by ${entry.$2}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          text: 'Photo by ',
                          children: [
                            TextSpan(
                              text: entry.$2,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: tokens.foreground,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: tokens.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LazyComposition extends StatefulWidget {
  const _LazyComposition();
  @override
  State<_LazyComposition> createState() => _LazyCompositionState();
}

class _LazyCompositionState extends State<_LazyComposition> {
  final _controller = ScrollController();
  bool _visible = true;
  int _count = 500;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    child: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            DButton(
              label: Text(_visible ? 'Use fading thumb' : 'Keep thumb visible'),
              onPressed: () => setState(() => _visible = !_visible),
            ),
            DButton(
              label: Text(_count == 500 ? 'Remove rows' : 'Restore rows'),
              onPressed: () => setState(() => _count = _count == 500 ? 3 : 500),
            ),
          ],
        ),
        Expanded(
          child: DScrollBar(
            controller: _controller,
            thumbVisibility: _visible,
            child: ListView.builder(
              controller: _controller,
              itemCount: _count,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Row $i'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
