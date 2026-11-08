import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/content_route.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/topic_reader.dart';
import 'shell_scope.dart';
import 'topic_inbox_header.dart';
import 'topic_skeleton.dart';
import 'topic_view.dart';

class TopicReaderOutlet extends StatefulWidget {
  const TopicReaderOutlet({
    super.key,
    required this.route,
    required this.registry,
    required this.ordinary,
  });

  final ContentRoute route;
  final PluginRegistry registry;
  final Widget ordinary;

  @override
  State<TopicReaderOutlet> createState() => _TopicReaderOutletState();
}

class _TopicReaderOutletState extends State<TopicReaderOutlet> {
  PluginTopicReader? _reader;
  Object? _identity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(TopicReaderOutlet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    if (!widget.registry.hasTopicReaders) return;
    final shell = ShellScope.read(context);
    final tab = ShellScope.tabOf(context);
    final key = (
      shell,
      tab.siteUrl,
      tab.lease?.session,
      tab.tabId,
      widget.route.topicId,
      widget.route.postNumber,
    );
    if (_identity == key &&
        _reader?.route.topicQuery == widget.route.topicQuery) {
      return;
    }
    _reader?.removeListener(_changed);
    _reader?.close();
    _identity = key;
    _reader = shell.createTopicReader(tab, widget.route)..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _reader?.removeListener(_changed);
    _reader?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ShellScope.tabOf(context);
    return TopicSkeletonScope(
      key: ValueKey((
        tab.siteUrl,
        tab.lease?.session,
        tab.tabId,
        widget.route.topicId,
      )),
      child: _buildReader(context),
    );
  }

  Widget _buildReader(BuildContext context) {
    if (!widget.registry.hasTopicReaders) return widget.ordinary;
    final reader = _reader!;
    if (!reader.isCurrent) return const SizedBox.shrink();
    final shell = ShellScope.read(context);
    final topic = reader.topic;
    if (topic == null ||
        !shell.topicReaderResolved(reader.siteUrl, reader.topicId)) {
      if (shell.topicReaderFailure(reader.siteUrl, reader.topicId) != null) {
        return Center(
          child: DEmpty(
            children: [
              DEmptyHeader(
                children: [DEmptyTitle(context.l10n.couldnTLoadThisTopic)],
              ),
              DEmptyContent(
                children: [
                  DButton(
                    label: Text(context.l10n.retry),
                    onPressed: reader.refreshMetadata,
                  ),
                ],
              ),
            ],
          ),
        );
      }
      final preview = shell.store.read<Topic>(reader.siteUrl, reader.topicId);
      return TopicInboxHeader(
        loading: true,
        title:
            topic?.displayTitle ?? preview?.displayTitle ?? reader.route.title,
        siteUrl: reader.siteUrl,
        route: reader.route,
        topic: topic,
        preview: preview,
        registry: widget.registry,
        canReturnToSidebar: true,
        keepTopicListOpen: false,
        bodyBuilder: (header) => TopicLoadingSkeleton(header: header),
      );
    }
    return widget.registry.buildTopicReader(
          context,
          TopicReaderProbe(
            siteUrl: reader.siteUrl,
            topic: topic,
            config: shell.siteConfigFor(reader.siteUrl),
          ),
          reader,
        ) ??
        widget.ordinary;
  }
}

class PluginTopicPost extends StatelessWidget {
  const PluginTopicPost({
    super.key,
    required this.reader,
    required this.postId,
    this.layout = TopicPostLayout.standard,
    this.contentExpanded = true,
    this.enableDoubleTapReaction = true,
    this.authorBadges = const [],
    this.leading,
    this.bodyLeading,
    this.footerLeading,
    this.onBodyPressed,
    this.bodyActionLabel,
  });

  final PluginTopicReader reader;
  final int postId;
  final TopicPostLayout layout;
  final bool contentExpanded;
  final bool enableDoubleTapReaction;
  final List<Widget> authorBadges;
  final Widget? leading;
  final Widget? bodyLeading;
  final Widget? footerLeading;
  final VoidCallback? onBodyPressed;
  final String? bodyActionLabel;

  @override
  Widget build(BuildContext context) =>
      !reader.isCurrent || reader.post(postId) == null
      ? const SizedBox.shrink()
      : TopicPostPresentation(
          siteUrl: reader.siteUrl,
          topicId: reader.topicId,
          postId: postId,
          layout: layout,
          contentExpanded: contentExpanded,
          enableDoubleTapReaction: enableDoubleTapReaction,
          authorBadges: authorBadges,
          leading: leading,
          bodyLeading: bodyLeading,
          footerLeading: footerLeading,
          onBodyPressed: onBodyPressed,
          bodyActionLabel: bodyActionLabel,
        );
}

class PluginTopicHeader extends StatelessWidget {
  const PluginTopicHeader({
    super.key,
    required this.reader,
    required this.bodyBuilder,
    this.controls,
  });

  final PluginTopicReader reader;
  final Widget Function(DPageHeaderGeometry header) bodyBuilder;
  final Widget? controls;

  @override
  Widget build(BuildContext context) => TopicInboxHeader(
    title: reader.topic?.displayTitle ?? reader.route.title,
    siteUrl: reader.siteUrl,
    topic: reader.topic,
    route: reader.route,
    registry: ShellScope.read(context).plugins.registry,
    canReturnToSidebar: true,
    keepTopicListOpen: false,
    headerControls: controls,
    bodyBuilder: bodyBuilder,
  );
}
