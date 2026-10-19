import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

/// Native civil-date input. The bookmark owner resolves the chosen wall time.
class BookmarkReminderDatePicker extends StatefulWidget {
  const BookmarkReminderDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  @override
  State<BookmarkReminderDatePicker> createState() => _DateState();
}

class _DateState extends State<BookmarkReminderDatePicker> {
  late DCalendarDate? _date = DCalendarDate.fromDateTime(widget.initialDate);
  late final _text = TextEditingController();
  bool _valid = true;
  @override
  void initState() {
    super.initState();
    _text.addListener(_validate);
  }

  void _validate() {
    final date = const DIntlDateTextCodec().tryParse(
      _text.text,
      Localizations.localeOf(context),
    );
    final valid =
        date != null &&
        !date.isBefore(widget.firstDate) &&
        !date.isAfter(widget.lastDate);
    if (_valid != valid) setState(() => _valid = valid);
  }

  @override
  void dispose() {
    _text.removeListener(_validate);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DDatePickerInput(
        initialValue: _date,
        controller: _text,
        label: context.l10n.date,
        startMonth: DCalendarDate.fromDateTime(widget.firstDate),
        endMonth: DCalendarDate.fromDateTime(widget.lastDate),
        today: DCalendarDate.fromDateTime(widget.firstDate),
        disabled: (date) =>
            date.isBefore(DCalendarDate.fromDateTime(widget.firstDate)) ||
            date.isAfter(DCalendarDate.fromDateTime(widget.lastDate)),
        onChanged: (date) => setState(() => _date = date),
      ),
      const SizedBox(height: DSpacing.lg),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: DSpacing.controlGap,
        children: [
          DButton(
            variant: DButtonVariant.secondary,
            label: Text(context.l10n.cancel),
            onPressed: () => DDialogClose.close<void>(context),
          ),
          DButton(
            key: const ValueKey('bookmark-picker-apply'),
            label: Text(context.l10n.next),
            onPressed: !_valid || _date == null
                ? null
                : () => DDialogClose.close<DateTime>(
                    context,
                    DateTime(_date!.year, _date!.month, _date!.day),
                  ),
          ),
        ],
      ),
    ],
  );
}

class BookmarkReminderTimePicker extends StatefulWidget {
  const BookmarkReminderTimePicker({super.key, required this.initialTime});
  final TimeOfDay initialTime;
  @override
  State<BookmarkReminderTimePicker> createState() => _TimeState();
}

class _TimeState extends State<BookmarkReminderTimePicker> {
  late DTimeValue? _time = DTimeValue(
    hour: widget.initialTime.hour,
    minute: widget.initialTime.minute,
  );
  bool _valid = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DTimeInput(
        initialValue: _time,
        includeSeconds: false,
        mobilePicker: true,
        label: context.l10n.time,
        onChanged: (time) => setState(() => _time = time),
        onValidityChanged: (valid) => setState(() => _valid = valid),
      ),
      const SizedBox(height: DSpacing.lg),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: DSpacing.controlGap,
        children: [
          DButton(
            variant: DButtonVariant.secondary,
            label: Text(context.l10n.cancel),
            onPressed: () => DDialogClose.close<void>(context),
          ),
          DButton(
            key: const ValueKey('bookmark-picker-apply'),
            label: Text(context.l10n.apply),
            onPressed: !_valid || _time == null
                ? null
                : () => DDialogClose.close<TimeOfDay>(
                    context,
                    TimeOfDay(hour: _time!.hour, minute: _time!.minute),
                  ),
          ),
        ],
      ),
    ],
  );
}
