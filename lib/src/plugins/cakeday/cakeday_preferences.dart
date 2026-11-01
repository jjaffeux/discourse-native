import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'cakeday_data.dart';

PluginUserPreferenceSection? cakedayPreferenceSectionFor(
  BuildContext context,
  PluginUserPreferenceContext preferences,
) {
  final settings = preferences.siteSettings.get(cakedaySettingsKey);
  if (settings?.enabled != true || settings?.birthdays != true) return null;
  final values =
      preferences.preferences.pluginValues[cakedayPreferenceSection.id];
  return PluginUserPreferenceSection(
    section: cakedayPreferenceSection,
    title: context.l10n.cakedayBirthday,
    icon: DIcons.cakeCandles,
    content: CakedayBirthdayEditor(
      key: ValueKey((preferences.siteUrl, preferences.preferences.username)),
      value: values is CakedayPreferences
          ? values
          : const CakedayPreferences.unavailable(),
      editable: preferences.editable,
      onChanged: (value) => preferences.onEdit(
        cakedayPreferenceSection,
        (current) => current.copyWith(
          pluginValues: {
            ...current.pluginValues,
            cakedayPreferenceSection.id: value,
          },
        ),
      ),
    ),
  );
}

class CakedayBirthdayEditor extends StatefulWidget {
  const CakedayBirthdayEditor({
    super.key,
    required this.value,
    required this.editable,
    required this.onChanged,
  });
  final CakedayPreferences value;
  final bool editable;
  final ValueChanged<CakedayPreferences> onChanged;
  @override
  State<CakedayBirthdayEditor> createState() => _CakedayBirthdayEditorState();
}

class _CakedayBirthdayEditorState extends State<CakedayBirthdayEditor> {
  int? _month, _day;
  CakedayBirthday? _emitted;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _month = widget.value.birthday?.month;
    _day = widget.value.birthday?.day;
    _emitted = widget.value.birthday;
  }

  @override
  void didUpdateWidget(CakedayBirthdayEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.available != oldWidget.value.available ||
        widget.value.birthday != _emitted) {
      _reset();
    }
  }

  bool get _invalid =>
      _month != null &&
      _day != null &&
      CakedayBirthday.create(_month!, _day!) == null;
  void _changed() {
    setState(() {});
    if (_invalid) {
      widget.onChanged(CakedayPreferences.invalid(_emitted));
      return;
    }
    _emitted = _month == null || _day == null
        ? null
        : CakedayBirthday.create(_month!, _day!);
    widget.onChanged(CakedayPreferences(_emitted));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = widget.editable && widget.value.available;
    return DFieldGroup(
      children: [
        DField(
          invalid: _invalid,
          enabled: enabled,
          children: [
            DFieldLabel(child: Text(l10n.cakedayDateOfBirth)),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                DSelect<int>.controlled(
                  key: const ValueKey('cakeday-birthday-month'),
                  value: _month,
                  width: 180,
                  enabled: enabled,
                  semanticLabel: l10n.month,
                  entries: [
                    DSelectOption(
                      value: null,
                      label: l10n.none,
                      child: Text(l10n.none),
                    ),
                    for (var month = 1; month <= 12; month++)
                      DSelectOption(
                        value: month,
                        label: DateFormat.MMMM().format(DateTime(2000, month)),
                        child: Text(
                          DateFormat.MMMM().format(DateTime(2000, month)),
                        ),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) {
                          _month = value;
                          _changed();
                        }
                      : null,
                ),
                DSelect<int>.controlled(
                  key: const ValueKey('cakeday-birthday-day'),
                  value: _day,
                  width: 110,
                  enabled: enabled,
                  semanticLabel: l10n.day,
                  entries: [
                    DSelectOption(
                      value: null,
                      label: l10n.none,
                      child: Text(l10n.none),
                    ),
                    for (var day = 1; day <= 31; day++)
                      DSelectOption(
                        value: day,
                        label: '$day',
                        child: Text('$day'),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) {
                          _day = value;
                          _changed();
                        }
                      : null,
                ),
              ],
            ),
            DFieldDescription(
              child: Text(
                widget.value.available
                    ? l10n.cakedayBirthdayHelp
                    : l10n.cakedayBirthdayUnavailable,
              ),
            ),
            if (_invalid) DFieldError(child: Text(l10n.cakedayInvalidBirthday)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                variant: DButtonVariant.ghost,
                label: Text(l10n.cakedayClearBirthday),
                onPressed: enabled && (_month != null || _day != null)
                    ? () {
                        _month = null;
                        _day = null;
                        _changed();
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
