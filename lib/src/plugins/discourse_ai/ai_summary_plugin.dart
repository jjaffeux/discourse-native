import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../site_plugin_api.dart';
import 'ai_summary.dart';
import 'ai_summary_controller.dart';
import 'discourse_ai_services.dart';

/// Native presentation of discourse-ai's topic summary contribution.
final class AiSummaryPlugin
    implements
        SitePlugin,
        TopicRecordPlugin<AiSummaryAvailability>,
        TopicMapActionPlugin {
  const AiSummaryPlugin();

  @override
  String get name => 'discourse-ai';

  @override
  PluginDataKey<AiSummaryAvailability> get record =>
      aiSummaryAvailabilityDataKey;

  @override
  AiSummaryAvailability? readTopic(Map<String, dynamic> json, String siteUrl) =>
      AiSummaryAvailability.fromJson(json);

  @override
  List<Widget> topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final availability = topic.plugins.get(aiSummaryAvailabilityDataKey);
    if (availability?.summarizable != true) return const [];
    return [
      _AiSummaryButton(
        siteUrl: siteUrl,
        topicId: topic.id,
        availability: availability!,
      ),
    ];
  }
}

class _AiSummaryButton extends StatelessWidget {
  const _AiSummaryButton({
    required this.siteUrl,
    required this.topicId,
    required this.availability,
  });

  final String siteUrl;
  final int topicId;
  final AiSummaryAvailability availability;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('ai-topic-summary-button'),
    onPressed: () {
      final controller = PluginScope.require(
        context,
        aiSummaryControllerService,
      );
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => _AiSummaryDialog(
            controller: controller,
            siteUrl: siteUrl,
            topicId: topicId,
            availability: availability,
          ),
        ),
      );
    },
    icon: const DIcon(DIcons.discourseSparkles, size: 15),
    label: const Text('Summarize'),
  );
}

class _AiSummaryDialog extends StatefulWidget {
  const _AiSummaryDialog({
    required this.controller,
    required this.siteUrl,
    required this.topicId,
    required this.availability,
  });

  final AiSummaryController controller;
  final String siteUrl;
  final int topicId;
  final AiSummaryAvailability availability;

  @override
  State<_AiSummaryDialog> createState() => _AiSummaryDialogState();
}

class _AiSummaryDialogState extends State<_AiSummaryDialog> {
  AiTopicSummary? _summary;
  bool _loading = false;
  bool _generated = false;
  bool _regenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool regenerate = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _regenerating = regenerate;
      _error = null;
      if (regenerate) _summary = null;
    });
    try {
      final summary = await widget.controller.load(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        hasCachedSummary: widget.availability.hasCachedSummary || _generated,
        regenerate: regenerate,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _generated = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't generate this summary.");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _regenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;
    return AlertDialog(
      title: const Row(
        children: [
          DIcon(DIcons.discourseSparkles, size: 18),
          SizedBox(width: 8),
          Text('Topic summary'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360, maxWidth: 560),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 160),
          child: switch ((_loading, _error, summary)) {
            (true, _, _) => SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator.adaptive(),
                    const SizedBox(height: 12),
                    Text(
                      _regenerating
                          ? 'Regenerating summary…'
                          : 'Generating summary…',
                    ),
                  ],
                ),
              ),
            ),
            (_, final error?, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(error),
            ),
            (_, _, final summary?) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionArea(
                    child: Text(
                      summary.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: DiscourseTypography.lineHeightCooked,
                      ),
                    ),
                  ),
                  if (summary.outdated) ...[
                    const SizedBox(height: 16),
                    Text(
                      summary.newPostsSinceSummary > 0
                          ? 'This summary is outdated by '
                                '${summary.newPostsSinceSummary} new '
                                '${summary.newPostsSinceSummary == 1 ? 'post' : 'posts'}.'
                          : 'This summary is outdated.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (summary.algorithm case final algorithm?) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Generated with $algorithm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _ => const SizedBox(height: 120),
          },
        ),
      ),
      actions: [
        if (_error != null)
          TextButton(onPressed: _load, child: const Text('Try again')),
        if (summary?.outdated == true && summary?.canRegenerate == true)
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _load(regenerate: true),
            icon: const DIcon(DIcons.arrowsRotate, size: 14),
            label: const Text('Regenerate'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
