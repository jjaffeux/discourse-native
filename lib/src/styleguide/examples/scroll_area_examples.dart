import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final scrollAreaExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Native scrolling with transparent edge fades and compact, themed draggable scrollbars.',
  notes:
      'Vertical content fades over 14px at the top and 20px at the bottom only while more content remains beyond that edge. DScrollFadeScope changes the extent or follows a floating header; nested lists keep their own edges. Horizontal viewports are unchanged. Controllers are borrowed when supplied. DScrollBar decorates an existing viewport without replacing virtualization or restoration. Tab into an overflowing area, then use arrows, Page Up/Down, Home/End or Space/Shift+Space. Thumb artwork adapts to its surface with at least 3:1 contrast and a 2px container inset. Supply backgroundColor for a custom surface.',
  examples: [
    StyleguideExample(
      title: 'Surface contrast',
      description:
          'Thumb colors follow the supplied surface, with 2px of clear space at the container edge. Switch palettes to compare content, panel and popup backgrounds.',
      code: 'DScrollArea(backgroundColor: surface, child: content)',
      builder: (context) {
        final tokens = DTokens.of(context);
        return Row(
          children: [
            for (final surface in [
              tokens.background,
              tokens.muted,
              tokens.surface,
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ColoredBox(
                    color: surface,
                    child: SizedBox(
                      height: 160,
                      child: DScrollArea(
                        backgroundColor: surface,
                        child: Column(
                          children: [
                            for (var i = 1; i <= 20; i++)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text('Row $i'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    StyleguideExample(
      title: 'Tags',
      description:
          'The reference 192 × 288px list with 16px padding and separators.',
      code: _tagsCode,
      builder: (_) => const _Tags(),
    ),
    StyleguideExample(
      title: 'Horizontal',
      description:
          'The reference photographs, 150 × 200px, 16px gaps and padding in a 384px area. Drag the bottom thumb or use a trackpad.',
      code: _artworkCode,
      builder: (_) => const _Artworks(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The reference tags composition with an Arabic heading and a leading scrollbar.',
      code: _rtlCode,
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
      code: _lazyCode,
      builder: (_) => const _LazyComposition(),
    ),
    StyleguideExample(
      title: 'Hidden scrollbar',
      description:
          'Scroll with the wheel or touch, or Tab into the viewport and use the arrow keys. The scrollbar stays hidden during scrolling and hover, as in the sidebar.',
      code: r'''SizedBox(height: 180,
  child: DScrollArea(showScrollbar: false,
    child: Column(children: [
      for (var i = 0; i < 30; i++)
        Padding(padding: EdgeInsets.all(8), child: Text('Destination $i')),
    ]),
  ),
)''',
      builder: (_) => SizedBox(
        height: 180,
        child: DScrollArea(
          showScrollbar: false,
          child: Column(
            children: [
              for (var i = 0; i < 30; i++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Destination $i'),
                ),
            ],
          ),
        ),
      ),
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
          borderRadius: BorderRadius.circular(tokens.radius * .8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: DScrollArea(
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontFamilyFallback: Theme.of(
                  context,
                ).textTheme.bodyMedium?.fontFamilyFallback,
                fontSize: DiscourseTypography.sm,
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
          borderRadius: BorderRadius.circular(tokens.radius * .8),
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
                        borderRadius: BorderRadius.circular(tokens.radius * .8),
                        child: Image.asset(
                          'packages/discourse_native/src/styleguide/assets/scroll_area/${entry.$1}.jpg',
                          width: 150,
                          height: 200,
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
                          fontSize: DiscourseTypography.xs,
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

const _tagsCode =
    "import 'package:discourse_native/discourse_ui.dart';\nimport 'package:flutter/material.dart';\n\nclass ScrollAreaTags extends StatelessWidget {\n  const ScrollAreaTags({this.rtl = false});\n  final bool rtl;\n  @override\n  Widget build(BuildContext context) {\n    final tokens = DTokens.of(context);\n    return SizedBox(\n      width: 192,\n      height: 288,\n      child: DecoratedBox(\n        decoration: BoxDecoration(\n          border: Border.all(color: tokens.border),\n          borderRadius: BorderRadius.circular(tokens.radius * .8),\n        ),\n        child: Padding(\n          padding: const EdgeInsets.all(1),\n          child: DScrollArea(\n            \n            padding: const EdgeInsets.all(16),\n            child: DefaultTextStyle(\n              style: TextStyle(\n                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,\n                fontFamilyFallback: Theme.of(\n                  context,\n                ).textTheme.bodyMedium?.fontFamilyFallback,\n                fontSize: DiscourseTypography.sm,\n                height: 20 / 14,\n                color: tokens.foreground,\n              ),\n              child: Column(\n                crossAxisAlignment: CrossAxisAlignment.stretch,\n                children: [\n                  Text(\n                    rtl ? 'العلامات' : 'Tags',\n                    style: const TextStyle(\n                      height: 1,\n                      fontWeight: FontWeight.w500,\n                    ),\n                  ),\n                  const SizedBox(height: 16),\n                  for (var i = 50; i > 0; i--) ...[\n                    Text('v1.2.0-beta.\$i'),\n                    const Padding(\n                      padding: EdgeInsets.symmetric(vertical: 8),\n                      child: DSeparator(),\n                    ),\n                  ],\n                ],\n              ),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}";

const _rtlCode =
    "// Mount ScrollAreaTags(rtl: true) inside Directionality(textDirection: TextDirection.rtl).\nimport 'package:discourse_native/discourse_ui.dart';\nimport 'package:flutter/material.dart';\n\nclass ScrollAreaTags extends StatelessWidget {\n  const ScrollAreaTags({this.rtl = false});\n  final bool rtl;\n  @override\n  Widget build(BuildContext context) {\n    final tokens = DTokens.of(context);\n    return SizedBox(\n      width: 192,\n      height: 288,\n      child: DecoratedBox(\n        decoration: BoxDecoration(\n          border: Border.all(color: tokens.border),\n          borderRadius: BorderRadius.circular(tokens.radius * .8),\n        ),\n        child: Padding(\n          padding: const EdgeInsets.all(1),\n          child: DScrollArea(\n            \n            padding: const EdgeInsets.all(16),\n            child: DefaultTextStyle(\n              style: TextStyle(\n                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,\n                fontFamilyFallback: Theme.of(\n                  context,\n                ).textTheme.bodyMedium?.fontFamilyFallback,\n                fontSize: DiscourseTypography.sm,\n                height: 20 / 14,\n                color: tokens.foreground,\n              ),\n              child: Column(\n                crossAxisAlignment: CrossAxisAlignment.stretch,\n                children: [\n                  Text(\n                    rtl ? 'العلامات' : 'Tags',\n                    style: const TextStyle(\n                      height: 1,\n                      fontWeight: FontWeight.w500,\n                    ),\n                  ),\n                  const SizedBox(height: 16),\n                  for (var i = 50; i > 0; i--) ...[\n                    Text('v1.2.0-beta.\$i'),\n                    const Padding(\n                      padding: EdgeInsets.symmetric(vertical: 8),\n                      child: DSeparator(),\n                    ),\n                  ],\n                ],\n              ),\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}";

const _artworkCode =
    "import 'package:discourse_native/discourse_ui.dart';\nimport 'package:flutter/material.dart';\n\nclass ScrollAreaArtworks extends StatelessWidget {\n  const ScrollAreaArtworks();\n  @override\n  Widget build(BuildContext context) {\n    final tokens = DTokens.of(context);\n    return SizedBox(\n      width: 384,\n      child: DecoratedBox(\n        decoration: BoxDecoration(\n          border: Border.all(color: tokens.border),\n          borderRadius: BorderRadius.circular(tokens.radius * .8),\n        ),\n        child: Padding(\n          padding: const EdgeInsets.all(1),\n          child: DScrollArea(\n            \n            axes: DScrollAxes.horizontal,\n            padding: const EdgeInsets.all(16),\n            child: Row(\n              crossAxisAlignment: CrossAxisAlignment.start,\n              children: [\n                for (final entry in const [\n                  ('ornella', 'Ornella Binni'),\n                  ('tom', 'Tom Byrom'),\n                  ('vladimir', 'Vladimir Malyavko'),\n                ]) ...[\n                  if (entry.\$1 != 'ornella') const SizedBox(width: 16),\n                  Column(\n                    crossAxisAlignment: CrossAxisAlignment.start,\n                    mainAxisSize: MainAxisSize.min,\n                    children: [\n                      ClipRRect(\n                        borderRadius: BorderRadius.circular(tokens.radius * .8),\n                        child: Image.asset(\n                          'packages/discourse_native/src/styleguide/assets/scroll_area/\${entry.\$1}.jpg',\n                          width: 150,\n                          height: 200,\n                          fit: BoxFit.cover,\n                          semanticLabel: 'Photo by \${entry.\$2}',\n                        ),\n                      ),\n                      const SizedBox(height: 8),\n                      Text.rich(\n                        TextSpan(\n                          text: 'Photo by ',\n                          children: [\n                            TextSpan(\n                              text: entry.\$2,\n                              style: TextStyle(\n                                fontWeight: FontWeight.w600,\n                                color: tokens.foreground,\n                              ),\n                            ),\n                          ],\n                        ),\n                        style: TextStyle(\n                          fontSize: DiscourseTypography.xs,\n                          height: 16 / 12,\n                          color: tokens.mutedForeground,\n                        ),\n                      ),\n                    ],\n                  ),\n                ],\n              ],\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n}";

const _lazyCode = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ScrollAreaLazyComposition extends StatefulWidget {
  const ScrollAreaLazyComposition();
  @override
  State<ScrollAreaLazyComposition> createState() => ScrollAreaLazyCompositionState();
}

class ScrollAreaLazyCompositionState extends State<ScrollAreaLazyComposition> {
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
}''';
