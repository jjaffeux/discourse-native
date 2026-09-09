import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final scrollAreaExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Native scrolling with compact, themed draggable scrollbars.',
  notes:
      'Browser reference, widget exports and the isolated macOS fixture were reviewed. Controllers are borrowed when supplied. DScrollBar decorates an existing viewport without replacing virtualization or restoration. Tab into an overflowing area, then use arrows, Page Up/Down, Home/End or Space/Shift+Space. Thumb artwork uses the live border token.',
  examples: [
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
            borderRadius: BorderRadius.circular(tokens.radius * .8),
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontFamilyFallback: Theme.of(
                  context,
                ).textTheme.bodyMedium?.fontFamilyFallback,
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
          borderRadius: BorderRadius.circular(tokens.radius * .8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: DScrollArea(
            borderRadius: BorderRadius.circular(tokens.radius * .8),
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

const _tagsCode = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ScrollAreaTags extends StatelessWidget {
  const ScrollAreaTags({this.rtl = false});
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
            borderRadius: BorderRadius.circular(tokens.radius * .8),
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontFamilyFallback: Theme.of(
                  context,
                ).textTheme.bodyMedium?.fontFamilyFallback,
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
}''';

const _rtlCode =
    r'''// Mount ScrollAreaTags(rtl: true) inside Directionality(textDirection: TextDirection.rtl).
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ScrollAreaTags extends StatelessWidget {
  const ScrollAreaTags({this.rtl = false});
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
            borderRadius: BorderRadius.circular(tokens.radius * .8),
            padding: const EdgeInsets.all(16),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontFamilyFallback: Theme.of(
                  context,
                ).textTheme.bodyMedium?.fontFamilyFallback,
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
}''';

const _artworkCode = r'''import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ScrollAreaArtworks extends StatelessWidget {
  const ScrollAreaArtworks();
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
            borderRadius: BorderRadius.circular(tokens.radius * .8),
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
}''';

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
