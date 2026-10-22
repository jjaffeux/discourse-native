import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'event_calendar.dart';
import 'event_calendar_data.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_directory_session.dart';
import 'event_navigation.dart';

export 'event_directory_session.dart' show eventDirectoryOccurrences;

class EventDirectory extends StatelessWidget {
  const EventDirectory({
    super.key,
    required this.site,
    required this.mine,
    required this.controller,
    required this.navigation,
    this.page,
  });
  final String site;
  final bool mine;
  final EventController controller;
  final EventNavigation navigation;
  final EventCalendarPage? page;
  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    child: _EventDirectoryBody(
      site: site,
      mine: mine,
      controller: controller,
      navigation: navigation,
      page: page,
      // The mockup follows the shell width (53 + 240 + 420), so a narrow
      // desktop pane still starts in Month. Picking a view pins that choice.
      compact: MediaQuery.sizeOf(context).width < 713,
    ),
  );
}

class _EventDirectoryBody extends StatefulWidget {
  const _EventDirectoryBody({
    required this.site,
    required this.mine,
    required this.controller,
    required this.navigation,
    required this.page,
    required this.compact,
  });

  final String site;
  final bool mine;
  final EventController controller;
  final EventNavigation navigation;
  final EventCalendarPage? page;
  final bool compact;

  @override
  State<_EventDirectoryBody> createState() => _EventDirectoryState();
}

class _EventDirectoryState extends State<_EventDirectoryBody> {
  List<EventCalendarEntry> _events = const [];
  late EventCalendarPage _page;
  late EventDirectorySession _session;
  bool _viewSelected = false;
  tz.Location get _location => _session.location;
  int get _firstDay => _session.firstDay;
  EventSettings get _settings => _session.settings;

  void _createSession() {
    _session = EventDirectorySession(
      controller: widget.controller,
      site: widget.site,
      mine: widget.mine,
      page: _page,
    )..addListener(_changed);
    _projectEvents();
  }

  @override
  void initState() {
    super.initState();
    _viewSelected = widget.page != null;
    _page = widget.page?.directoryPage ?? _defaultPage();
    _createSession();
  }

  EventCalendarPage _defaultPage() {
    final controller = widget.controller;
    final timezone = controller.zones.readerTimezone(
      controller.accountTimezone(widget.site),
    );
    final today = tz.TZDateTime.from(
      controller.api.clock(),
      controller.zones.location(timezone)!,
    );
    final view = widget.compact
        ? EventCalendarView.schedule
        : EventCalendarView.month;
    return EventCalendarPage(
      view,
      DateTime.utc(today.year, today.month, today.day),
    );
  }

  void _changed() => setState(_projectEvents);

  @override
  void didUpdateWidget(_EventDirectoryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.site != widget.site ||
        oldWidget.mine != widget.mine) {
      _session.dispose();
      if (oldWidget.site != widget.site) _viewSelected = widget.page != null;
      _page =
          widget.page?.directoryPage ??
          (oldWidget.site != widget.site ? _defaultPage() : _page);
      _createSession();
    } else {
      if (widget.page != null && widget.page != oldWidget.page) {
        final incoming = widget.page!.directoryPage;
        if (incoming != _page) _viewSelected = true;
        _page = incoming;
      } else if (!_viewSelected && oldWidget.compact != widget.compact) {
        _page = EventCalendarPage(_defaultPage().view, _page.date);
      }
      _session.show(_page);
    }
  }

  void _projectEvents() {
    final controller = widget.controller;
    _events = [
      for (final event in _session.occurrences)
        ?EventCalendarEntry.decode(
          event,
          zones: controller.zones,
          timezone: _session.timezone,
          settings: _settings,
          categoryName: switch (eventInt(event.fields['category_id'])) {
            final id? =>
              controller.siteState.categoryFor?.call(widget.site, id)?.name,
            _ => null,
          },
          categoryColor: switch (eventInt(event.fields['category_id'])) {
            final id? => switch (controller.siteState.categoryFor?.call(
              widget.site,
              id,
            )) {
              final category? => Color(category.colorValue),
              _ => null,
            },
            _ => null,
          },
        ),
    ];
  }

  void _navigate(EventCalendarPage page) {
    if (page == _page) return;
    setState(() {
      _viewSelected = _viewSelected || page.view != _page.view;
      _page = page;
    });
    _session.show(page);
    widget.navigation.rememberDirectory(mine: widget.mine, page: page);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventCalendar(
    page: _page,
    events: _events,
    loading: _session.loading,
    location: _location,
    firstDay: _firstDay,
    display: _settings.calendarDisplay,
    clock: widget.controller.api.clock,
    mine: widget.mine,
    onMineChanged:
        widget.controller.accounts.isConnected(widget.site) || widget.mine
        ? (mine) => widget.navigation.openDirectory(
            mine: mine,
            page: _page,
            replace: true,
          )
        : null,
    onViewSelected: () => _viewSelected = true,
    onPageChanged: _navigate,
    onOpen: (entry) => widget.navigation.openEvent(widget.site, entry.event),
    status: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_session.failed)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.unableToLoadEventsTryRefreshingTheCalendar,
                    ),
                  ),
                  DButton(
                    variant: DButtonVariant.outline,
                    onPressed: _session.refresh,
                    label: Text(context.l10n.retry),
                  ),
                ],
              ),
            ),
          ),
        if (!_session.loading && !_session.failed && _events.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              context.l10n.noEventsInThisPeriod,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
}
