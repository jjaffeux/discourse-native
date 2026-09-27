import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';

final stickyExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Keep an avatar visible while its post scrolls.',
  notes:
      'DSticky fills a bounded slot and keeps its child below the viewport top, '
      'stopping at the slot bottom. The content keeps its normal layout. '
      'Wrap the enclosing list in DStickySliver to refresh cached positions after '
      'content changes height, paging, or scroll corrections. The child keeps '
      'its existing focus, semantics and interaction. Topic readers enable this '
      'on desktop, where the body already reserves an avatar gutter.',
  examples: [
    StyleguideExample(
      title: 'Bounded avatars',
      description:
          'Scroll through posts of different lengths. Each avatar stays in its '
          'own gutter and leaves with the end of its post.',
      states: const ['Long post', 'Short post', 'Scroll reversal', 'RTL'],
      code: '''DStickySliver(
  sliver: SliverList.builder(
    itemCount: posts.length,
    itemBuilder: (context, index) => Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 48),
          child: postBody(posts[index]),
        ),
        PositionedDirectional(
          start: 0, top: 0, bottom: 0, width: 32,
          child: DSticky(topOffset: 16, child: avatar(posts[index])),
        ),
      ],
    ),
  ),
)''',
      builder: (_) => const SizedBox(height: 360, child: _StickyExample()),
    ),
  ],
);

class _StickyExample extends StatefulWidget {
  const _StickyExample();

  @override
  State<_StickyExample> createState() => _StickyExampleState();
}

class _StickyExampleState extends State<_StickyExample> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DScrollBar(
    controller: _scroll,
    child: CustomScrollView(
      controller: _scroll,
      slivers: [
        DStickySliver(
          sliver: SliverList.builder(
            itemCount: 3,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Author ${index + 1}'),
                        for (var line = 0; line < (index == 1 ? 1 : 12); line++)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'The avatar remains visible as you read this '
                              'post, then scrolls away with its final paragraph.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: 32,
                    child: DSticky(
                      topOffset: 16,
                      child: DAvatar(
                        semanticLabel: 'Author ${index + 1}',
                        fallback: DAvatarFallback(child: Text('${index + 1}')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
