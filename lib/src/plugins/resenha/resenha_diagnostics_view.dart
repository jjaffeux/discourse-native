import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../diagnostics/diagnostic_event.dart';
import '../../shell/adaptive_dialog_action.dart';
import '../../shell/diagnostics_text.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'resenha_report_exporter.dart';

const int resenhaDiagnosticsClipboardByteLimit = 10 * 1024 * 1024;

/// The small presentation boundary between the diagnostics capture store and
/// its panel. Keeping the view JSON-shaped makes capture records inspectable
/// even as new WebRTC or LiveKit fields are added by the SDKs.
class ResenhaDiagnosticsView extends StatefulWidget {
  const ResenhaDiagnosticsView({
    super.key,
    required this.stateListenable,
    required this.eventsListenable,
    required this.readState,
    required this.readEvents,
    required this.startCapture,
    required this.stopCapture,
    required this.clear,
    required this.buildJsonReport,
    required this.exporter,
    this.buildClipboardReport,
    this.writeJsonReportTo,
    this.clipboardByteLimit = resenhaDiagnosticsClipboardByteLimit,
    this.onEventProjected,
    this.onSearchTextBuilt,
  });

  final Listenable stateListenable;
  final Listenable eventsListenable;
  final ResenhaDiagnosticsUiState Function() readState;
  final List<Map<String, Object?>> Function() readEvents;
  final Future<void> Function() startCapture;
  final Future<void> Function() stopCapture;
  final Future<void> Function() clear;
  final Future<String> Function() buildJsonReport;
  final Future<ResenhaClipboardReport> Function(int byteLimit)?
  buildClipboardReport;
  final ResenhaReportWriter? writeJsonReportTo;
  final ResenhaReportExporter exporter;
  final int clipboardByteLimit;

  @visibleForTesting
  final ValueChanged<String>? onEventProjected;

  @visibleForTesting
  final ValueChanged<String>? onSearchTextBuilt;

  @override
  State<ResenhaDiagnosticsView> createState() => _ResenhaDiagnosticsViewState();
}

class ResenhaDiagnosticsUiState {
  const ResenhaDiagnosticsUiState({
    required this.enabled,
    required this.retainedBytes,
    required this.droppedRecords,
    required this.truncated,
    this.captureId,
    this.startedAtUtc,
  });

  final bool enabled;
  final String? captureId;
  final DateTime? startedAtUtc;
  final int retainedBytes;
  final int droppedRecords;
  final bool truncated;
}

class _ResenhaDiagnosticsViewState extends State<ResenhaDiagnosticsView> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _timeline = ScrollController();
  final Map<String, _CaptureEvent> _eventsById = {};
  String? _selectedId;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      key: const ValueKey('resenha-diagnostics-listener'),
      listenable: Listenable.merge([
        widget.stateListenable,
        widget.eventsListenable,
      ]),
      builder: (context, _) {
        final state = widget.readState();
        final events = _projectEvents(widget.readEvents());
        final selected = _selectedEvent(events);

        return Column(
          children: [
            _CaptureControls(
              state: state,
              busy: _busy,
              exporterLabel: widget.exporter.actionLabel,
              onCaptureChanged: _toggleCapture,
              onCopy: _busy ? null : _copyReport,
              onExport: _busy ? null : _exportReport,
              onClear: _busy || state.enabled ? null : _confirmClear,
            ),
            Divider(height: 1, color: Theme.of(context).shell.divider),
            if (selected == null)
              Expanded(child: _buildTimeline(events))
            else
              Expanded(
                child: _CaptureEventDetail(
                  event: selected,
                  onBack: () => setState(() => _selectedId = null),
                  onCopy: () => _copyEvent(selected),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTimeline(List<_CaptureEvent> events) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? events
        : events
              .where(
                (event) => event.matches(
                  query,
                  onSearchTextBuilt: widget.onSearchTextBuilt,
                ),
              )
              .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            key: const ValueKey('resenha-diagnostics-search'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search Resenha capture',
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: DIcon(DIcons.magnifyingGlass, size: 18),
              ),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('resenha-diagnostics-clear-search'),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const DIcon(DIcons.xmark, size: 16),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _CaptureEmptyState(
                  hasEvents: events.isNotEmpty,
                  recording: widget.readState().enabled,
                )
              : Scrollbar(
                  controller: _timeline,
                  child: ListView.builder(
                    key: const ValueKey('resenha-diagnostics-timeline'),
                    controller: _timeline,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final event = visible[visible.length - index - 1];
                      return _CaptureEventRow(
                        key: ValueKey('resenha-diagnostic-event-${event.id}'),
                        event: event,
                        onTap: () => setState(() => _selectedId = event.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  _CaptureEvent? _selectedEvent(List<_CaptureEvent> events) {
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    for (final event in events) {
      if (event.id == selectedId) return event;
    }
    _selectedId = null;
    return null;
  }

  List<_CaptureEvent> _projectEvents(List<Map<String, Object?>> jsonEvents) {
    final projected = <_CaptureEvent>[];
    final seen = <String>{};
    for (final json in jsonEvents) {
      final id = _eventId(json);
      seen.add(id);
      var event = _eventsById[id];
      if (event == null || !identical(event.json, json)) {
        event = _CaptureEvent(json, id: id);
        _eventsById[id] = event;
        widget.onEventProjected?.call(id);
      }
      projected.add(event);
    }
    _eventsById.removeWhere((id, _) => !seen.contains(id));
    return List.unmodifiable(projected);
  }

  Future<void> _toggleCapture(bool enabled) async {
    if (_busy || enabled == widget.readState().enabled) return;
    if (enabled) {
      final confirmed = await showDiscourseDialog<bool>(
        context: context,
        builder: (dialogContext) => DiscourseAlertDialog(
          title: const Text('Turn on deep Resenha capture?'),
          content: const Text(
            'This records usernames and user IDs, network addresses, raw '
            'SDP and ICE negotiation, media statistics, and device details. '
            'Credentials and other secrets are redacted. Capture stays on '
            'until you turn it off or restart the app.',
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            AdaptiveDialogAction(
              key: const ValueKey('resenha-confirm-start-capture'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              kind: AdaptiveDialogActionKind.primary,
              child: const Text('Turn on capture'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _runBusy(
      enabled ? widget.startCapture : widget.stopCapture,
      successMessage: enabled ? 'Deep capture is on' : 'Deep capture stopped',
    );
  }

  Future<void> _confirmClear() async {
    if (widget.readState().enabled) return;
    final confirmed = await showDiscourseDialog<bool>(
      context: context,
      builder: (dialogContext) => DiscourseAlertDialog(
        title: const Text('Clear Resenha capture?'),
        content: const Text(
          'This permanently removes the retained deep-capture records from '
          'this device.',
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            key: const ValueKey('resenha-confirm-clear-capture'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            kind: AdaptiveDialogActionKind.destructive,
            child: const Text('Clear capture'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBusy(widget.clear, successMessage: 'Resenha capture cleared');
    if (mounted) setState(() => _selectedId = null);
  }

  Future<void> _copyReport() async {
    await _runBusy(() async {
      final clipboardReport = widget.buildClipboardReport == null
          ? boundResenhaReportForClipboard(
              await widget.buildJsonReport(),
              byteLimit: widget.clipboardByteLimit,
            )
          : await widget.buildClipboardReport!(widget.clipboardByteLimit);
      await Clipboard.setData(ClipboardData(text: clipboardReport.text));
      if (mounted) {
        _showMessage(
          clipboardReport.truncated
              ? 'Recent report copied (full report is too large)'
              : 'Resenha report copied',
        );
      }
    });
  }

  Future<void> _copyEvent(_CaptureEvent event) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(event.json),
      ),
    );
    if (mounted) _showMessage('Capture event copied');
  }

  Future<void> _exportReport() async {
    await _runBusy(() async {
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      final origin = renderBox == null
          ? null
          : renderBox.localToGlobal(Offset.zero) & renderBox.size;
      final exporter = widget.exporter;
      final writer = widget.writeJsonReportTo;
      final ResenhaReportExportOutcome outcome;
      if (exporter is StreamingResenhaReportExporter && writer != null) {
        outcome = await (exporter as StreamingResenhaReportExporter)
            .exportGenerated(writer, sharePositionOrigin: origin);
      } else {
        outcome = await exporter.export(
          await widget.buildJsonReport(),
          sharePositionOrigin: origin,
        );
      }
      if (!mounted || outcome == ResenhaReportExportOutcome.cancelled) return;
      _showMessage(
        outcome == ResenhaReportExportOutcome.saved
            ? 'Resenha report saved'
            : 'Resenha report shared',
      );
    });
  }

  Future<void> _runBusy(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && successMessage != null) _showMessage(successMessage);
    } catch (error) {
      if (mounted) _showMessage('Resenha diagnostics failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.state,
    required this.busy,
    required this.exporterLabel,
    required this.onCaptureChanged,
    required this.onCopy,
    required this.onExport,
    required this.onClear,
  });

  final ResenhaDiagnosticsUiState state;
  final bool busy;
  final String exporterLabel;
  final ValueChanged<bool> onCaptureChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onExport;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(color: theme.shell.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DIcon(
                    DIcons.circle,
                    size: 10,
                    color: state.enabled
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.enabled ? 'Recording On' : 'Recording Off',
                      key: const ValueKey('resenha-recording-state'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    key: const ValueKey('resenha-capture-switch'),
                    value: state.enabled,
                    onChanged: busy ? null : onCaptureChanged,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Deep capture stores identities, network and media '
                'negotiation, device details, and SDK logs. Secrets are '
                'redacted. Restarting the app turns recording off.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MetadataChip(
                    key: const ValueKey('resenha-retained-size'),
                    label: _formatBytes(state.retainedBytes),
                  ),
                  _MetadataChip(label: '${state.droppedRecords} dropped'),
                  if (state.truncated)
                    const _MetadataChip(
                      key: ValueKey('resenha-truncated-indicator'),
                      label: 'Truncated',
                      warning: true,
                    ),
                  if (state.startedAtUtc != null)
                    _MetadataChip(
                      label: 'Since ${diagnosticTimeText(state.startedAtUtc!)}',
                    ),
                  if (state.captureId != null)
                    _MetadataChip(
                      key: const ValueKey('resenha-capture-id'),
                      label: 'Capture ${state.captureId}',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('resenha-copy-report'),
                    onPressed: onCopy,
                    icon: const DIcon(DIcons.copy, size: 15),
                    label: const Text('Copy report'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('resenha-export-report'),
                    onPressed: onExport,
                    icon: const DIcon(DIcons.download, size: 15),
                    label: Text(exporterLabel),
                  ),
                  IconButton.outlined(
                    key: const ValueKey('resenha-clear-capture'),
                    tooltip: state.enabled
                        ? 'Turn recording off before clearing'
                        : 'Clear capture',
                    onPressed: onClear,
                    icon: const DIcon(DIcons.trashCan, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({super.key, required this.label, this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: warning ? colors.onErrorContainer : colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CaptureEvent {
  _CaptureEvent(this.json, {required this.id})
    : timestampUtc = _eventTimestamp(json),
      name = _eventName(json),
      component = _eventComponent(json),
      severity = _eventSeverity(json),
      message = _eventMessage(json);

  final Map<String, Object?> json;
  final String id;
  final DateTime timestampUtc;
  final String name;
  final String component;
  final DiagnosticSeverity severity;
  final String? message;
  String? _searchText;

  bool matches(String query, {ValueChanged<String>? onSearchTextBuilt}) {
    if (query.isEmpty) return true;
    var searchText = _searchText;
    if (searchText == null) {
      searchText = jsonEncode(json).toLowerCase();
      _searchText = searchText;
      onSearchTextBuilt?.call(id);
    }
    return searchText.contains(query);
  }
}

class _CaptureEventRow extends StatelessWidget {
  const _CaptureEventRow({super.key, required this.event, required this.onTap});

  final _CaptureEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityColor = event.severity == DiagnosticSeverity.error
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
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
              width: 42,
              child: Text(
                event.severity.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: severityColor,
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
                    event.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      diagnosticTimeText(event.timestampUtc),
                      event.component,
                      event.message,
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const DIcon(DIcons.chevronRight, size: 12),
          ],
        ),
      ),
    );
  }
}

class _CaptureEventDetail extends StatelessWidget {
  const _CaptureEventDetail({
    required this.event,
    required this.onBack,
    required this.onCopy,
  });

  final _CaptureEvent event;
  final VoidCallback onBack;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: ValueKey('resenha-diagnostic-detail-${event.id}'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('resenha-diagnostics-detail-back'),
              tooltip: 'Back to capture',
              onPressed: onBack,
              icon: const DIcon(DIcons.arrowLeft, size: 18),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${sentenceCase(event.severity.name)} · ${event.component}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('resenha-copy-event'),
              onPressed: onCopy,
              icon: const DIcon(DIcons.copy, size: 15),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in event.json.entries)
          if (entry.value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sentenceCase(splitIdentifier(entry.key)),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    diagnosticValueText(entry.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: entry.value is Map || entry.value is Iterable
                          ? 'monospace'
                          : null,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _CaptureEmptyState extends StatelessWidget {
  const _CaptureEmptyState({required this.hasEvents, required this.recording});

  final bool hasEvents;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = hasEvents
        ? 'No matching capture events'
        : recording
        ? 'Waiting for Resenha activity'
        : 'No deep-capture records';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(
              hasEvents ? DIcons.filter : DIcons.microphoneLines,
              size: 30,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              hasEvents
                  ? 'Change the search to see more.'
                  : recording
                  ? 'Call and signaling events will appear here.'
                  : 'Turn recording on before reproducing the call problem.',
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

String _eventId(Map<String, Object?> json) {
  final value =
      json['id'] ??
      json['recordId'] ??
      json['sequence'] ??
      json['timestampUtc'];
  return '$value';
}

DateTime _eventTimestamp(Map<String, Object?> json) {
  final value = json['timestampUtc'] ?? json['timestamp'];
  return value is String
      ? DateTime.tryParse(value)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.fromMillisecondsSinceEpoch(0);
}

String _eventName(Map<String, Object?> json) =>
    '${json['event'] ?? json['name'] ?? json['kind'] ?? 'capture event'}';

String _eventComponent(Map<String, Object?> json) =>
    '${json['component'] ?? json['source'] ?? 'resenha'}';

String? _eventMessage(Map<String, Object?> json) {
  final value = json['message'];
  return value == null ? null : '$value';
}

DiagnosticSeverity _eventSeverity(Map<String, Object?> json) {
  final value = json['severity'];
  for (final severity in DiagnosticSeverity.values) {
    if (severity.name == value) return severity;
  }
  return DiagnosticSeverity.debug;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
