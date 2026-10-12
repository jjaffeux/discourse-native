import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
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
      'interaction stopping. The base-nova mapping is a 16px slide gap, 28px '
      'outline circular controls, 48px control offset, 16px chevrons, and host '
      'palette/font/radius tokens. The production cooked-post image carousel '
      'uses this track and DCarouselDot indicators. Dots use 10px artwork (22px when selected) with matching hit areas.',
  examples: [
    _example('Default', 'One full-width Card per snap.', const _CarouselDemo()),

    _example(
      'Spacing',
      'An 8px compact gap demonstrates explicit slide spacing.',
      const _CarouselDemo(extent: .5, spacing: 8),
      code: "DCarouselContent( spacing: 8, children: items)",
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
    this.arabic = false,
    this.controller,

    this.onSelected,
    this.onScrollStart,
    this.onScrollEnd,
  }) : responsive = false,
       vertical = false,
       loop = false,
       centered = false;
  final double extent, spacing;
  final bool responsive, vertical, loop, centered, arabic;
  final DCarouselController? controller;

  final ValueChanged<int>? onSelected;
  final VoidCallback? onScrollStart, onScrollEnd;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (var i = 1; i <= 5; i++) _card(arabic ? '٠١٢٣٤٥'[i] : '$i'),
    ];
    final carousel = DCarousel(
      controller: controller,

      loop: loop,

      semanticLabel: arabic ? 'شرائح' : 'Featured slides',
      onSelected: onSelected,

      children: [
        DCarouselContent(
          height: vertical ? 224 : 160,

          spacing: spacing,

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
            height: 126,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: DiscourseTypography.xxl,
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
