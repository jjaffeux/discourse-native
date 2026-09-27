import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'chat_channel.dart';
import 'chat_inbox.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// Mobile's combined inbox keeps its filters while visiting a conversation.
class ChatMobileSidebar extends StatelessWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = chat.inboxFilters;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, filters]),
      builder: (context, _) {
        final settings = chat.siteConfigFor(siteUrl).chatSettings;
        final filter = filters.filterFor(siteUrl);
        final channels = chatInboxConversations(chat, siteUrl, filter);
        final error = chat.channelsError(siteUrl);
        final loading = !chat.channelsLoaded(siteUrl) && error == null;
        final colors = DTokens.of(context);
        Widget row(ChatChannel channel) => ValueListenableBuilder<ChatChannel?>(
          key: ValueKey(channel.id),
          valueListenable: chat.channelRef(siteUrl, channel.id),
          builder: (context, current, _) => ChatInboxRow(
            siteUrl: siteUrl,
            channel: current ?? channel,
            onPressed: () => shell.openChannel(channel.id),
          ),
        );
        return LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            // While the chrome stays fixed this view cannot scroll, so the
            // conversation list keeps the primary scroll controller.
            primary: false,
            child: _InboxLayout(
              viewportExtent: viewport.maxHeight,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chat',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: DSpacing.md),
                      ChatInboxFilterBar(siteUrl: siteUrl, filters: filters),
                      const SizedBox(height: DSpacing.sm),
                      DSeparator(color: colors.border),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, slot) => loading
                      ? const Center(
                          child: DSpinner(
                            semanticLabel: 'Loading conversations',
                          ),
                        )
                      : error != null && channels.isEmpty
                      ? ChatInboxError(
                          onRetry: () => unawaited(
                            chat.loadChannels(siteUrl, force: true),
                          ),
                        )
                      : channels.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(DSpacing.lg),
                            child: Text(
                              chatInboxEmptyMessage(filter),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : slot.hasBoundedHeight
                      ? ListView.separated(
                          key: PageStorageKey((
                            'mobile-chat-list',
                            siteUrl,
                            filter,
                          )),
                          padding: EdgeInsets.zero,
                          itemCount: channels.length,
                          separatorBuilder: (context, _) =>
                              DSeparator(color: colors.border),
                          itemBuilder: (context, index) => row(channels[index]),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, channel)
                                in channels.indexed) ...[
                              if (index > 0) DSeparator(color: colors.border),
                              row(channel),
                            ],
                          ],
                        ),
                ),
                if (settings.publicChannelsEnabled ||
                    (settings.threadsEnabled && chat.hasThreads(siteUrl)))
                  DCardFooter(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ChatInboxShortcuts(
                      browse: settings.publicChannelsEnabled,
                      myThreads:
                          settings.threadsEnabled && chat.hasThreads(siteUrl),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Fixes the title and filters above the conversations and the shortcuts
/// below them while the conversations keep at least a touch target of
/// [viewportExtent]. A shorter viewport, such as a keyboard over enlarged
/// text, leaves no room for that chrome, so the conversations take their
/// natural height and the enclosing scroll view moves all three together.
///
/// The children are the header, the conversations and an optional footer.
/// The header and footer are measured in the same pass that decides, so the
/// switch follows the kit's control sizes and the text scale exactly. The
/// conversations read the outcome from their constraints: a bounded height is
/// a lazy list's own viewport, an unbounded one asks for every row.
class _InboxLayout extends MultiChildRenderObjectWidget {
  const _InboxLayout({required this.viewportExtent, required super.children});

  final double viewportExtent;

  @override
  _RenderInboxLayout createRenderObject(BuildContext context) =>
      _RenderInboxLayout(viewportExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInboxLayout renderObject,
  ) {
    renderObject.viewportExtent = viewportExtent;
  }
}

class _InboxParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderInboxLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _InboxParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _InboxParentData> {
  _RenderInboxLayout(this._viewportExtent);

  double _viewportExtent;
  set viewportExtent(double value) {
    if (value == _viewportExtent) return;
    _viewportExtent = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _InboxParentData) {
      child.parentData = _InboxParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final list = childAfter(header)!;
    final footer = childAfter(list);
    final width = constraints.maxWidth;
    final natural = BoxConstraints.tightFor(width: width);
    header.layout(natural, parentUsesSize: true);
    footer?.layout(natural, parentUsesSize: true);
    final headerExtent = header.size.height;
    final footerExtent = footer?.size.height ?? 0;
    final room = _viewportExtent - headerExtent - footerExtent;
    final double listExtent;
    if (room >= DSpacing.touchTarget) {
      list.layout(BoxConstraints.tightFor(width: width, height: room));
      listExtent = room;
    } else {
      list.layout(natural, parentUsesSize: true);
      listExtent = math.max(room, list.size.height);
    }
    final height = headerExtent + listExtent + footerExtent;
    (header.parentData! as _InboxParentData).offset = Offset.zero;
    (list.parentData! as _InboxParentData).offset = Offset(0, headerExtent);
    if (footer != null) {
      (footer.parentData! as _InboxParentData).offset = Offset(
        0,
        height - footerExtent,
      );
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
