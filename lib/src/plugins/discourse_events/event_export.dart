import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'event_controller.dart';

export 'event_api.dart' show EmptyEventCalendarException;

/// One export's view and account lifetime, including native save continuations.
/// Cancelling retires continuations; it cannot dismiss an OS-owned share sheet.
final class EventExportOperation {
  EventExportOperation(this.controller, this.site)
    : _lease = controller.requests.capture(site),
      _accountRevision = controller.accountRevision(site);

  final EventController controller;
  final String site;
  final PluginSiteLease _lease;
  final int _accountRevision;
  bool _cancelled = false;

  bool get isCurrent =>
      !_cancelled &&
      _lease.isCurrent &&
      controller.isAccountCurrent(site, _accountRevision);

  void cancel() => _cancelled = true;
}

Future<String> eventCalendar(
  EventController controller,
  String site, {
  int? eventId,
  bool mine = false,
  bool Function()? isCurrent,
}) async {
  final operation = EventExportOperation(controller, site);
  bool current() => operation.isCurrent && (isCurrent?.call() ?? true);
  if (!current()) throw StateError('Export cancelled.');
  final username = mine
      ? controller.siteState.currentUserFor(site)?.username
      : null;
  if (mine && username == null) throw StateError('Connect your account first.');
  final credentials = await controller.requests.credentialsFor(site);
  if (!current()) throw StateError('Export cancelled.');
  try {
    final calendar = await credentials.run(
      () => controller.api.calendar(
        site,
        credentials,
        eventId: eventId,
        attendingUser: username,
      ),
    );
    if (!current()) throw StateError('Export cancelled.');
    return calendar;
  } catch (_) {
    if (!current()) throw StateError('Export cancelled.');
    rethrow;
  }
}
