import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../foundation/clock_time.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark_reminder.dart';
import '../models/user_card.dart';
import '../models/user_status.dart';
import '../plugin_api/composer_sheet_header.dart';
import '../plugin_api/emoji_usage.dart';
import '../theme/discourse_typography.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';
import 'user_card_header.dart';

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
  // The menu that opens this editor can close immediately afterward.
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
  return _showStatusForm<void>(
    context: context,
    title: appL10n.setCustomStatus,
    builder: (context) => _UserStatusEditor(
      siteUrl: siteUrl,
      controller: controller,
      ownsAccount: ownsAccount,
      identity: UserCard(
        username: user.username,
        id: user.id,
        name: user.name,
        avatarUrl: user.avatarUrl,
        isStaff: user.staff,
        isAdmin: user.admin,
      ),
      initialStatus: initialStatus,
      initialPauseNotifications: initialPauseNotifications,
    ),
  );
}

enum _StatusExpiry { never, oneHour, twoHours, tomorrow, custom }

class _UserStatusEditor extends StatefulWidget {
  const _UserStatusEditor({
    required this.siteUrl,
    required this.controller,
    required this.ownsAccount,
    required this.initialStatus,
    required this.identity,
    required this.initialPauseNotifications,
  });

  final String siteUrl;
  final ShellController controller;
  final bool Function() ownsAccount;
  final UserStatus? initialStatus;
  final UserCard identity;
  final bool initialPauseNotifications;

  @override
  State<_UserStatusEditor> createState() => _UserStatusEditorState();
}

class _UserStatusEditorState extends State<_UserStatusEditor> {
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
    unawaited(
      widget.controller.loadUserCard(
        widget.identity.username,
        siteUrl: widget.siteUrl,
      ),
    );
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
      final selection =
          await _showStatusForm<({DCalendarDate date, DTimeValue time})>(
            context: context,
            title: appL10n.customDateAndTime,
            builder: (context) => _StatusExpiryPicker(
              initialDate: DCalendarDate.fromDateTime(
                initialDate.isAfter(lastDate) ? lastDate : initialDate,
              ),
              firstDate: DCalendarDate.fromDateTime(firstDate),
              lastDate: DCalendarDate.fromDateTime(lastDate),
              initialTime: DTimeValue(
                hour: wallInitial.hour,
                minute: wallInitial.minute,
              ),
            ),
          );
      if (selection == null || !_isCurrent) return;
      final endsAt = BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: selection.date.dateTimeUtc,
        hour: selection.time.hour,
        minute: selection.time.minute,
      );
      if (endsAt == null) {
        setState(
          () => _error =
              appL10n.thatLocalTimeDoesNotExistBecauseOfDaylightSavingTime,
        );
        return;
      }
      if (!endsAt.isAfter(DateTime.now())) {
        setState(() => _error = appL10n.chooseATimeInTheFuture);
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
      setState(() => _error = appL10n.enterAStatusDescription);
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
    final customEndsAt = _expiry == _StatusExpiry.custom ? _customEndsAt : null;
    final until = customEndsAt == null
        ? null
        : tz.TZDateTime.from(customEndsAt, _readerLocation);
    return _StatusFormLayout(
      key: const ValueKey('user-status-editor'),
      title: context.l10n.setCustomStatus,
      actions: [
        if (widget.initialStatus != null)
          DButton(
            label: Text(context.l10n.clearStatus),
            onPressed: _busy ? null : _clear,
            variant: DButtonVariant.destructive,
            expanded: context.isTouch,
          ),
        if (!context.isTouch)
          DButton(
            label: Text(context.l10n.cancel),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        DButton(
          label: Text(context.l10n.save),
          onPressed: _save,
          variant: DButtonVariant.primary,
          loading: _busy,
          expanded: context.isTouch,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: widget.controller.store.ref<UserCard>(
              widget.siteUrl,
              widget.identity.username.toLowerCase(),
            ),
            builder: (context, _) => DCard(
              key: const ValueKey('user-status-card-preview'),
              spacing: 0,
              child: UserCardHeader(
                card: widget.ownsAccount()
                    ? widget.controller.userCard(
                            widget.identity.username,
                            siteUrl: widget.siteUrl,
                          ) ??
                          widget.identity
                    : widget.identity,
                siteUrl: widget.siteUrl,
                statusContent: DBubble(
                  variant: DBubbleVariant.status,
                  maximumWidthFactor: 1,
                  children: [
                    DBubbleContent(
                      child: Row(
                        children: [
                          DButton.iconOnly(
                            onPressed: _busy ? null : _pickEmoji,
                            variant: DButtonVariant.inline,
                            density: DButtonDensity.inlineMetadata,
                            tooltip: context.l10n.chooseStatusEmoji,
                            icon: SiteEmojiImage(
                              siteUrl: widget.siteUrl,
                              name: _emoji,
                              size: 15,
                              alt: '',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: DInput(
                              controller: _description,
                              borderless: true,
                              style: const TextStyle(
                                fontSize: DiscourseTypography.preview,
                                height: 1.3,
                              ),
                              autofocus: !context.isTouch,
                              enabled: !_busy,
                              maxLength: 100,
                              textInputAction: TextInputAction.done,
                              semanticLabel: context.l10n.whatSYourStatus,
                              hintText: context.l10n.whatAreYouUpTo,
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
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: DSpacing.lg),
          DSelect<_StatusExpiry>.controlled(
            isExpanded: true,
            label: Text(context.l10n.clearAfter),
            value: _expiry,
            entries: [
              DSelectOption(
                value: _StatusExpiry.never,
                label: context.l10n.never,
                child: Text(context.l10n.never),
              ),
              DSelectOption(
                value: _StatusExpiry.oneHour,
                label: context.l10n.message1Hour,
                child: Text(context.l10n.message1Hour),
              ),
              DSelectOption(
                value: _StatusExpiry.twoHours,
                label: context.l10n.message2Hours,
                child: Text(context.l10n.message2Hours),
              ),
              DSelectOption(
                value: _StatusExpiry.tomorrow,
                label: context.l10n.tomorrow,
                child: Text(context.l10n.tomorrow),
              ),
              DSelectOption(
                value: _StatusExpiry.custom,
                label: context.l10n.customDateAndTime,
                child: Text(context.l10n.customDateAndTime),
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
              context.l10n.until(
                (MaterialLocalizations.of(
                  context,
                ).formatMediumDate(until)).toString(),
                (clockTimeLabel(context, until)).toString(),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: DSpacing.lg),
          DSwitchTile(
            value: _pauseNotifications,
            onChanged: _busy
                ? null
                : (value) {
                    if (!_canAct) return;
                    setState(() {
                      _pauseNotifications = value;
                      _error = null;
                    });
                  },
            contentPadding: EdgeInsets.zero,
            title: DLabel(child: Text(context.l10n.pauseNotifications)),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 10),
            DFieldError(child: Text(error)),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }
}

Future<T?> _showStatusForm<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  if (context.isTouch) {
    return showDSheet<T>(
      context: context,
      useRootNavigator: true,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: title,
        showCloseButton: false,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [Expanded(child: builder(context))],
      ),
    );
  }
  return showDDialog<T>(
    context: context,
    useRootNavigator: true,
    builder: (context, dialog) => builder(context),
  );
}

/// The status forms share the poll/date sheet's fixed header and action bar.
class _StatusFormLayout extends StatelessWidget {
  const _StatusFormLayout({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ComposerSheetHeader(title: title),
          Expanded(
            child: DSheetBody(
              padding: const EdgeInsets.fromLTRB(
                DSpacing.lg,
                0,
                DSpacing.lg,
                DSpacing.lg,
              ),
              child: child,
            ),
          ),
          const DSeparator(),
          DSheetFooter(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (MediaQuery.textScalerOf(context).scale(14) > 21) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: DSpacing.controlGap,
                      children: actions,
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: DSpacing.controlGap),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      );
    }
    return DDialogContent(
      maxWidth: 480,
      semanticLabel: title,
      children: [
        DDialogHeader(children: [DDialogTitle(child: Text(title))]),
        DDialogScrollArea(child: child),
        DDialogFooter(children: actions),
      ],
    );
  }
}

class _StatusExpiryPicker extends StatefulWidget {
  const _StatusExpiryPicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.initialTime,
  });

  final DCalendarDate initialDate;
  final DCalendarDate firstDate;
  final DCalendarDate lastDate;
  final DTimeValue initialTime;

  @override
  State<_StatusExpiryPicker> createState() => _StatusExpiryPickerState();
}

class _StatusExpiryPickerState extends State<_StatusExpiryPicker> {
  late DCalendarDate? _date = widget.initialDate;
  late DTimeValue? _time = widget.initialTime;
  bool _validTime = true;

  @override
  Widget build(BuildContext context) => _StatusFormLayout(
    title: context.l10n.customDateAndTime,
    actions: [
      if (!context.isTouch)
        DButton(
          label: Text(context.l10n.cancel),
          variant: DButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      DButton(
        label: Text(context.l10n.apply),
        variant: DButtonVariant.primary,
        expanded: context.isTouch,
        onPressed: _date == null || _time == null || !_validTime
            ? null
            : () => Navigator.of(context).pop((date: _date!, time: _time!)),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DCalendar(
          responsiveCellSize: context.isTouch
              ? (width) => (width - 16) / 7
              : null,
          selection: DCalendarSingleSelection(_date),
          initialDisplayedMonth: widget.initialDate,
          startMonth: widget.firstDate,
          endMonth: widget.lastDate,
          today: widget.firstDate,
          disabled: (date) =>
              date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate),
          onSelectionChanged: (selection, _) => setState(
            () => _date = (selection as DCalendarSingleSelection).date,
          ),
        ),
        const SizedBox(height: DSpacing.lg),
        DTimeInput(
          initialValue: widget.initialTime,
          includeSeconds: false,
          mobilePicker: true,
          label: context.l10n.time,
          onChanged: (time) => setState(() => _time = time),
          onValidityChanged: (valid) => setState(() => _validTime = valid),
        ),
      ],
    ),
  );
}
