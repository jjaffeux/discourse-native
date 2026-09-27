import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'ai_summary.dart';
import 'ai_summary_controller.dart';
import 'discourse_ai_icons.dart';
import 'discourse_ai_services.dart';

final class AiSummaryPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
        TopicRecordPlugin<AiSummaryAvailability>,
        TopicMapActionPlugin,
        TopicRecommendationSourcePlugin {
  const AiSummaryPlugin();

  @override
  String get name => 'discourse-ai';

  @override
  PluginIconCatalog get iconCatalog => discourseAiIconCatalog;

  @override
  PluginDataKey<AiSummaryAvailability> get record =>
      aiSummaryAvailabilityDataKey;

  @override
  AiSummaryAvailability? readTopic(Map<String, dynamic> json, String siteUrl) =>
      AiSummaryAvailability.fromJson(json);

  @override
  List<TopicRecommendationSourceCodec> get topicRecommendationSourceCodecs =>
      const [discourseAiRelatedTopicRecommendationSourceCodec];

  @override
  TopicMapActionContribution topicMapActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final availability = topic.plugins.get(aiSummaryAvailabilityDataKey);
    if (availability?.summarizable != true) {
      return TopicMapActionContribution.none;
    }
    return TopicMapActionContribution(
      replacesSummary: true,
      actions: [
        _AiSummaryButton(
          siteUrl: siteUrl,
          topicId: topic.id,
          availability: availability!,
        ),
      ],
    );
  }
}

const discourseAiRelatedTopicRecommendationSourceId =
    TopicRecommendationSourceId('discourse-ai/related');

const discourseAiRelatedTopicRecommendationSource =
    TopicRecommendationSourceDefinition(
      id: discourseAiRelatedTopicRecommendationSourceId,
      label: 'Related',
      icon: DiscourseAiIcons.sparkles,
    );

const discourseAiRelatedTopicRecommendationSourceCodec =
    DiscourseAiRelatedTopicRecommendationSourceCodec();

final class DiscourseAiRelatedTopicRecommendationSourceCodec
    extends TopicRecommendationSourceCodec {
  const DiscourseAiRelatedTopicRecommendationSourceCodec();

  @override
  TopicRecommendationSourceDefinition get definition =>
      discourseAiRelatedTopicRecommendationSource;

  @override
  Set<String> get legacyStoredIds => const {'related'};

  @override
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json) {
    if (!json.containsKey('related_topics')) return null;
    return List.unmodifiable(jsonObjects(json['related_topics']));
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
  Widget build(BuildContext context) => DButton(
    key: const ValueKey('ai-topic-summary-button'),
    label: const Text('Summarize'),
    onPressed: () {
      final controller = PluginUiScope.require(
        context,
        aiSummaryControllerService,
      );
      final mobile = context.isTouch;
      Widget content() => _AiSummaryDialog(
        controller: controller,
        siteUrl: siteUrl,
        topicId: topicId,
        availability: availability,
        mobile: mobile,
      );
      unawaited(
        mobile
            ? showDSheet<void>(
                context: context,
                side: DSheetSide.bottom,
                builder: (context, sheet) => DSheetContent(
                  side: DSheetSide.bottom,
                  topBottomMaxHeightFactor: .9,
                  children: [
                    const DSheetHeader(
                      children: [DSheetTitle(child: Text('Topic summary'))],
                    ),
                    DSheetBody(child: content()),
                  ],
                ),
              )
            : showDDialog<void>(
                context: context,
                builder: (context, dialog) => content(),
              ),
      );
    },
    icon: const DIcon(DiscourseAiIcons.sparkles),
  );
}

const _genericFailureText = "Couldn't generate this summary.";

/// Upstream's `credit_limit_dialog.message_user` copy. The job's own `message`
/// is a Ruby exception message, which upstream never shows either.
String _streamFailureText(AiSummaryStreamFailure failure) {
  if (!failure.creditLimitExceeded) return _genericFailureText;
  return switch (failure.resetTime) {
    final reset? =>
      'This community has reached its AI credit limit for today. Please try '
          'again after $reset or contact your site administrator for more '
          'information.',
    null =>
      'This community has reached its AI credit limit for today. Responses '
          'will be unavailable until your limit resets. Please contact your '
          'site administrator for more information.',
  };
}

class _AiSummaryDialog extends StatefulWidget {
  const _AiSummaryDialog({
    required this.controller,
    required this.siteUrl,
    required this.topicId,
    required this.availability,
    required this.mobile,
  });

  final bool mobile;
  final AiSummaryController controller;
  final String siteUrl;
  final int topicId;
  final AiSummaryAvailability availability;

  @override
  State<_AiSummaryDialog> createState() => _AiSummaryDialogState();
}

class _AiSummaryDialogState extends State<_AiSummaryDialog> {
  AiSummaryRequest? _request;
  AiTopicSummary? _summary;
  String? _cooked;
  bool _loading = false;
  bool _generated = false;
  bool _regenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
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
      final request = widget.controller.load(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        hasCachedSummary: widget.availability.hasCachedSummary || _generated,
        regenerate: regenerate,
      );
      _request = request;
      final summary = await request.result;
      if (!mounted) return;
      _generated = true;
      final cooked = await widget.controller.cook(
        siteUrl: widget.siteUrl,
        raw: summary.text,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _cooked = cooked;
      });
    } on AiSummaryCancelled {
      // Dismissal already owns the dialog's next state.
    } on AiSummaryStreamFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = _streamFailureText(failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _genericFailureText);
    } finally {
      _request = null;
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
    final content = switch ((_loading, _error, summary)) {
      (true, _, _) => SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DSpinner(size: DSpacing.xl),
              const SizedBox(height: 12),
              Text(
                _regenerating ? 'Regenerating summary…' : 'Generating summary…',
              ),
            ],
          ),
        ),
      ),
      (_, final error?, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(error),
      ),
      (_, _, final summary?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RouteAwareSelectionArea(
            child: CookedHtml(
              html: _cooked!,
              siteUrl: widget.siteUrl,
              textStyle: theme.textTheme.bodyMedium?.copyWith(
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
      _ => const SizedBox(height: 120),
    };
    final actions = <Widget>[
      if (_error != null)
        DButton(label: const Text('Try again'), onPressed: _load),
      if (summary?.outdated == true && summary?.canRegenerate == true)
        DButton(
          label: const Text('Regenerate'),
          onPressed: _loading ? null : () => _load(regenerate: true),
          icon: const DIcon(DIcons.arrowsRotate),
        ),
      DButton(
        label: const Text('Close'),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
    final dialog = widget.mobile
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              DSheetFooter(children: actions),
            ],
          )
        : DDialogContent(
            maxWidth: 608,
            showCloseButton: false,
            children: [
              const DDialogHeader(
                children: [DDialogTitle(child: Text('Topic summary'))],
              ),
              DDialogScrollArea(child: content),
              DDialogFooter(children: actions),
            ],
          );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _request?.cancel();
      },
      child: dialog,
    );
  }
}
