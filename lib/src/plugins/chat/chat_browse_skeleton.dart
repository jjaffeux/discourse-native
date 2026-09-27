import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';

/// Leaves directory navigation usable while the rows share a loading pulse.
class ChatBrowseSkeleton extends StatelessWidget {
  const ChatBrowseSkeleton({
    super.key,
    required this.page,
    this.rows = 6,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
  });

  final ChatBrowsePage page;
  final int rows;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRows);

  Widget _buildRows(BuildContext context, BoxConstraints constraints) {
    final threads = page == ChatBrowsePage.threads;
    final channels = page == ChatBrowsePage.channels;
    final content = DSkeletonRegion(
      key: ValueKey('chat-browse-${page.name}-skeleton'),
      semanticsLabel: 'Loading ${page.name}',
      color: skeletonFill(context),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++) ...[
            const DSeparator(),
            DItem(
              shape: DItemShape.fullWidth,
              padding: threads && constraints.maxWidth < 600
                  ? const EdgeInsets.symmetric(vertical: DSpacing.md)
                  : null,
              children: [
                if (!threads)
                  DItemMedia(
                    child: DSkeleton(
                      width: channels ? 32 : 40,
                      height: channels ? 32 : 40,
                      borderRadius: BorderRadius.circular(DRadius.bubble),
                    ),
                  ),
                DItemContent(
                  spacing: DSpacing.sm,
                  children: [
                    if (threads) const DSkeleton(width: 80, height: 12),
                    FractionallySizedBox(
                      widthFactor: row.isEven ? .6 : .45,
                      alignment: AlignmentDirectional.centerStart,
                      child: const DSkeleton(height: 14),
                    ),
                    Row(
                      spacing: DSpacing.sm,
                      children: [
                        if (threads) const DSkeleton.circle(diameter: 18),
                        Expanded(
                          child: FractionallySizedBox(
                            widthFactor: row.isEven ? .8 : .65,
                            alignment: AlignmentDirectional.centerStart,
                            child: const DSkeleton(height: 12),
                          ),
                        ),
                        if (threads) const DSkeleton(width: 44, height: 12),
                      ],
                    ),
                  ],
                ),
                if (channels)
                  DItemActions(
                    children: [
                      DSkeleton(
                        width: 64,
                        height: 32,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    return scrollable
        ? SingleChildScrollView(padding: padding, child: content)
        : Padding(padding: padding, child: content);
  }
}
