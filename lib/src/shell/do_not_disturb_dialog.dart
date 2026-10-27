import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/do_not_disturb.dart';
import '../theme/d_icons.dart';
import 'notification_schedule_sheet.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

Future<void> showDoNotDisturbDialog(
  BuildContext context, {
  required String siteUrl,
  ShellController? controller,
}) async {
  final shell = controller ?? ShellScope.read(context);
  final instance = shell.instanceFor(siteUrl);
  if (instance?.user == null) return;
  final lease = shell.lifecycle.capture(siteUrl);
  final navigatorContext = Navigator.of(context, rootNavigator: true).context;
  final scope = ShellScope.maybeRead(navigatorContext);
  bool ownsAccount() =>
      navigatorContext.mounted &&
      !shell.accountSessionDisposed &&
      lease.isCurrent &&
      identical(ShellScope.maybeRead(navigatorContext), scope);
  await showDDialog<void>(
    context: context,
    useRootNavigator: true,
    modal: false,
    dismissOnBarrier: false,
    dismissOnEscape: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    presentationBuilder: (_, presentation) => presentation.content,
    builder: (context, dialog) => _PauseNotificationsMenu(
      siteUrl: siteUrl,
      controller: shell,
      ownsAccount: ownsAccount,
      onClose: dialog.close,
    ),
  );
}

class _PauseNotificationsMenu extends StatefulWidget {
  const _PauseNotificationsMenu({
    required this.siteUrl,
    required this.controller,
    required this.ownsAccount,
    required this.onClose,
  });
  final String siteUrl;
  final ShellController controller;
  final bool Function() ownsAccount;
  final VoidCallback onClose;
  @override
  State<_PauseNotificationsMenu> createState() =>
      _PauseNotificationsMenuState();
}

class _PauseNotificationsMenuState extends State<_PauseNotificationsMenu> {
  final _menu = DDropdownMenuController();
  DoNotDisturbOption? _saving;
  bool _openingSchedule = false;
  bool _open = true;
  String? _error;
  bool get _canAct =>
      mounted &&
      widget.ownsAccount() &&
      _open &&
      _saving == null &&
      !_openingSchedule;
  @override
  void initState() {
    super.initState();
    final instance = widget.controller.instanceFor(widget.siteUrl);
    if (instance != null) {
      unawaited(widget.controller.preferences.load(instance));
    }
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  Future<void> _save(DoNotDisturbOption option) async {
    if (!_canAct) return;
    setState(() {
      _saving = option;
      _error = null;
    });
    final error = await widget.controller.doNotDisturb.pause(
      widget.siteUrl,
      option.duration,
    );
    if (!mounted || !widget.ownsAccount() || !_open) return;
    if (error == null) {
      _menu.close();
    } else {
      setState(() {
        _saving = null;
        _error = error;
      });
    }
  }

  Future<void> _openSchedule(BuildContext context) async {
    if (!_canAct) return;
    _openingSchedule = true;
    try {
      await showNotificationScheduleSheet(
        context: context,
        siteUrl: widget.siteUrl,
        controller: widget.controller,
        ownsAccount: widget.ownsAccount,
      );
    } finally {
      if (mounted) {
        setState(() => _openingSchedule = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.ownsAccount() && !_menu.isOpen) _menu.open();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          left: size.width / 2,
          top: size.height / 3,
          child: DDropdownMenu(
            controller: _menu,
            defaultOpen: true,
            sheetOnMobile: true,
            mobileSheetVariant: DSheetVariant.adaptiveMenu,
            onOpenChange: (open, _) => _open = open,
            onOpenChangeComplete: (open) {
              if (!open && !_openingSchedule) widget.onClose();
            },
            content: DDropdownMenuContent(
              width: 360,
              align: DPopoverAlign.center,
              semanticLabel: context.l10n.pauseNotifications,
              children: [
                DDropdownMenuLabel(
                  child: Text(context.l10n.pauseNotifications),
                ),
                for (final option in DoNotDisturbOption.values)
                  DDropdownMenuItem(
                    key: ValueKey('do-not-disturb-${option.name}'),
                    closeOnSelect: false,
                    onPressed: _saving == null && !_openingSchedule
                        ? () => unawaited(_save(option))
                        : null,
                    trailing: _saving == option
                        ? const DSpinner(size: 14)
                        : null,
                    child: Text(option.label),
                  ),
                if (_error case final error?) DFieldError(errors: [error]),
                const DDropdownMenuSeparator(),
                Builder(
                  builder: (context) => ListenableBuilder(
                    listenable: widget.controller.preferences,
                    builder: (context, _) {
                      final schedule = widget.controller.preferences
                          .stateFor(widget.siteUrl)
                          ?.confirmed
                          ?.notificationSchedule;
                      return DDropdownMenuItem(
                        key: const ValueKey('notification-schedule-open'),
                        closeOnSelect: false,
                        onPressed: _saving == null && !_openingSchedule
                            ? () => unawaited(_openSchedule(context))
                            : null,
                        trailing: const DIcon(DIcons.chevronRight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.notificationSchedule),
                            DText(
                              notificationScheduleSummary(context, schedule),
                              variant: DTextVariant.muted,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                DDropdownMenuItem(
                  onPressed: _saving == null ? () => _menu.close() : null,
                  child: Text(context.l10n.cancel),
                ),
              ],
            ),
            child: const DPopoverAnchor(child: SizedBox.square(dimension: 1)),
          ),
        ),
      ],
    );
  }
}
