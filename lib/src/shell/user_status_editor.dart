import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../foundation/clock_time.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark_reminder.dart';
import '../models/user_status.dart';
import '../plugin_api/emoji_usage.dart';
import 'emoji_picker.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';

Future<void> showUserStatusEditor(
  BuildContext context, {
  required String siteUrl,
}) {
  final controller = ShellScope.read(context);
  final instance = controller.instanceFor(siteUrl);
  final user = instance?.user;
  if (instance == null || user == null || !instance.config.userStatusEnabled) {
    return Future.value();
  }
  final lease = controller.lifecycle.capture(siteUrl);
  // The menu that opens this dialog can close immediately afterward.
  final navigatorContext = Navigator.of(context, rootNavigator: true).context;
  bool ownsAccount() =>
      navigatorContext.mounted &&
      !controller.accountSessionDisposed &&
      lease.isCurrent &&
      identical(ShellScope.maybeRead(navigatorContext), controller);
  final initialStatus = controller.userStatuses.statusFor(
    siteUrl,
    user.id,
    user.status,
  );
  final initialPauseNotifications = controller.doNotDisturb
      .stateFor(siteUrl)
      .isActiveAt(DateTime.now());
  return showDialog<void>(
    context: context,
    builder: (context) => _UserStatusDialog(
      siteUrl: siteUrl,
      controller: controller,
      ownsAccount: ownsAccount,
      initialStatus: initialStatus,
      initialPauseNotifications: initialPauseNotifications,
    ),
  );
}

enum _StatusExpiry { never, oneHour, twoHours, tomorrow, custom }

class _UserStatusDialog extends StatefulWidget {
  const _UserStatusDialog({
    required this.siteUrl,
    required this.controller,
    required this.ownsAccount,
    required this.initialStatus,
    required this.initialPauseNotifications,
  });

  final String siteUrl;
  final ShellController controller;
  final bool Function() ownsAccount;
  final UserStatus? initialStatus;
  final bool initialPauseNotifications;

  @override
  State<_UserStatusDialog> createState() => _UserStatusDialogState();
}

class _UserStatusDialogState extends State<_UserStatusDialog> {
  late final TextEditingController _description;
  late String _emoji;
  late _StatusExpiry _expiry;
  DateTime? _customEndsAt;
  late bool _pauseNotifications;
  bool _busy = false;
  bool _picking = false;
  String? _error;

  bool get _isCurrent =>
      mounted &&
      widget.ownsAccount() &&
      ModalRoute.of(context)?.isActive == true;

  bool get _canAct =>
      _isCurrent &&
      ModalRoute.of(context)?.isCurrent == true &&
      !_busy &&
      !_picking;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStatus;
    _description = TextEditingController(text: initial?.description ?? '');
    _emoji = initial?.emoji ?? 'speech_balloon';
    _pauseNotifications = widget.initialPauseNotifications;
    _customEndsAt = initial?.endsAt;
    _expiry = _customEndsAt == null
        ? _StatusExpiry.never
        : _StatusExpiry.custom;
  }

  /// Expiry shortcuts and the custom wall time are the account's, as on the
  /// web's status modal, with the device zone only as the fallback.
  tz.Location get _readerLocation {
    final environment = TimezoneEnvironment.instance;
    return environment.location(
      environment.readerTimezone(
        widget.controller.currentUserFor(widget.siteUrl)?.timezone,
      ),
    )!;
  }

  Future<void> _pickEmoji() async {
    if (!_canAct) return;
    _picking = true;
    final shell = widget.controller;
    try {
      final picked = await showEmojiPicker(
        context: context,
        siteUrl: widget.siteUrl,
        pickerContext: CoreEmojiUsageContexts.userStatus,
        store: shell.emojiPickerStore,
        loadCatalog: ({bool refresh = false}) async {
          if (!_isCurrent) return null;
          final catalog = await shell.ensureEmojiCatalog(widget.siteUrl);
          return _isCurrent ? catalog : null;
        },
        loadSearchAliases: ({bool refresh = false}) async {
          if (!_isCurrent) return null;
          final aliases = await shell.ensureEmojiSearchAliases(widget.siteUrl);
          return _isCurrent ? aliases : null;
        },
        anchorContext: context,
      );
      if (_isCurrent && picked != null) setState(() => _emoji = picked);
    } finally {
      if (_isCurrent) _picking = false;
    }
  }

  Future<void> _chooseExpiry(_StatusExpiry value) async {
    if (!_canAct) return;
    if (value != _StatusExpiry.custom) {
      setState(() {
        _expiry = value;
        _customEndsAt = null;
      });
      return;
    }

    _picking = true;
    try {
      final location = _readerLocation;
      final now = DateTime.now();
      final wallNow = tz.TZDateTime.from(now, location);
      final wallInitial = tz.TZDateTime.from(
        _customEndsAt?.isAfter(now) == true
            ? _customEndsAt!
            : now.add(const Duration(days: 1)),
        location,
      );
      // Picker dates represent account-local calendar days, not instants.
      final firstDate = DateTime(wallNow.year, wallNow.month, wallNow.day);
      final lastDate = DateTime(wallNow.year + 5);
      final initialDate = DateTime(
        wallInitial.year,
        wallInitial.month,
        wallInitial.day,
      );
      final date = await showDatePicker(
        context: context,
        initialDate: initialDate.isAfter(lastDate) ? lastDate : initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        currentDate: firstDate,
      );
      if (date == null || !mounted || !_isCurrent) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: wallInitial.hour,
          minute: wallInitial.minute,
        ),
      );
      if (time == null || !_isCurrent) return;
      final endsAt = BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: date,
        hour: time.hour,
        minute: time.minute,
      );
      if (endsAt == null) {
        setState(
          () => _error =
              'That local time does not exist because of daylight saving time.',
        );
        return;
      }
      if (!endsAt.isAfter(DateTime.now())) {
        setState(() => _error = 'Choose a time in the future.');
        return;
      }
      setState(() {
        _expiry = value;
        _customEndsAt = endsAt;
        _error = null;
      });
    } finally {
      if (_isCurrent) _picking = false;
    }
  }

  DateTime? _endsAt() {
    final now = DateTime.now();
    return switch (_expiry) {
      _StatusExpiry.never => null,
      _StatusExpiry.oneHour => now.add(const Duration(hours: 1)),
      _StatusExpiry.twoHours => now.add(const Duration(hours: 2)),
      _StatusExpiry.tomorrow => BookmarkReminderCalculator.tomorrow(
        now: now,
        location: _readerLocation,
      ),
      _StatusExpiry.custom => _customEndsAt,
    };
  }

  Future<void> _save() async {
    if (!_canAct) return;
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Enter a status description.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.setUserStatus(
      widget.siteUrl,
      description: description,
      emoji: _emoji,
      endsAt: _endsAt(),
      pauseNotifications: _pauseNotifications,
    );
    if (!mounted || !_isCurrent) return;
    if (error == null) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _clear() async {
    if (!_canAct) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.clearUserStatus(widget.siteUrl);
    if (!mounted || !_isCurrent) return;
    if (error == null) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _description.text.trim();
    final preview = description.isEmpty ? null : description;
    final customEndsAt = _expiry == _StatusExpiry.custom ? _customEndsAt : null;
    final until = customEndsAt == null
        ? null
        : tz.TZDateTime.from(customEndsAt, _readerLocation);
    return AlertDialog(
      title: const Text('Set custom status'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DButton.iconOnly(
                    onPressed: _busy ? null : _pickEmoji,
                    variant: DButtonVariant.outline,
                    tooltip: 'Choose status emoji',
                    icon: SiteEmojiImage(
                      siteUrl: widget.siteUrl,
                      name: _emoji,
                      size: 24,
                      alt: 'Status emoji',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      style: Theme.of(context).textTheme.bodyMedium,
                      controller: _description,
                      autofocus: true,
                      enabled: !_busy,
                      maxLength: 100,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'What’s your status?',
                        hintText: 'What are you up to?',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_canAct) setState(() => _error = null);
                      },
                      onSubmitted: (_) {
                        if (!_busy) unawaited(_save());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DSelect<_StatusExpiry>.controlled(
                isExpanded: true,
                label: const Text('Clear after'),
                value: _expiry,
                entries: const [
                  DSelectOption(
                    value: _StatusExpiry.never,
                    label: 'Never',
                    child: Text('Never'),
                  ),
                  DSelectOption(
                    value: _StatusExpiry.oneHour,
                    label: '1 hour',
                    child: Text('1 hour'),
                  ),
                  DSelectOption(
                    value: _StatusExpiry.twoHours,
                    label: '2 hours',
                    child: Text('2 hours'),
                  ),
                  DSelectOption(
                    value: _StatusExpiry.tomorrow,
                    label: 'Tomorrow',
                    child: Text('Tomorrow'),
                  ),
                  DSelectOption(
                    value: _StatusExpiry.custom,
                    label: 'Custom date and time',
                    child: Text('Custom date and time'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) unawaited(_chooseExpiry(value));
                      },
                initialValue: _expiry,
                enabled: !_busy,
              ),
              if (until != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Until ${MaterialLocalizations.of(context).formatMediumDate(until)} '
                  '${clockTimeLabel(context, until)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              DCheckbox(
                value: _pauseNotifications,
                onChanged: _busy
                    ? null
                    : (value) {
                        if (!_canAct) return;
                        setState(() {
                          _pauseNotifications = value ?? false;
                          _error = null;
                        });
                      },
                contentPadding: EdgeInsets.zero,

                title: const DLabel(child: Text('Pause notifications')),
              ),
              if (preview != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Preview: '),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: SiteEmojiImage(
                              siteUrl: widget.siteUrl,
                              name: _emoji,
                              size: 17,
                              alt: preview,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 10),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initialStatus != null)
          DButton(
            label: const Text('Clear status'),
            onPressed: _busy ? null : _clear,
          ),
        DButton(
          label: const Text('Cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        DButton(
          label: const Text('Save'),
          onPressed: _save,
          variant: DButtonVariant.primary,
          loading: _busy,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }
}
