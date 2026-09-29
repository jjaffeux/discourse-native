import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/topic_scroll_capture.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'diagnostics_text.dart';

const double diagnosticsPanelWidth = 440;

const double diagnosticsPanelMinWidth = 320;

class DiagnosticsPanel extends StatefulWidget {
  const DiagnosticsPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.plugins = const [],
  });

  final DiagnosticsController controller;
  final VoidCallback onClose;
  final List<DiagnosticsPlugin> plugins;

  @override
  State<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _timeline = ScrollController();
  late PluginDiagnosticsReadExportHost _pluginDiagnostics;
  DiagnosticsPlugin? _selectedPlugin;
  bool _showTopicScrollCapture = false;

  @override
  void initState() {
    super.initState();
    _pluginDiagnostics = PluginDiagnosticsReadExportHost(widget.controller);
    _showTopicScrollCapture =
        widget.controller.topicScrollCapture.state.hasCapture;
  }

  @override
  void didUpdateWidget(DiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _pluginDiagnostics = PluginDiagnosticsReadExportHost(widget.controller);
      _search.text = widget.controller.panelState.query;
      _showTopicScrollCapture =
          widget.controller.topicScrollCapture.state.hasCapture;
    }
    if (!widget.plugins.contains(_selectedPlugin)) {
      final selectedId = _selectedPlugin?.diagnosticsId;
      _selectedPlugin = selectedId == null
          ? null
          : widget.plugins
                .where((plugin) => plugin.diagnosticsId == selectedId)
                .firstOrNull;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (!_showTopicScrollCapture &&
              _selectedPlugin == null &&
              widget.controller.panelState.selectedEventId != null) {
            widget.controller.selectEvent(null);
          } else {
            widget.onClose();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        key: const ValueKey('diagnostics-panel'),
        color: theme.shell.panel,
        elevation: 12,
        child: SafeArea(
          left: false,
          child: ListenableBuilder(
            key: const ValueKey('diagnostics-events-listener'),
            listenable: Listenable.merge([
              widget.controller.eventsListenable,
              widget.controller.panelStateListenable,
            ]),
            builder: (context, _) {
              final panelState = widget.controller.panelState;
              _syncSearchText(panelState.query);
              final selected = _eventById(
                // In frozen mode this resolves against the held snapshot, so
                // an in-flight request completing cannot mutate the detail
                // the reader deliberately paused to inspect.
                widget.controller.visibleEvents,
                panelState.selectedEventId,
              );

              return Column(
                children: [
                  _PanelHeader(
                    frozen: panelState.frozen,
                    showingDetail:
                        !_showTopicScrollCapture &&
                        _selectedPlugin == null &&
                        selected != null,
                    showGeneralActions:
                        !_showTopicScrollCapture && _selectedPlugin == null,
                    onBack: () => widget.controller.selectEvent(null),
                    onToggleFrozen: () =>
                        widget.controller.setFrozen(!panelState.frozen),
                    onCopyReport: _copyReport,
                    onClear: _confirmClear,
                    onClose: widget.onClose,
                  ),
                  DSeparator(space: 1, color: theme.shell.divider),
                  _DiagnosticsTabs(
                    plugins: widget.plugins,
                    selectedPlugin: _selectedPlugin,
                    topicScrollSelected: _showTopicScrollCapture,
                    onGeneralSelected: () => setState(() {
                      _showTopicScrollCapture = false;
                      _selectedPlugin = null;
                    }),
                    onTopicScrollSelected: () => setState(() {
                      _showTopicScrollCapture = true;
                      _selectedPlugin = null;
                    }),
                    onPluginSelected: (plugin) => setState(() {
                      _showTopicScrollCapture = false;
                      _selectedPlugin = plugin;
                    }),
                  ),
                  DSeparator(space: 1, color: theme.shell.divider),
                  Expanded(
                    child: _showTopicScrollCapture
                        ? _TopicScrollCapturePanel(
                            controller: widget.controller.topicScrollCapture,
                            onCaptureStarted: widget.onClose,
                          )
                        : _selectedPlugin != null
                        ? _selectedPlugin!.buildDiagnostics(
                            context,
                            _pluginDiagnostics,
                          )
                        : selected == null
                        ? _buildTimeline(context)
                        : _EventDetail(
                            event: selected,
                            onCopy: () => _copyEvent(selected),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _syncSearchText(String query) {
    if (_search.text == query) return;
    _search.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final events = widget.controller.events;
    final panelState = widget.controller.panelState;
    final sources = <String>{
      ...events.map((event) => event.source),
      ...panelState.sources,
    }.toList()..sort();
    final visible = widget.controller.visibleEvents.reversed.toList(
      growable: false,
    );

    return Column(
      children: [
        FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: DToggleGroup<DiagnosticsKindFilter>(
                    key: const ValueKey('diagnostics-kind-filter'),
                    items: [
                      DToggleGroupItem(
                        value: DiagnosticsKindFilter.all,
                        child: Text(context.l10n.all),
                      ),
                      DToggleGroupItem(
                        value: DiagnosticsKindFilter.requests,
                        child: Text(context.l10n.requests),
                      ),
                      DToggleGroupItem(
                        value: DiagnosticsKindFilter.errors,
                        child: Text(context.l10n.errors),
                      ),
                    ],
                    values: [panelState.kindFilter],
                    allowEmptySelection: false,
                    variant: DToggleVariant.outline,
                    spacing: 0,
                    onChanged: (selection) {
                      widget.controller.setKindFilter(selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  style: Theme.of(context).textTheme.bodyMedium,
                  key: const ValueKey('diagnostics-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.l10n.searchDiagnostics,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: DIcon(DIcons.magnifyingGlass, size: 18),
                    ),
                    suffixIcon: panelState.query.isEmpty
                        ? null
                        : DButton.iconOnly(
                            onPressed: () {
                              _search.clear();
                              widget.controller.setQuery('');
                            },
                            variant: DButtonVariant.ghost,
                            tooltip: context.l10n.clearSearch,
                            icon: const DIcon(DIcons.xmark),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: widget.controller.setQuery,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MultiSelectMenu(
                        key: const ValueKey('diagnostics-severity-filter'),
                        label: context.l10n.severity,
                        values: DiagnosticSeverity.values
                            .map((severity) => severity.name)
                            .toList(),
                        selected: panelState.severities
                            .map((severity) => severity.name)
                            .toSet(),
                        onToggle: (value) {
                          final severity = DiagnosticSeverity.values.byName(
                            value,
                          );
                          final selected = Set<DiagnosticSeverity>.of(
                            panelState.severities,
                          );
                          _toggleSet(selected, severity);
                          widget.controller.setSeverities(selected);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MultiSelectMenu(
                        key: const ValueKey('diagnostics-source-filter'),
                        label: context.l10n.source,
                        values: sources,
                        selected: panelState.sources,
                        onToggle: (value) {
                          final selected = Set<String>.of(panelState.sources);
                          _toggleSet(selected, value);
                          widget.controller.setSources(selected);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyTimeline(hasEvents: events.isNotEmpty)
              : DScrollBar(
                  controller: _timeline,
                  child: ListView.builder(
                    key: const ValueKey('diagnostics-timeline'),
                    controller: _timeline,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final event = visible[index];
                      return _EventRow(
                        key: ValueKey('diagnostic-event-${event.id}'),
                        event: event,
                        onTap: () => widget.controller.selectEvent(event.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _copyEvent(DiagnosticEvent event) async {
    await Clipboard.setData(
      ClipboardData(text: widget.controller.formatEvent(event)),
    );
    if (mounted) _showCopied(appL10n.eventCopied);
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(
      ClipboardData(
        text: widget.controller.buildJsonReport(
          widget.controller.visibleEvents,
        ),
      ),
    );
    if (mounted) _showCopied(appL10n.filteredReportCopied);
  }

  Future<void> _confirmClear() async {
    final controller = widget.controller;
    final confirmed = await showDiscourseAlertDialog<bool>(
      context: context,
      title: Text(appL10n.clearDiagnosticsHistory),
      description: Text(
        appL10n.thisRemovesTheRecordedRequestsAndErrorsFromThisDeviceRequests,
      ),
      cancelLabel: Text(appL10n.cancel),
      actionLabel: Text(appL10n.clearHistory),
      cancelResult: false,
      actionResult: true,
      actionVariant: DButtonVariant.destructive,
    );
    // The app can replace its diagnostics owner while this dialog is open.
    // A confirmation describing the old history must never clear the new
    // controller's events.
    if (confirmed != true ||
        !mounted ||
        !identical(widget.controller, controller)) {
      return;
    }
    await controller.clear();
    if (mounted && identical(widget.controller, controller)) {
      controller.setFrozen(false);
    }
  }

  void _showCopied(String message) {
    DToast.show(context, message, id: 'diagnostics-copy');
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.frozen,
    required this.showingDetail,
    this.showGeneralActions = true,
    required this.onBack,
    required this.onToggleFrozen,
    required this.onCopyReport,
    required this.onClear,
    required this.onClose,
  });

  final bool frozen;
  final bool showingDetail;
  final bool showGeneralActions;
  final VoidCallback onBack;
  final VoidCallback onToggleFrozen;
  final VoidCallback onCopyReport;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(width: DResizableHandle.visualExtent()),
          if (showingDetail)
            DButton.iconOnly(
              key: const ValueKey('diagnostics-detail-back'),
              onPressed: onBack,
              variant: DButtonVariant.ghost,
              tooltip: context.l10n.backToDiagnostics,
              icon: const DIcon(DIcons.arrowLeft),
            ),
          Expanded(
            child: Text(
              showingDetail
                  ? context.l10n.eventDetails
                  : context.l10n.diagnostics,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (showGeneralActions) ...[
            DButton.iconOnly(
              key: const ValueKey('diagnostics-freeze'),
              onPressed: onToggleFrozen,
              variant: DButtonVariant.ghost,
              tooltip: frozen
                  ? context.l10n.resumeLiveUpdates
                  : context.l10n.freezeVisibleEvents,
              icon: DIcon(frozen ? DIcons.play : DIcons.snowflake),
            ),
            DButton.iconOnly(
              key: const ValueKey('diagnostics-copy-report'),
              onPressed: onCopyReport,
              variant: DButtonVariant.ghost,
              tooltip: context.l10n.copyFilteredReport,
              icon: const DIcon(DIcons.copy),
            ),
            DButton.iconOnly(
              key: const ValueKey('diagnostics-clear'),
              onPressed: onClear,
              variant: DButtonVariant.ghost,
              tooltip: context.l10n.clearHistory,
              icon: const DIcon(DIcons.trashCan),
            ),
          ],
          DButton.iconOnly(
            key: const ValueKey('diagnostics-close'),
            onPressed: onClose,
            variant: DButtonVariant.ghost,
            tooltip: context.l10n.closeDiagnostics,
            icon: const DIcon(DIcons.xmark),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _DiagnosticsTabs extends StatelessWidget {
  const _DiagnosticsTabs({
    required this.plugins,
    required this.selectedPlugin,
    required this.topicScrollSelected,
    required this.onGeneralSelected,
    required this.onTopicScrollSelected,
    required this.onPluginSelected,
  });

  final List<DiagnosticsPlugin> plugins;
  final DiagnosticsPlugin? selectedPlugin;
  final bool topicScrollSelected;
  final VoidCallback onGeneralSelected;
  final VoidCallback onTopicScrollSelected;
  final ValueChanged<DiagnosticsPlugin> onPluginSelected;

  @override
  Widget build(BuildContext context) {
    final selected = topicScrollSelected
        ? 1
        : selectedPlugin == null
        ? 0
        : plugins.indexOf(selectedPlugin!) + 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: DTabs<int>.controlled(
          value: selected,
          onChanged: (index) {
            if (index == null) return;
            if (index == 0) {
              onGeneralSelected();
            } else if (index == 1) {
              onTopicScrollSelected();
            } else {
              onPluginSelected(plugins[index - 2]);
            }
          },
          children: [
            DTabList<int>(
              key: const ValueKey('diagnostics-top-level-tabs'),
              children: [
                DTabTrigger(value: 0, child: Text(context.l10n.general)),
                DTabTrigger(
                  value: 1,
                  child: Text(context.l10n.scrollPerformance),
                ),
                for (var index = 0; index < plugins.length; index++)
                  DTabTrigger(
                    value: index + 2,
                    child: Text(plugins[index].diagnosticsLabel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicScrollCapturePanel extends StatelessWidget {
  const _TopicScrollCapturePanel({
    required this.controller,
    required this.onCaptureStarted,
  });

  final TopicScrollCaptureController controller;
  final VoidCallback onCaptureStarted;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      return ListView(
        key: const ValueKey('topic-scroll-capture-panel'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.l10n.scrollPerformanceCapture,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.recordScrollingInATopicTopicListOrUsersDirectoryThen,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (state.isRecording) ...[
            _CaptureStatus(
              label: context.l10n.recording,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.closeDiagnosticsReproduceTheIssueInATopicTopicListOr(
                (controller.maximumDuration.inMinutes).toString(),
                (controller.maximumEvents).toString(),
              ),
            ),
            const SizedBox(height: 16),
            DButton(
              key: const ValueKey('topic-scroll-capture-stop'),
              label: Text(context.l10n.stopCapture),
              onPressed: controller.stop,
              variant: DButtonVariant.destructive,
            ),
          ] else if (state.hasCapture) ...[
            _CaptureStatus(
              label: _captureStopLabel(state.stopReason),
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _CaptureSummary(state: state),
            const SizedBox(height: 16),
            DButton(
              key: const ValueKey('topic-scroll-performance-copy'),
              label: Text(context.l10n.copyPerformanceReport),
              onPressed: () => _copyCapture(context, compact: true),
              icon: const DIcon(DIcons.copy),
              variant: DButtonVariant.primary,
            ),
            const SizedBox(height: 8),
            DButton(
              key: const ValueKey('topic-scroll-capture-copy'),
              label: Text(context.l10n.copyFullJSONCapture),
              onPressed: () => _copyCapture(context, compact: false),
              icon: const DIcon(DIcons.copy),
            ),
            const SizedBox(height: 8),
            DButton(
              key: const ValueKey('topic-scroll-capture-restart'),
              label: Text(context.l10n.startANewCapture),
              onPressed: () => _startCapture(context),
            ),
            DButton(
              key: const ValueKey('topic-scroll-capture-clear'),
              label: Text(context.l10n.discardCapture),
              onPressed: controller.clear,
              variant: DButtonVariant.destructive,
            ),
          ] else ...[
            Text(
              context
                  .l10n
                  .theTraceIncludesTopicListRowBuildsAndScrollBookkeepingTopic,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DButton(
              key: const ValueKey('topic-scroll-capture-start'),
              label: Text(context.l10n.startCapture),
              onPressed: () => _startCapture(context),
              variant: DButtonVariant.primary,
            ),
          ],
        ],
      );
    },
  );

  void _startCapture(BuildContext context) {
    controller.start(displayRefreshRate: View.of(context).display.refreshRate);
    onCaptureStarted();
  }

  Future<void> _copyCapture(
    BuildContext context, {
    required bool compact,
  }) async {
    final report = await (compact
        ? controller.buildPerformanceReport()
        : controller.buildJsonReport());
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    DToast.show(
      context,
      compact ? appL10n.performanceReportCopied : appL10n.scrollCaptureCopied,
      id: 'diagnostics-copy',
    );
  }
}

class _CaptureStatus extends StatelessWidget {
  const _CaptureStatus({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DIcon(DIcons.circle, size: 10, color: color),
      const SizedBox(width: 8),
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    ],
  );
}

class _CaptureSummary extends StatelessWidget {
  const _CaptureSummary({required this.state});

  final TopicScrollCaptureState state;

  @override
  Widget build(BuildContext context) {
    final duration = state.duration ?? Duration.zero;
    final seconds = duration.inMilliseconds / 1000;
    return Text(
      context.l10n.eventsOverSTopicEventsFramesSlowBuildsSlowRastersBudget(
        (state.eventCount).toString(),
        (seconds.toStringAsFixed(1)).toString(),
        (state.topicEventCount).toString(),
        (state.frameCount).toString(),
        (state.slowBuildFrameCount).toString(),
        (state.slowRasterFrameCount).toString(),
        ((state.frameBudgetMicroseconds / 1000).toStringAsFixed(2)).toString(),
        (state.displayRefreshRate.toStringAsFixed(0)).toString(),
      ),
      key: const ValueKey('topic-scroll-capture-summary'),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

String _captureStopLabel(TopicScrollCaptureStopReason? reason) =>
    switch (reason) {
      TopicScrollCaptureStopReason.durationLimit => appL10n.stoppedAtTimeLimit,
      TopicScrollCaptureStopReason.eventLimit => appL10n.stoppedAtEventLimit,
      TopicScrollCaptureStopReason.manual || null => appL10n.captureReady,
    };

class _MultiSelectMenu extends StatelessWidget {
  const _MultiSelectMenu({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final description = selected.isEmpty
        ? label
        : selected.length == 1
        ? selected.single
        : '$label (${selected.length})';

    return Builder(
      builder: (menuContext) {
        final ValueChanged<String> onSelect = onToggle;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: context.l10n.filterBy(
                (label.toLowerCase()).toString(),
              ),
              width: 280,
              children: [
                for (final value in values)
                  DDropdownMenuCheckboxItem(
                    checked: selected.contains(value),
                    closeOnSelect: true,
                    onChanged: (_) => onSelect(value),
                    child: Text(sentenceCase(value)),
                  ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (triggerContext, state) => DButton(
                label: Text(sentenceCase(description)),
                icon: const DIcon(DIcons.filter),
                semanticLabel: context.l10n.filterBy((label).toString()),
                variant: DButtonVariant.outline,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                onPressed: values.isNotEmpty ? state.toggle : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event, required this.onTap});

  final DiagnosticEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _isError(event);
    final color = error
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final methodFontSize =
        theme.textTheme.labelSmall?.fontSize ?? DiscourseTypography.xs;
    final methodTextScale =
        MediaQuery.textScalerOf(context).scale(methodFontSize) / methodFontSize;

    return Semantics(
      button: true,
      label: _eventSemantics(event),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.shell.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40 * methodTextScale,
                child: Text(
                  _eventMethod(event),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _eventTitle(event),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${diagnosticTimeText(event.timestampUtc)}  ·  ${event.source}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _eventStatus(event),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _eventDuration(event),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const DIcon(DIcons.chevronRight, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event, required this.onCopy});

  final DiagnosticEvent event;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final json = event.toJson();
    final entries = json.entries.toList();

    return ListView(
      key: ValueKey('diagnostic-detail-${event.id}'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventTitle(event),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sentenceCase(event.severity.name)} · ${event.source}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            DButton(
              key: const ValueKey('diagnostics-copy-event'),
              label: Text(context.l10n.copy),
              onPressed: onCopy,
              icon: const DIcon(DIcons.copy),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in entries)
          if (entry.value != null)
            _DetailField(name: entry.key, value: entry.value),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.name, required this.value});

  final String name;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final long =
        name.toLowerCase().contains('stack') ||
        value is Map ||
        value is Iterable;
    final rendered = diagnosticValueText(value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sentenceCase(splitIdentifier(name)),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            rendered,
            style:
                (long ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                    ?.copyWith(fontFamily: long ? 'monospace' : null),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.hasEvents});

  final bool hasEvents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(
              hasEvents ? DIcons.filter : DIcons.bug,
              size: 30,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasEvents
                  ? context.l10n.noMatchingEvents
                  : context.l10n.noDiagnosticsYet,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              hasEvents
                  ? context.l10n.changeTheFiltersOrSearchToSeeMore
                  : context.l10n.requestsLogsAndOperationalErrorsWillAppearHere,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DiagnosticEvent? _eventById(List<DiagnosticEvent> events, String? id) {
  if (id == null) return null;
  for (final event in events) {
    if (event.id == id) return event;
  }
  return null;
}

void _toggleSet<T>(Set<T> values, T value) {
  if (!values.remove(value)) values.add(value);
}

bool _isError(DiagnosticEvent event) => event.isError;

String _eventMethod(DiagnosticEvent event) {
  return switch (event) {
    HttpDiagnosticEvent(:final method) => method,
    DiagnosticLogEvent() => 'LOG',
    ErrorDiagnosticEvent() => 'ERR',
    DiagnosticSessionEvent() => 'APP',
  };
}

String _eventTitle(DiagnosticEvent event) {
  return switch (event) {
    HttpDiagnosticEvent(:final uri) => uri,
    DiagnosticLogEvent(:final name, :final message) =>
      message == null ? name : '$name: $message',
    ErrorDiagnosticEvent(:final errorType, :final message) =>
      '${event.operation ?? errorType}: $message',
    DiagnosticSessionEvent(:final state, :final message) =>
      message ?? appL10n.session((state.name).toString()),
  };
}

String _eventStatus(DiagnosticEvent event) {
  return switch (event) {
    HttpDiagnosticEvent(:final statusCode?) => '$statusCode',
    HttpDiagnosticEvent(:final state) => sentenceCase(state.name),
    DiagnosticLogEvent() => sentenceCase(event.severity.name),
    ErrorDiagnosticEvent() => sentenceCase(event.severity.name),
    DiagnosticSessionEvent(:final state) => sentenceCase(state.name),
  };
}

String _eventDuration(DiagnosticEvent event) {
  if (event case HttpDiagnosticEvent(:final totalDuration?)) {
    final milliseconds = totalDuration.inMicroseconds / 1000;
    return milliseconds < 1000
        ? appL10n.msDiagnosticspanel((milliseconds.round()).toString())
        : '${(milliseconds / 1000).toStringAsFixed(1)} s';
  }
  return '';
}

String _eventSemantics(DiagnosticEvent event) => [
  _eventMethod(event),
  _eventTitle(event),
  _eventStatus(event),
  _eventDuration(event),
].where((part) => part.isNotEmpty).join(', ');
