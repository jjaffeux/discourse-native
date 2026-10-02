import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';

/// Leaves directory navigation usable while the rows share a loading pulse.
class ChatBrowseSkeleton extends StatelessWidget {
  const ChatBrowseSkeleton({
    super.key,
    required this.page,
    this.rows,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
  });

  final ChatBrowsePage page;

  /// Null fills a bounded viewport, or uses six rows in a scrolling page.
  /// Pagination footers request their smaller, fixed row count explicitly.
  final int? rows;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRows);

  Widget _buildRows(BuildContext context, BoxConstraints constraints) {
    final contentConstraints = constraints.deflate(
      padding.resolve(Directionality.of(context)),
    );
    final rowWidth = contentConstraints.maxWidth;
    final threads = page == ChatBrowsePage.threads;
    final channels = page == ChatBrowsePage.channels;
    final fillViewport = rows == null && constraints.hasBoundedHeight;
    // The two text shapes and their gap are a lower bound on every row's
    // height. Native items own the remaining geometry; clip the extra rows.
    const minimumRowHeight = 14 + 12 + DSpacing.sm;
    final rowCount =
        rows ??
        (fillViewport
            ? math.max(
                1,
                (contentConstraints.maxHeight / minimumRowHeight).ceil(),
              )
            : 6);
    final placeholders = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          const DSeparator(),
          DItem(
            shape: DItemShape.fullWidth,
            padding: rowWidth < 600
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
    );
    final content = DSkeletonRegion(
      key: ValueKey('chat-browse-${page.name}-skeleton'),
      semanticsLabel: context.l10n.loadingChatbrowseskeleton(
        (page.name).toString(),
      ),
      color: skeletonFill(context),
      expand: fillViewport,
      child: fillViewport
          ? ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: placeholders,
              ),
            )
          : placeholders,
    );
    return scrollable
        ? SingleChildScrollView(
            padding: padding,
            child: fillViewport
                ? SizedBox(height: contentConstraints.maxHeight, child: content)
                : content,
          )
        : Padding(padding: padding, child: content);
  }
}
