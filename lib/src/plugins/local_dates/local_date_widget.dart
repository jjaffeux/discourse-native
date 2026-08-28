import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/plugin_scope.dart';
import '../../shell/anchored_layout.dart';
import '../../shell/platform.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'local_date.dart';
import 'local_date_environment.dart';
import 'local_dates_services.dart';
import 'local_dates_settings.dart';

Widget? localDateWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'span' ||
      !element.classes.contains('discourse-local-date')) {
    return null;
  }
  final spec = LocalDateSpec.fromDataAttributes(
    element.attributes.map((key, value) => MapEntry(key.toString(), value)),
    fallbackText: element.text,
  );
  LocalDateSpec? from;
  LocalDateSpec? to;
  if (spec.range == 'to') {
    final previous = element.previousElementSibling;
    if (previous != null &&
        previous.classes.contains('discourse-local-date') &&
        previous.attributes['data-range'] == 'from') {
      from = LocalDateSpec.fromDataAttributes(
        previous.attributes.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        fallbackText: previous.text,
      );
    }
  } else if (spec.range == 'from') {
    final next = element.nextElementSibling;
    if (next != null &&
        next.classes.contains('discourse-local-date') &&
        next.attributes['data-range'] == 'to') {
      to = LocalDateSpec.fromDataAttributes(
        next.attributes.map((key, value) => MapEntry(key.toString(), value)),
        fallbackText: next.text,
      );
    }
  }
  return InlineCustomWidget(
    child: LocalDateInline(spec: spec, siteUrl: siteUrl, from: from, to: to),
  );
}

/// Native inline treatment for server-cooked local dates. It deliberately has
/// no [Post] dependency, so chat, quotes and oneboxes use the same code path.
class LocalDateInline extends StatefulWidget {
  const LocalDateInline({
    super.key,
    required this.spec,
    this.siteUrl,
    this.from,
    this.to,
    this.formatter = const LocalDateFormatter(),
    this.now,
  });

  final LocalDateSpec spec;
  final String? siteUrl;
  final LocalDateSpec? from;
  final LocalDateSpec? to;
  final LocalDateFormatter formatter;
  final DateTime Function()? now;

  @override
  State<LocalDateInline> createState() => _LocalDateInlineState();
}

class _LocalDateInlineState extends State<LocalDateInline> {
  Timer? _timer;
  DateTime? _scheduledFor;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = PluginUiScope.maybe(context, localDatesUiService);
    final siteUrl = widget.siteUrl ?? service?.currentSiteUrl;
    final accountTimezone = siteUrl == null
        ? null
        : service?.accountTimezoneFor(siteUrl);
    final locale = Localizations.localeOf(context);
    return ListenableBuilder(
      listenable: LocalDateEnvironment.instance,
      builder: (context, _) {
        final now = _now;
        final resolved = widget.formatter.resolve(
          widget.spec,
          locale: locale,
          accountTimezone: accountTimezone,
          now: now,
          sameLocalDayAsFrom: _sameLocalDayAsFrom(locale, accountTimezone, now),
        );
        if (resolved == null) return Text(widget.spec.fallbackText);
        _scheduleRefresh(resolved, now);
        return _LocalDateButton(
          formatted: resolved.formatted,
          past: resolved.past,
          semanticLabel: _semanticLabel(
            resolved,
            locale,
            accountTimezone,
            siteUrl == null
                ? const []
                : service?.configFor(siteUrl).localDatesSettings.timezones ??
                      const [],
          ),
          onPressed: (anchor) => _showPreviews(
            context,
            anchor: anchor,
            siteUrl: siteUrl,
            accountTimezone: accountTimezone,
          ),
        );
      },
    );
  }

  bool _sameLocalDayAsFrom(
    Locale locale,
    String? accountTimezone,
    DateTime now,
  ) {
    final from = widget.from;
    if (from == null || !from.hasTime || !widget.spec.hasTime) return false;
    final start = widget.formatter.resolve(
      from,
      locale: locale,
      accountTimezone: accountTimezone,
      now: now,
    );
    final end = widget.formatter.resolve(
      widget.spec,
      locale: locale,
      accountTimezone: accountTimezone,
      now: now,
    );
    return start != null &&
        end != null &&
        start.displayed.year == end.displayed.year &&
        start.displayed.month == end.displayed.month &&
        start.displayed.day == end.displayed.day;
  }

  String _semanticLabel(
    LocalDateResolved resolved,
    Locale locale,
    String? accountTimezone,
    Iterable<String> defaults,
  ) => widget.formatter
      .previews(
        widget.spec,
        locale: locale,
        accountTimezone: accountTimezone,
        defaultTimezones: defaults,
        now: _now,
      )
      .map((preview) => '${preview.label}: ${preview.formatted}')
      .join(', ');

  void _scheduleRefresh(LocalDateResolved resolved, DateTime now) {
    final readerLocation = LocalDateEnvironment.instance.location(
      resolved.readerTimezone,
    )!;
    final readerNow = tz.TZDateTime.from(now, readerLocation);
    final DateTime next;
    if (widget.spec.countdown) {
      final second = DateTime.fromMillisecondsSinceEpoch(
        (now.millisecondsSinceEpoch ~/ 1000 + 1) * 1000,
      );
      next = resolved.source.isBefore(second) ? resolved.source : second;
    } else if (widget.spec.recurring != null) {
      next = now.add(const Duration(minutes: 1));
    } else {
      next = tz.TZDateTime(
        readerLocation,
        readerNow.year,
        readerNow.month,
        readerNow.day + 1,
      );
    }
    if (_scheduledFor == next && _timer?.isActive == true) return;
    _timer?.cancel();
    _scheduledFor = next;
    final delay = next.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      _scheduledFor = null;
      setState(() {});
    });
  }

  Future<void> _showPreviews(
    BuildContext context, {
    required Rect anchor,
    required String? siteUrl,
    required String? accountTimezone,
  }) async {
    final locale = Localizations.localeOf(context);
    final service = PluginUiScope.maybe(context, localDatesUiService);
    final defaultTimezones = siteUrl == null
        ? const <String>[]
        : service?.configFor(siteUrl).localDatesSettings.timezones ??
              const <String>[];
    final previews = widget.formatter.previews(
      widget.spec,
      locale: locale,
      accountTimezone: accountTimezone,
      defaultTimezones: defaultTimezones,
      now: _now,
    );
    if (previews.isEmpty) return;
    Widget body(BuildContext context) => _LocalDatePreviewBody(
      previews: previews,
      rangeEnd: widget.to,
      formatter: widget.formatter,
      locale: locale,
      accountTimezone: accountTimezone,
      now: _now,
    );
    if (context.isTouch) {
      await showShellSheet<void>(
        context: context,
        title: 'Date and time',
        builder: body,
      );
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss date and time',
      barrierColor: Colors.transparent,
      pageBuilder: (context, _, _) => CustomSingleChildLayout(
        delegate: AnchoredLayout(anchor: anchor, maxWidth: 420),
        child: Material(
          elevation: 8,
          color: Theme.of(context).shell.floating,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: body(context),
          ),
        ),
      ),
    );
  }
}

class _LocalDateButton extends StatelessWidget {
  const _LocalDateButton({
    required this.formatted,
    required this.past,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String formatted;
  final bool past;
  final String semanticLabel;
  final ValueChanged<Rect> onPressed;

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final color = past
        ? inherited.color?.withValues(alpha: 0.62)
        : theme.colorScheme.primary;
    final label = semanticLabel.isEmpty ? formatted : semanticLabel;

    void activate() {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      onPressed(origin & box.size);
    }

    // This widget participates in a cooked paragraph through a WidgetSpan.
    // Forcing a 44px box around it would expand the surrounding line, so it
    // uses WCAG's inline-target exception and makes the complete painted date
    // the hit target instead. InkWell still supplies keyboard focus, Enter and
    // Space activation, and a visible focus overlay.
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: activate,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: activate,
            borderRadius: BorderRadius.circular(2),
            focusColor: theme.colorScheme.primary.withValues(alpha: 0.16),
            child: Text.rich(
              TextSpan(
                style: inherited.copyWith(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dotted,
                  decorationColor: color,
                ),
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: DIcon(DIcons.globe, size: 15, color: color),
                  ),
                  TextSpan(text: ' $formatted'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalDatePreviewBody extends StatelessWidget {
  const _LocalDatePreviewBody({
    required this.previews,
    required this.rangeEnd,
    required this.formatter,
    required this.locale,
    required this.accountTimezone,
    required this.now,
  });

  final List<LocalDatePreview> previews;
  final LocalDateSpec? rangeEnd;
  final LocalDateFormatter formatter;
  final Locale locale;
  final String? accountTimezone;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < previews.length; index++) ...[
          if (index > 0) Divider(height: 17, color: theme.shell.divider),
          _PreviewRow(
            preview: previews[index],
            rangeEnd: rangeEnd,
            formatter: formatter,
            locale: locale,
            accountTimezone: accountTimezone,
            now: now,
          ),
        ],
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.preview,
    required this.rangeEnd,
    required this.formatter,
    required this.locale,
    required this.accountTimezone,
    required this.now,
  });

  final LocalDatePreview preview;
  final LocalDateSpec? rangeEnd;
  final LocalDateFormatter formatter;
  final Locale locale;
  final String? accountTimezone;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    String? end;
    final endSpec = rangeEnd;
    if (endSpec != null) {
      final resolved = formatter.resolve(
        LocalDateSpec(
          date: endSpec.date,
          fallbackText: endSpec.fallbackText,
          time: endSpec.time,
          timezone: endSpec.timezone,
          format: 'LLLL',
          displayedTimezone: preview.timezone,
        ),
        locale: locale,
        accountTimezone: accountTimezone,
        now: now,
      );
      end = resolved?.formatted;
    }
    final labels = [
      if (preview.current) 'Device',
      if (preview.source) 'Source',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (labels.isNotEmpty)
                Text(
                  labels.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            end == null ? preview.formatted : '${preview.formatted} → $end',
          ),
        ),
      ],
    );
  }
}
