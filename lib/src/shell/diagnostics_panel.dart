import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'diagnostics_text.dart';

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
  DiagnosticsPlugin? _selectedPlugin;

  @override
  void didUpdateWidget(DiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _search.text = widget.controller.panelState.query;
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
          if (_selectedPlugin == null &&
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
                    showingDetail: _selectedPlugin == null && selected != null,
                    showGeneralActions: _selectedPlugin == null,
                    onBack: () => widget.controller.selectEvent(null),
                    onToggleFrozen: () =>
                        widget.controller.setFrozen(!panelState.frozen),
                    onCopyReport: _copyReport,
                    onClear: _confirmClear,
                    onClose: widget.onClose,
                  ),
                  Divider(height: 1, color: theme.shell.divider),
                  if (widget.plugins.isNotEmpty) ...[
                    _DiagnosticsTabs(
                      plugins: widget.plugins,
                      selected: _selectedPlugin,
                      onChanged: (plugin) =>
                          setState(() => _selectedPlugin = plugin),
                    ),
                    Divider(height: 1, color: theme.shell.divider),
                  ],
                  Expanded(
                    child: _selectedPlugin != null
                        ? _selectedPlugin!.buildDiagnostics(
                            context,
                            widget.controller,
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
  const _DiagnosticsTabs({
    required this.plugins,
    required this.selected,
    required this.onChanged,
  });

  final List<DiagnosticsPlugin> plugins;
  final DiagnosticsPlugin? selected;
  final ValueChanged<DiagnosticsPlugin?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          key: const ValueKey('diagnostics-top-level-tabs'),
          segments: [
            const ButtonSegment(value: 0, label: Text('General')),
            for (var index = 0; index < plugins.length; index++)
              ButtonSegment(
                value: index + 1,
                label: Text(plugins[index].diagnosticsLabel),
              ),
          ],
          selected: {selected == null ? 0 : plugins.indexOf(selected!) + 1},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            final index = selection.first;
            onChanged(index == 0 ? null : plugins[index - 1]);
          },
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
      popUpAnimationStyle: discoursePopupMenuAnimationStyle(context),
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
