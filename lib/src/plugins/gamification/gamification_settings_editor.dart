import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'gamification_controller.dart';
import 'gamification_fields.dart';
import 'gamification_labels.dart';
import 'gamification_models.dart';

class GamificationSettingsEditor extends StatefulWidget {
  const GamificationSettingsEditor({
    super.key,
    required this.handle,
    required this.settings,
  });
  final GamificationAdminHandle handle;
  final GamificationGlobalSettings settings;
  @override
  State<GamificationSettingsEditor> createState() =>
      _GamificationSettingsEditorState();
}

class _GamificationSettingsEditorState
    extends State<GamificationSettingsEditor> {
  late final _viewLease = widget.handle.owner.requests.capture(
    widget.handle.site,
  );
  late final _viewRevision = widget.handle.owner.revision(widget.handle.site);
  bool get _viewCurrent =>
      widget.handle.canManage &&
      widget.handle.owner.current(
        widget.handle.site,
        _viewLease,
        _viewRevision,
        admin: true,
      );

  late bool _enabled = widget.settings.enabled;
  late Set<int> _categories = widget.settings.categoryIds;
  late GamificationRankingStrategy _ranking = widget.settings.ranking;
  late final _weights = {
    for (final rule in GamificationRule.values)
      rule: TextEditingController(text: '${widget.settings.weights[rule]}'),
  };
  String? _notice;
  @override
  void dispose() {
    for (final field in _weights.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_viewCurrent) return gameNotice(context.l10n.gamificationAdminOnly);

    final enabled = widget.handle.mayMutate;
    String ranking(GamificationRankingStrategy r) => switch (r) {
      GamificationRankingStrategy.denseRank =>
        context.l10n.gamificationDenseRank,
      GamificationRankingStrategy.rank => context.l10n.gamificationRankStrategy,
      GamificationRankingStrategy.rowNumber =>
        context.l10n.gamificationRowNumber,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        Text(context.l10n.gamificationSettingsHelp),
        Text(context.l10n.gamificationGlobalCategoryHelp),
        DToggle(
          pressed: _enabled,
          enabled: enabled,
          onPressedChanged: (v) => setState(() => _enabled = v),
          child: Text(context.l10n.gamificationEnabled),
        ),
        GamificationCategories(
          handle: widget.handle,
          value: _categories,
          enabled: enabled,
          onChanged: (v) => setState(() => _categories = v),
        ),
        DSelect<GamificationRankingStrategy>.controlled(
          value: _ranking,
          enabled: enabled,
          semanticLabel: context.l10n.gamificationRanking,
          entries: [
            for (final r in GamificationRankingStrategy.values)
              DSelectOption(
                value: r,
                label: ranking(r),
                child: Text(ranking(r)),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _ranking = v);
          },
        ),
        for (final rule in GamificationRule.values)
          DInput(
            controller: _weights[rule],
            labelText: gameRuleLabel(context, rule),
            helperText: gameRuleHelp(context, rule),
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
          ),
        if (_notice != null) gameNotice(_notice!),
        DButton(
          label: Text(context.l10n.gamificationSave),
          onPressed: enabled ? _save : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_viewCurrent) return;
    final values = <GamificationRule, int>{};
    for (final entry in _weights.entries) {
      final parsed = int.tryParse(entry.value.text.trim());
      if (parsed == null) {
        setState(() => _notice = context.l10n.gamificationSettingsInvalid);
        return;
      }
      values[entry.key] = parsed;
    }
    final result = await widget.handle.saveSettings(
      GamificationGlobalSettings(
        enabled: _enabled,
        categoryIds: _categories,
        weights: values,
        ranking: _ranking,
      ),
    );
    if (!mounted) return;
    if (result.status == GamificationMutationStatus.saved) {
      setState(() => _notice = context.l10n.gamificationSaved);
    }
  }
}
