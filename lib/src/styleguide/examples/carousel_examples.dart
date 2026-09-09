import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final carouselExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A carousel with motion, snapping, swipe and accessible controls.',
  notes:
      'The composition mirrors Carousel, Content, Item, Previous and Next. '
      'DCarouselController is borrowed; plugins are borrowed through plugins or '
      'disposed by the carousel through ownedPlugins. Extents are fractions of '
      'the live viewport and can resolve responsively. Arrow keys follow the '
      'axis and reading direction; touch and pointer drags use Flutter paging. '
      'Autoplay pauses for focus and reduced motion and supports Embla-style '
      'interaction stopping. The base-nova mapping is a 16px slide gap, 32px '
      'outline circular controls, 48px control offset, 16px chevrons, and host '
      'palette/font/radius tokens. The production cooked-post image carousel '
      'uses this track while retaining its gallery dots and media rendering.',
  examples: [
    _example('Default', 'One full-width Card per snap.', const _CarouselDemo()),
    _example(
      'Sizes',
      'Three Card slides fit at wide widths.',
      const _CarouselDemo(extent: 1 / 3),
      code: 'DCarouselContent(extentFraction: 1 / 3, children: items)',
    ),
    _example(
      'Responsive sizes',
      'Two slides below 480px, then three.',
      const _CarouselDemo(responsive: true),
      code:
          'DCarouselContent(extentResolver: (width) => width < 480 ? .5 : 1 / 3, children: items)',
    ),
    _example(
      'Spacing',
      'An 8px compact gap demonstrates explicit slide spacing.',
      const _CarouselDemo(extent: .5, spacing: 8),
      code: 'DCarouselContent(extentFraction: .5, spacing: 8, children: items)',
    ),
    _example(
      'Vertical',
      'Vertical swipe and Up/Down navigation preserve the same composition.',
      const _CarouselDemo(vertical: true),
      code:
          'DCarousel(orientation: Axis.vertical, children: [DCarouselContent(height: 224, children: items), const DCarouselPrevious(), const DCarouselNext()])',
    ),
    _example(
      'Options: loop and center',
      'Looping keeps both controls enabled; centered alignment reveals adjacent slides.',
      const _CarouselDemo(loop: true, extent: .72, centered: true),
      code:
          'DCarousel(loop: true, children: [DCarouselContent(extentFraction: .72, alignment: DCarouselAlignment.center, children: items)])',
    ),
    StyleguideExample(
      title: 'API and events',
      description:
          'Select slides imperatively and observe selection/scroll events.',
      states: const ['Controller', 'Selected event', 'Scroll start/end'],
      code:
          "final controller = DCarouselController();\nDCarousel(controller: controller, onSelected: (index) => setState(() => current = index), children: parts)",
      builder: (_) => const _ApiDemo(),
    ),
    StyleguideExample(
      title: 'Autoplay plugin',
      description: 'Two-second autoplay with explicit play and stop controls.',
      states: const [
        'Autoplay',
        'Interaction stop',
        'Reduced motion',
        'Disposal',
      ],
      code:
          'DCarousel(ownedPlugins: [DCarouselAutoplay(delay: const Duration(seconds: 2))], children: parts)',
      builder: (_) => const _AutoplayDemo(),
    ),
    _example(
      'RTL',
      'Direction-aware drag, arrow keys and chevrons in Arabic.',
      const Directionality(
        textDirection: TextDirection.rtl,
        child: _CarouselDemo(arabic: true),
      ),
      code:
          'Directionality(textDirection: TextDirection.rtl, child: DCarousel(children: parts))',
    ),
  ],
);

StyleguideExample _example(
  String title,
  String description,
  Widget child, {
  String code =
      'DCarousel(children: [DCarouselContent(children: items), const DCarouselPrevious(), const DCarouselNext()])',
}) => StyleguideExample(
  title: title,
  description: description,
  code: code,
  states: [title, 'Swipe', 'Keyboard', 'Live theme'],
  builder: (_) => child,
);

class _CarouselDemo extends StatelessWidget {
  const _CarouselDemo({
    this.extent = 1,
    this.spacing = 16,
    this.responsive = false,
    this.vertical = false,
    this.loop = false,
    this.centered = false,
    this.arabic = false,
    this.controller,
    this.plugins = const [],
    this.onSelected,
    this.onScrollStart,
    this.onScrollEnd,
  });
  final double extent, spacing;
  final bool responsive, vertical, loop, centered, arabic;
  final DCarouselController? controller;
  final List<DCarouselPlugin> plugins;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onScrollStart, onScrollEnd;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (var i = 1; i <= 5; i++) _card(arabic ? '٠١٢٣٤٥'[i] : '$i'),
    ];
    final carousel = DCarousel(
      controller: controller,
      orientation: vertical ? Axis.vertical : Axis.horizontal,
      loop: loop,
      plugins: plugins,
      semanticLabel: arabic ? 'شرائح' : 'Featured slides',
      onSelected: onSelected,
      onScrollStart: onScrollStart,
      onScrollEnd: onScrollEnd,
      children: [
        DCarouselContent(
          height: vertical ? 224 : 160,
          extentFraction: extent,
          extentResolver: responsive
              ? (width) => width < 480 ? .5 : 1 / 3
              : null,
          spacing: spacing,
          alignment: centered
              ? DCarouselAlignment.center
              : DCarouselAlignment.start,
          children: cards,
        ),
        const DCarouselPrevious(),
        const DCarouselNext(),
      ],
    );
    return SizedBox(width: vertical ? 272 : 516, child: carousel);
  }

  DCarouselItem _card(String label) => DCarouselItem(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: DCard(
        child: DCardContent(
          child: SizedBox(
            height: 158,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ApiDemo extends StatefulWidget {
  const _ApiDemo();
  @override
  State<_ApiDemo> createState() => _ApiDemoState();
}

class _ApiDemoState extends State<_ApiDemo> {
  final _controller = DCarouselController();
  int _current = 0, _starts = 0, _ends = 0;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CarouselDemo(
        controller: _controller,
        onSelected: (value) => setState(() => _current = value),
        onScrollStart: () => setState(() => _starts++),
        onScrollEnd: () => setState(() => _ends++),
      ),
      Text('Slide ${_current + 1} of 5 · scrolls $_starts/$_ends'),
      DButton(
        label: const Text('Select slide 4'),
        size: DButtonSize.small,
        variant: DButtonVariant.outline,
        onPressed: () => _controller.select(3),
      ),
    ],
  );
}

class _AutoplayDemo extends StatefulWidget {
  const _AutoplayDemo();
  @override
  State<_AutoplayDemo> createState() => _AutoplayDemoState();
}

class _AutoplayDemoState extends State<_AutoplayDemo> {
  final _controller = DCarouselController();
  final _autoplay = DCarouselAutoplay(delay: const Duration(seconds: 2));
  int _current = 0;
  @override
  void dispose() {
    _autoplay.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CarouselDemo(
        controller: _controller,
        loop: true,
        plugins: [_autoplay],
        onSelected: (value) => setState(() => _current = value),
      ),
      Text('Slide ${_current + 1} of 5'),
      Wrap(
        spacing: 8,
        children: [
          DButton(
            label: const Text('Play'),
            size: DButtonSize.small,
            onPressed: _autoplay.play,
          ),
          DButton(
            label: const Text('Stop'),
            size: DButtonSize.small,
            variant: DButtonVariant.outline,
            onPressed: _autoplay.stop,
          ),
        ],
      ),
    ],
  );
}
