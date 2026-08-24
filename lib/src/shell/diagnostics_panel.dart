import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../diagnostics/diagnostics_persistence.dart';
import '../diagnostics/resenha_report_exporter.dart';
import '../plugins/resenha/resenha_diagnostics.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'diagnostics_text.dart';
import 'resenha_diagnostics_view.dart';

/// The initial width used by both the docked diagnostics sidebar and the
/// non-phone overlay.
const double diagnosticsPanelWidth = 440;

/// The bounds for a user-selected diagnostics panel width. The shell may
/// further constrain the preferred width when the current window is narrow.
const double diagnosticsPanelMinWidth = 320;
const double diagnosticsPanelMaxWidth = 720;

/// A live, searchable view over the app-wide diagnostics recorder.
///
/// Filtering lives in the app-owned diagnostics controller, so it survives
/// navigation, site-controller replacement, and responsive relocation without
/// making every request notify the rest of the shell.
class DiagnosticsPanel extends StatefulWidget {
  const DiagnosticsPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.resenhaController,
    this.resenhaReportExporter,
    this.resenhaClipboardByteLimit = resenhaDiagnosticsClipboardByteLimit,
  });

  final DiagnosticsController controller;
  final VoidCallback onClose;
  final ResenhaDiagnosticsController? resenhaController;
  final ResenhaReportExporter? resenhaReportExporter;
  final int resenhaClipboardByteLimit;

  @override
  State<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _timeline = ScrollController();
  final ResenhaDiagnosticsTimelineProjection _resenhaTimeline =
      ResenhaDiagnosticsTimelineProjection();
  late final ResenhaReportExporter _resenhaReportExporter =
      widget.resenhaReportExporter ?? NativeResenhaReportExporter();
  bool _showResenha = false;

  @override
  void didUpdateWidget(DiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _search.text = widget.controller.panelState.query;
    }
    if (!identical(widget.controller, oldWidget.controller) ||
        !identical(widget.resenhaController, oldWidget.resenhaController)) {
      _resenhaTimeline.clear();
    }
    if (widget.resenhaController == null) _showResenha = false;
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
          if (!_showResenha &&
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
                    showingDetail: !_showResenha && selected != null,
                    showGeneralActions: !_showResenha,
                    onBack: () => widget.controller.selectEvent(null),
                    onToggleFrozen: () =>
                        widget.controller.setFrozen(!panelState.frozen),
                    onCopyReport: _copyReport,
                    onClear: _confirmClear,
                    onClose: widget.onClose,
                  ),
                  Divider(height: 1, color: theme.shell.divider),
                  if (widget.resenhaController != null) ...[
                    _DiagnosticsTabs(
                      showResenha: _showResenha,
                      onChanged: (showResenha) {
                        setState(() => _showResenha = showResenha);
                      },
                    ),
                    Divider(height: 1, color: theme.shell.divider),
                  ],
                  Expanded(
                    child: _showResenha
                        ? _buildResenhaTimeline(widget.resenhaController!)
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

  Widget _buildResenhaTimeline(ResenhaDiagnosticsController controller) {
    return ResenhaDiagnosticsView(
      stateListenable: controller.stateListenable,
      eventsListenable: Listenable.merge([
        controller.eventsListenable,
        widget.controller.eventsListenable,
      ]),
      readState: () {
        final state = controller.state;
        return ResenhaDiagnosticsUiState(
          enabled: state.enabled,
          captureId: state.captureId,
          startedAtUtc: state.startedAtUtc,
          retainedBytes: state.retainedBytes,
          droppedRecords: state.droppedRecords,
          truncated: state.truncated,
        );
      },
      readEvents: () => _resenhaTimeline.project(
        controller.eventsTail,
        widget.controller.events,
      ),
      startCapture: controller.startCapture,
      stopCapture: controller.stopCapture,
      clear: controller.clear,
      buildJsonReport: () => _buildResenhaJsonReport(controller),
      buildClipboardReport: (byteLimit) =>
          _buildResenhaClipboardReport(controller, byteLimit),
      writeJsonReportTo: (output) =>
          _writeResenhaJsonReportTo(controller, output),
      exporter: _resenhaReportExporter,
      clipboardByteLimit: widget.resenhaClipboardByteLimit,
    );
  }

  Future<ResenhaClipboardReport> _buildResenhaClipboardReport(
    ResenhaDiagnosticsController controller,
    int byteLimit,
  ) async {
    // A full deep report below the clipboard threshold is cheap enough to
    // build and lets the exact ordinary/deep de-duplicator decide whether the
    // combined report still fits. Above the threshold, never materialize the
    // retained (up to 50 MiB) history merely to throw its oldest bytes away.
    if (controller.state.retainedBytes <= byteLimit) {
      return boundResenhaReportForClipboard(
        await _buildResenhaJsonReport(controller),
        byteLimit: byteLimit,
      );
    }

    final capturedOrdinaryIds = <String>{
      for (final event in controller.eventsTail)
        if (event.data[resenhaDiagnosticsEventIdField] case final String id) id,
    };
    final recent = <_ResenhaReportRecord>[
      for (final event in widget.controller.events)
        if (_isResenhaOrdinaryEvent(event) &&
            !_duplicatesDeepEvent(event, capturedOrdinaryIds))
          _ordinaryResenhaReportRecord(event),
      for (final event in controller.eventsTail)
        (
          timestamp: event.timestampUtc,
          identity: 'deep:${event.identity}',
          line: jsonEncode(resenhaDiagnosticLine(event)),
        ),
    ]..sort(_compareResenhaReportRecords);
    final ordinaryBytes = recent
        .where((record) => record.identity.startsWith('ordinary:'))
        .fold<int>(
          0,
          (total, record) => total + utf8.encode(record.line).length + 1,
        );
    final marker = jsonEncode({
      'kind': 'export_metadata',
      'truncated': true,
      'reason': 'clipboard_limit',
      'deepRetainedBytes': controller.state.retainedBytes,
      'ordinaryRecentBytes': ordinaryBytes,
      'message': 'Recent records only. Use Share/Save for the full report.',
    });
    final retained = <String>[];
    var retainedBytes = utf8.encode('$marker\n').length;
    for (final record in recent.reversed) {
      final lineBytes = utf8.encode('${record.line}\n').length;
      if (retainedBytes + lineBytes > byteLimit) break;
      retained.add(record.line);
      retainedBytes += lineBytes;
    }
    return ResenhaClipboardReport(
      '$marker\n${retained.reversed.join('\n')}',
      truncated: true,
    );
  }

  Future<String> _buildResenhaJsonReport(
    ResenhaDiagnosticsController controller,
  ) async {
    final deepReport = await controller.buildJsonReport();
    final capturedOrdinaryIds = _deepEventIds(deepReport);
    final ordinaryEvents = widget.controller.events.where(
      (event) =>
          _isResenhaOrdinaryEvent(event) &&
          !_duplicatesDeepEvent(event, capturedOrdinaryIds),
    );
    final ordinaryRecords = [
      for (final event in ordinaryEvents) _ordinaryResenhaReportRecord(event),
    ]..sort(_compareResenhaReportRecords);

    final firstLineEnd = deepReport.indexOf('\n');
    if (firstLineEnd < 0) return deepReport;
    final rawHeader = deepReport.substring(0, firstLineEnd);
    final header = _enrichResenhaReportHeader(
      rawHeader,
      ordinaryEventCount: ordinaryRecords.length,
    );

    final deepEvents = deepReport.substring(firstLineEnd + 1);
    return '$header\n${_mergeResenhaReportEvents(deepEvents, ordinaryRecords)}';
  }

  Future<void> _writeResenhaJsonReportTo(
    ResenhaDiagnosticsController controller,
    StringSink output,
  ) async {
    final ordinarySnapshot = widget.controller.events
        .where(_isResenhaOrdinaryEvent)
        .toList(growable: false);
    final candidateIds = <String>{
      for (final event in ordinarySnapshot.whereType<DiagnosticLogEvent>())
        if (event.attributes[resenhaDiagnosticsEventIdField]
            case final String id)
          id,
    };
    final capturedIds = await controller.findRetainedEventIds(candidateIds);
    final ordinaryRecords = [
      for (final event in ordinarySnapshot)
        if (!_duplicatesDeepEvent(event, capturedIds))
          _ordinaryResenhaReportRecord(event),
    ]..sort(_compareResenhaReportRecords);
    final merged = _MergingResenhaReportSink(output, ordinaryRecords);
    await controller.writeJsonReportTo(merged);
    merged.finish();
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
      // Keep an active filter removable after its last event expires or the
      // history is cleared.
      ...panelState.sources,
    }.toList()..sort();
    // The recorder is chronological; latest-first is more useful for a live
    // console and still leaves ordering unambiguous via the timestamps.
    final visible = widget.controller.visibleEvents.reversed.toList(
      growable: false,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<DiagnosticsKindFilter>(
                  key: const ValueKey('diagnostics-kind-filter'),
                  segments: const [
                    ButtonSegment(
                      value: DiagnosticsKindFilter.all,
                      label: Text('All'),
                    ),
                    ButtonSegment(
                      value: DiagnosticsKindFilter.requests,
                      label: Text('Requests'),
                    ),
                    ButtonSegment(
                      value: DiagnosticsKindFilter.errors,
                      label: Text('Errors'),
                    ),
                  ],
                  selected: {panelState.kindFilter},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    widget.controller.setKindFilter(selection.first);
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('diagnostics-search'),
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search diagnostics',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: DIcon(DIcons.magnifyingGlass, size: 18),
                  ),
                  suffixIcon: panelState.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            widget.controller.setQuery('');
                          },
                          icon: const DIcon(DIcons.xmark, size: 16),
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
                      label: 'Severity',
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
                      label: 'Source',
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
        Expanded(
          child: visible.isEmpty
              ? _EmptyTimeline(hasEvents: events.isNotEmpty)
              : Scrollbar(
                  controller: _timeline,
                  child: ListView.builder(
                    key: const ValueKey('diagnostics-timeline'),
                    controller: _timeline,
                    itemExtent: 70,
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
    if (mounted) _showCopied('Event copied');
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(
      ClipboardData(
        text: widget.controller.buildJsonReport(
          widget.controller.visibleEvents,
        ),
      ),
    );
    if (mounted) _showCopied('Filtered report copied');
  }

  Future<void> _confirmClear() async {
    final controller = widget.controller;
    final confirmed = await showDiscourseDialog<bool>(
      context: context,
      builder: (dialogContext) => DiscourseAlertDialog(
        title: const Text('Clear diagnostics history?'),
        content: const Text(
          'This removes the recorded requests and errors from this device. '
          'Requests already in progress will not be restored afterward.',
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            kind: AdaptiveDialogActionKind.destructive,
            child: const Text('Clear history'),
          ),
        ],
      ),
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
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
          if (showingDetail)
            IconButton(
              key: const ValueKey('diagnostics-detail-back'),
              tooltip: 'Back to diagnostics',
              onPressed: onBack,
              icon: const DIcon(DIcons.arrowLeft, size: 18),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              showingDetail ? 'Event details' : 'Diagnostics',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (showGeneralActions) ...[
            IconButton(
              key: const ValueKey('diagnostics-freeze'),
              tooltip: frozen ? 'Resume live updates' : 'Freeze visible events',
              onPressed: onToggleFrozen,
              icon: DIcon(frozen ? DIcons.play : DIcons.snowflake, size: 18),
              color: frozen ? Theme.of(context).colorScheme.primary : null,
            ),
            IconButton(
              key: const ValueKey('diagnostics-copy-report'),
              tooltip: 'Copy filtered report',
              onPressed: onCopyReport,
              icon: const DIcon(DIcons.copy, size: 18),
            ),
            IconButton(
              key: const ValueKey('diagnostics-clear'),
              tooltip: 'Clear history',
              onPressed: onClear,
              icon: const DIcon(DIcons.trashCan, size: 18),
            ),
          ],
          IconButton(
            key: const ValueKey('diagnostics-close'),
            tooltip: 'Close diagnostics',
            onPressed: onClose,
            icon: const DIcon(DIcons.xmark, size: 18),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _DiagnosticsTabs extends StatelessWidget {
  const _DiagnosticsTabs({required this.showResenha, required this.onChanged});

  final bool showResenha;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          key: const ValueKey('diagnostics-top-level-tabs'),
          segments: const [
            ButtonSegment(value: false, label: Text('General')),
            ButtonSegment(value: true, label: Text('Resenha')),
          ],
          selected: {showResenha},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

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

    return PopupMenuButton<String>(
      enabled: values.isNotEmpty,
      tooltip: 'Filter by ${label.toLowerCase()}',
      onSelected: onToggle,
      itemBuilder: (context) => [
        for (final value in values)
          CheckedPopupMenuItem(
            value: value,
            checked: selected.contains(value),
            child: Text(sentenceCase(value)),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Filter by $label',
        value: selected.isEmpty ? 'All' : selected.join(', '),
        child: InputDecorator(
          isEmpty: selected.isEmpty,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          child: Row(
            children: [
              const DIcon(DIcons.filter, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sentenceCase(description),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const DIcon(DIcons.chevronDown, size: 12),
            ],
          ),
        ),
      ),
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

    return Semantics(
      button: true,
      label: _eventSemantics(event),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.shell.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
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
            OutlinedButton.icon(
              key: const ValueKey('diagnostics-copy-event'),
              onPressed: onCopy,
              icon: const DIcon(DIcons.copy, size: 15),
              label: const Text('Copy'),
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
                    ?.copyWith(
                      fontFamily: long ? 'monospace' : null,
                      height: 1.35,
                    ),
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
              hasEvents ? 'No matching events' : 'No diagnostics yet',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              hasEvents
                  ? 'Change the filters or search to see more.'
                  : 'Requests, logs, and operational errors will appear here.',
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
      message ?? 'Session ${state.name}',
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
        ? '${milliseconds.round()} ms'
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

typedef _ResenhaTimelineKey = ({DateTime timestamp, String identity});
typedef _ResenhaTimelineEntry = ({
  Object source,
  _ResenhaTimelineKey key,
  Map<String, Object?> json,
});

/// Retains JSON projections while their immutable recorder events are current.
///
/// Each recorder already publishes its history in stable event objects. Ordered
/// maps preserve the timeline's timestamp-and-identity tie break across updates,
/// leaving each publication as one linear merge instead of a full re-projection
/// and sort.
final class ResenhaDiagnosticsTimelineProjection {
  ResenhaDiagnosticsTimelineProjection({this.onEventProjected});

  @visibleForTesting
  final ValueChanged<String>? onEventProjected;

  final Map<String, _ResenhaTimelineEntry> _deepByIdentity = {};
  final Map<String, _ResenhaTimelineEntry> _ordinaryByIdentity = {};
  final SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> _deepByOrder =
      SplayTreeMap(_compareKeys);
  final SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry>
  _ordinaryByOrder = SplayTreeMap(_compareKeys);

  List<Map<String, Object?>> project(
    List<ResenhaDiagnosticRecord> deepEvents,
    List<DiagnosticEvent> ordinaryEvents,
  ) {
    final capturedOrdinaryIds = <String>{};
    final seenDeep = <String>{};
    for (final event in deepEvents) {
      if (event.data[resenhaDiagnosticsEventIdField] case final String id) {
        capturedOrdinaryIds.add(id);
      }
      final identity = 'deep:${event.captureId}:${event.sequence}';
      seenDeep.add(identity);
      if (identical(_deepByIdentity[identity]?.source, event)) continue;
      _upsert(
        source: event,
        key: (timestamp: event.timestampUtc, identity: identity),
        json: Map.unmodifiable({
          ...event.toJson(),
          'id': identity,
          'origin': 'deep',
        }),
        byIdentity: _deepByIdentity,
        byOrder: _deepByOrder,
      );
    }
    _removeMissing(seenDeep, _deepByIdentity, _deepByOrder);

    final seenOrdinary = <String>{};
    for (final event in ordinaryEvents) {
      if (!_isResenhaOrdinaryEvent(event) ||
          _duplicatesDeepEvent(event, capturedOrdinaryIds)) {
        continue;
      }
      final identity = 'ordinary:${event.id}';
      seenOrdinary.add(identity);
      if (identical(_ordinaryByIdentity[identity]?.source, event)) continue;
      _upsert(
        source: event,
        key: (timestamp: event.timestampUtc, identity: identity),
        json: _ordinaryResenhaEventJson(event),
        byIdentity: _ordinaryByIdentity,
        byOrder: _ordinaryByOrder,
      );
    }
    _removeMissing(seenOrdinary, _ordinaryByIdentity, _ordinaryByOrder);

    return _merge();
  }

  void clear() {
    _deepByIdentity.clear();
    _ordinaryByIdentity.clear();
    _deepByOrder.clear();
    _ordinaryByOrder.clear();
  }

  void _upsert({
    required Object source,
    required _ResenhaTimelineKey key,
    required Map<String, Object?> json,
    required Map<String, _ResenhaTimelineEntry> byIdentity,
    required SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> byOrder,
  }) {
    final held = byIdentity[key.identity];
    if (held != null) byOrder.remove(held.key);

    final entry = (source: source, key: key, json: json);
    byIdentity[key.identity] = entry;
    byOrder[key] = entry;
    onEventProjected?.call(key.identity);
  }

  void _removeMissing(
    Set<String> seen,
    Map<String, _ResenhaTimelineEntry> byIdentity,
    SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> byOrder,
  ) {
    final removed = [
      for (final identity in byIdentity.keys)
        if (!seen.contains(identity)) identity,
    ];
    for (final identity in removed) {
      final entry = byIdentity.remove(identity);
      if (entry != null) byOrder.remove(entry.key);
    }
  }

  List<Map<String, Object?>> _merge() {
    final deep = _deepByOrder.values.iterator;
    final ordinary = _ordinaryByOrder.values.iterator;
    var hasDeep = deep.moveNext();
    var hasOrdinary = ordinary.moveNext();
    final merged = <Map<String, Object?>>[];

    while (hasDeep && hasOrdinary) {
      if (_compareKeys(deep.current.key, ordinary.current.key) <= 0) {
        merged.add(deep.current.json);
        hasDeep = deep.moveNext();
      } else {
        merged.add(ordinary.current.json);
        hasOrdinary = ordinary.moveNext();
      }
    }
    while (hasDeep) {
      merged.add(deep.current.json);
      hasDeep = deep.moveNext();
    }
    while (hasOrdinary) {
      merged.add(ordinary.current.json);
      hasOrdinary = ordinary.moveNext();
    }
    return List.unmodifiable(merged);
  }

  static int _compareKeys(_ResenhaTimelineKey left, _ResenhaTimelineKey right) {
    final timestamp = left.timestamp.compareTo(right.timestamp);
    return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
  }
}

Map<String, Object?> _ordinaryResenhaEventJson(DiagnosticEvent event) {
  final json = <String, Object?>{
    ..._resenhaOrdinaryEventPayload(event),
    'id': 'ordinary:${event.id}',
    'ordinaryEventId': event.id,
    'origin': 'ordinary',
  };
  switch (event) {
    case HttpDiagnosticEvent():
      json['event'] = '${event.method} ${_resenhaHttpPath(event.uri)}';
      json['component'] = 'http';
      json['message'] = [
        event.statusCode,
        event.state.name,
        if (event.totalDuration != null)
          '${event.totalDuration!.inMilliseconds} ms',
      ].join(' · ');
    case ErrorDiagnosticEvent():
      json['event'] = event.operation ?? event.errorType;
      json['component'] = event.source;
    case DiagnosticLogEvent():
      // The view already understands its `name`, `component`, and `message`.
      break;
    case DiagnosticSessionEvent():
      json['event'] = 'session.${event.state.name}';
      json['component'] = event.source;
  }
  return Map.unmodifiable(json);
}

/// Strict projection for data copied from the app-wide recorder into the
/// Resenha surface. General diagnostics may retain a scrubbed exception and
/// response metadata, but those strings can still contain peer addresses or
/// media identifiers. The always-on Resenha stream keeps only allowlisted
/// causal fields; full detail belongs to explicit deep capture.
Map<String, Object?> _resenhaOrdinaryEventPayload(DiagnosticEvent event) =>
    switch (event) {
      HttpDiagnosticEvent() => {
        ...event.commonJson(),
        'method': event.method,
        'uri': _resenhaHttpPath(event.uri),
        'state': event.state.name,
        if (event.statusCode != null) 'statusCode': event.statusCode,
        if (event.headerDuration != null)
          'headerDurationMicros': event.headerDuration!.inMicroseconds,
        if (event.totalDuration != null)
          'totalDurationMicros': event.totalDuration!.inMicroseconds,
        'sentBytes': event.sentBytes,
        'receivedBytes': event.receivedBytes,
        if (event.errorType != null) 'errorType': event.errorType,
      },
      ErrorDiagnosticEvent() => {
        ...event.commonJson(),
        'errorType': event.errorType,
      },
      DiagnosticLogEvent() => event.toJson(),
      DiagnosticSessionEvent() => {
        ...event.commonJson(),
        'state': event.state.name,
      },
    };

String _resenhaHttpPath(String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null) return '<unavailable-path>';
  final path = parsed.path.isEmpty ? '/' : parsed.path;
  final queryNames = parsed.query
      .split('&')
      .map((part) => part.split('=').first)
      .where((name) => name.isNotEmpty)
      .join('&');
  return queryNames.isEmpty ? path : '$path?$queryNames';
}

bool _isResenhaOrdinaryEvent(DiagnosticEvent event) {
  if (event.source == 'resenha' ||
      event.operation == 'resenha' ||
      (event.operation?.startsWith('resenha.') ?? false) ||
      (event.correlationId?.startsWith('resenha-call-') ?? false)) {
    return true;
  }
  if (event case HttpDiagnosticEvent(:final uri)) {
    final path = Uri.tryParse(uri)?.path ?? uri.split('?').first;
    return path.toLowerCase().contains('/resenha/');
  }
  return false;
}

bool _duplicatesDeepEvent(
  DiagnosticEvent event,
  Set<String> capturedOrdinaryIds,
) {
  if (event is! DiagnosticLogEvent) return false;
  final eventId = event.attributes[resenhaDiagnosticsEventIdField];
  return eventId is String && capturedOrdinaryIds.contains(eventId);
}

Set<String> _deepEventIds(String report) {
  final pattern = RegExp(
    '"${RegExp.escape(resenhaDiagnosticsEventIdField)}":"([A-Za-z0-9._:-]+)"',
  );
  return {for (final match in pattern.allMatches(report)) match.group(1)!};
}

typedef _ResenhaReportRecord = ({
  DateTime timestamp,
  String identity,
  String line,
});

_ResenhaReportRecord _ordinaryResenhaReportRecord(DiagnosticEvent event) => (
  timestamp: event.timestampUtc,
  identity: 'ordinary:${event.id}',
  line: jsonEncode({
    'version': resenhaDiagnosticsFormatVersion,
    'record': 'event',
    'origin': 'ordinary',
    'event': _resenhaOrdinaryEventPayload(event),
  }),
);

int _compareResenhaReportRecords(
  _ResenhaReportRecord left,
  _ResenhaReportRecord right,
) {
  final timestamp = left.timestamp.compareTo(right.timestamp);
  return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
}

String _enrichResenhaReportHeader(
  String rawHeader, {
  required int ordinaryEventCount,
}) {
  try {
    final decoded = jsonDecode(rawHeader);
    if (decoded is Map) {
      return jsonEncode({
        for (final entry in decoded.entries) '${entry.key}': entry.value,
        'streams': {
          'ordinary': {
            'retentionHours': diagnosticsRetentionAge.inHours,
            'maximumEvents': diagnosticsRetentionCount,
            'maximumBytes': diagnosticsRetentionBytes,
            'eventCount': ordinaryEventCount,
            'selection': [
              'source=resenha',
              'operation=resenha.*',
              'correlationId=resenha-call-*',
              'HTTP path contains /resenha/',
            ],
          },
          'deep': {
            'requiresExplicitCapture': true,
            'retentionDays': resenhaDiagnosticsRetentionAge.inDays,
            'maximumBytes': resenhaDiagnosticsRetentionBytes,
          },
        },
      });
    }
  } on FormatException {
    // The deep controller currently emits valid JSON. Preserve a future or
    // externally supplied header instead of making report export fail.
  }
  return rawHeader;
}

final class _MergingResenhaReportSink implements StringSink {
  _MergingResenhaReportSink(this.output, this.ordinaryEvents);

  final StringSink output;
  final List<_ResenhaReportRecord> ordinaryEvents;
  final StringBuffer _pending = StringBuffer();
  var _ordinaryIndex = 0;
  var _lineIndex = 0;
  var _finished = false;

  @override
  void write(Object? object) {
    if (_finished) throw StateError('The Resenha report sink is finished.');
    final chunk = '$object';
    var offset = 0;
    while (offset < chunk.length) {
      final newline = chunk.indexOf('\n', offset);
      if (newline < 0) {
        _pending.write(chunk.substring(offset));
        return;
      }
      _pending.write(chunk.substring(offset, newline));
      final line = _pending.toString();
      _pending.clear();
      _emitLine(
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      );
      offset = newline + 1;
    }
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final object in objects) {
      if (!first) write(separator);
      first = false;
      write(object);
    }
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  void finish() {
    if (_finished) return;
    if (_pending.isNotEmpty) _emitLine(_pending.toString());
    while (_ordinaryIndex < ordinaryEvents.length) {
      output.writeln(ordinaryEvents[_ordinaryIndex].line);
      _ordinaryIndex += 1;
    }
    _pending.clear();
    _finished = true;
  }

  void _emitLine(String line) {
    if (_lineIndex == 0) {
      output.writeln(
        _enrichResenhaReportHeader(
          line,
          ordinaryEventCount: ordinaryEvents.length,
        ),
      );
      _lineIndex += 1;
      return;
    }
    if (line.isEmpty) return;
    final deepTimestamp = _resenhaReportLineTimestamp(line);
    if (deepTimestamp != null) {
      while (_ordinaryIndex < ordinaryEvents.length &&
          ordinaryEvents[_ordinaryIndex].timestamp.isBefore(deepTimestamp)) {
        output.writeln(ordinaryEvents[_ordinaryIndex].line);
        _ordinaryIndex += 1;
      }
    }
    output.writeln(line);
    _lineIndex += 1;
  }
}

final RegExp _resenhaReportTimestampPattern = RegExp(
  r'"timestampUtc":"([^"]+)"',
);

String _mergeResenhaReportEvents(
  String deepEvents,
  List<_ResenhaReportRecord> ordinaryEvents,
) {
  if (ordinaryEvents.isEmpty) return deepEvents;
  final output = StringBuffer();
  var ordinaryIndex = 0;
  var offset = 0;
  while (offset < deepEvents.length) {
    final newline = deepEvents.indexOf('\n', offset);
    final end = newline < 0 ? deepEvents.length : newline;
    final line = deepEvents.substring(offset, end);
    offset = newline < 0 ? deepEvents.length : newline + 1;
    if (line.isEmpty) continue;

    final deepTimestamp = _resenhaReportLineTimestamp(line);
    if (deepTimestamp != null) {
      // Deep wins an exact timestamp tie. Its capture sequence is the most
      // precise ordering available for callbacks recorded in the same tick.
      while (ordinaryIndex < ordinaryEvents.length &&
          ordinaryEvents[ordinaryIndex].timestamp.isBefore(deepTimestamp)) {
        output.writeln(ordinaryEvents[ordinaryIndex].line);
        ordinaryIndex += 1;
      }
    }
    output.writeln(line);
  }
  while (ordinaryIndex < ordinaryEvents.length) {
    output.writeln(ordinaryEvents[ordinaryIndex].line);
    ordinaryIndex += 1;
  }
  return output.toString();
}

DateTime? _resenhaReportLineTimestamp(String line) {
  final match = _resenhaReportTimestampPattern.firstMatch(line);
  return match == null ? null : DateTime.tryParse(match.group(1)!)?.toUtc();
}
