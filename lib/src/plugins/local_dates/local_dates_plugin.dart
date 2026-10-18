import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../chat/chat_preview_contract.dart';
import 'local_date.dart';
import 'local_date_composer.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_parser.dart';
import 'local_date_environment.dart';
import 'local_date_widget.dart';
import 'local_dates_settings.dart';

export 'local_dates_settings.dart';

class LocalDatesPlugin
    implements
        SitePlugin,
        CookingPlugin,
        ChatPreviewContribution,
        BookmarkReminderPlugin,
        ComposerComponentPlugin,
        ComposerShortcutPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        CookedElementPlugin,
        SiteSettingsPlugin<LocalDatesSettings> {
  LocalDatesPlugin({required this.environment})
    : formatter = LocalDateFormatter(environment: environment);

  final LocalDateEnvironment environment;
  final LocalDateFormatter formatter;

  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: 'discourse-local-dates',
      owner: 'discourse-local-dates',
      version: '1',
      enabledSetting: 'discourse_local_dates_enabled',
    ),
  ];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) {
    final settings = data.read(localDatesSettingsDataKey);
    return {
      'settings': {
        'discourse_local_dates_enabled': settings?.enabled ?? false,
        'discourse_local_dates_email_format': settings?.emailFormat,
        'discourse_local_dates_email_timezone': settings?.emailTimezone,
      },
    };
  }

  @override
  String get name => 'discourse-local-dates';

  @override
  PluginDataPersistenceCodec<LocalDatesSettings> get siteSettingsCodec =>
      localDatesSettingsPersistenceCodec;

  @override
  LocalDatesSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => LocalDatesSettings.fromSiteSettings(json);

  @override
  String get previewFeatureId => 'discourse-local-dates';

  @override
  ComposerSyntaxKind get composerSyntaxKind => localDateComposerSyntaxKind;

  @override
  ComposerSyntaxKind get composerComponentKind => localDateComposerSyntaxKind;

  @override
  LocalDateComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) => createLocalDateComposerSyntaxPolicy(context, environment);

  @override
  void registerComposerComponent(
    ComposerSyntaxPolicyContext context,
    ComposerComponentRegistrar registrar,
  ) {
    final policy = createComposerSyntaxPolicy(context);
    registrar.add(localDateComposerComponent(policy));
  }

  @override
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  ) => localDateComposerShortcuts(context, editor);

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      localDateWidgetBuilder(element, siteUrl: siteUrl, formatter: formatter);

  @override
  DateTime? futureBookmarkReminder(
    String cooked, {
    required String? accountTimezone,
  }) {
    final root = dom.DocumentFragment.html(cooked);
    final now = DateTime.now();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    for (final element in root.querySelectorAll('span.discourse-local-date')) {
      final spec = LocalDateSpec.fromDataAttributes(
        element.attributes.map((key, value) => MapEntry('$key', value)),
        fallbackText: element.text,
      );
      final resolved = formatter.resolve(
        spec,
        locale: locale,
        accountTimezone: accountTimezone,
        now: now,
      );
      if (resolved != null && resolved.source.isAfter(now)) {
        return resolved.source.toUtc();
      }
    }
    return null;
  }

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final syntax = _localDateSyntaxRanges(request.raw);
    if (syntax.isEmpty) return ChatPreviewInspection();
    if (!request.siteConfig.localDatesSettings.enabled) {
      return ChatPreviewInspection(
        blockers: [
          ChatPreviewBlocker(appL10n.localDatesDisabled, range: syntax.first),
        ],
      );
    }

    final blocks = parseLocalDateComposerBlocks(
      request.raw,
      environment: environment,
    );
    final forwardIncompatible = blocks.where(
      (block) => block.attributes.any(
        (attribute) =>
            !localDateAttributeNames.contains(attribute.normalizedName),
      ),
    );
    if (forwardIncompatible.isNotEmpty) {
      final block = forwardIncompatible.first;
      return ChatPreviewInspection(
        blockers: [
          ChatPreviewBlocker(
            appL10n.localDateSyntaxContainsUnsupportedOptions,
            range: SourceRange(block.start, block.end),
          ),
        ],
      );
    }
    for (final occurrence in syntax) {
      if (!blocks.any((block) => block.start == occurrence.start)) {
        return ChatPreviewInspection(
          blockers: [
            ChatPreviewBlocker(
              appL10n.localDateSyntaxIsMalformedOrUnsupported,
              range: occurrence,
            ),
          ],
        );
      }
    }
    if (blocks.length != syntax.length) {
      return ChatPreviewInspection(
        blockers: [
          ChatPreviewBlocker(appL10n.localDateSyntaxCouldNotBeAccountedFor),
        ],
      );
    }

    return ChatPreviewInspection(
      claims: [
        for (final block in blocks)
          ChatPreviewClaim(
            range: SourceRange(block.start, block.end),
            node: PluginPreviewNode(
              range: SourceRange(block.start, block.end),
              featureId: previewFeatureId,
              kind: switch (block.kind) {
                LocalDateComposerKind.date => 'date',
                LocalDateComposerKind.range => 'date-range',
              },
              fallbackText: block.source,
            ),
          ),
      ],
    );
  }

  @override
  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    if (node.featureId != previewFeatureId) return null;
    final blocks = parseLocalDateComposerBlocks(
      node.fallbackText,
      environment: environment,
    );
    if (blocks.length != 1 ||
        blocks.single.start != 0 ||
        blocks.single.end != node.fallbackText.length) {
      return null;
    }
    final block = blocks.single;
    if ((node.kind == 'date') != (block.kind == LocalDateComposerKind.date)) {
      return null;
    }
    return _OptimisticLocalDate(block: block, formatter: formatter);
  }

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) => localDateComposerToolbar(context, editor);
}

class _OptimisticLocalDate extends StatelessWidget {
  const _OptimisticLocalDate({required this.block, required this.formatter});

  final LocalDateComposerBlock block;
  final LocalDateFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final draft = LocalDateComposerDraft.fromBlock(block);
    LocalDateSpec spec({required String date, String? time, String? range}) =>
        LocalDateSpec(
          date: date,
          time: time,
          timezone: draft.timezone,
          range: range,
          format: draft.format,
          calendar: draft.calendar,
          recurring: range == null ? draft.recurring : null,
          countdown: range == null && draft.countdown,
          displayedTimezone: draft.displayedTimezone,
          timezones: draft.previewTimezones,
          fallbackText: block.source,
        );

    final start = spec(
      date: draft.startDate,
      time: draft.startTime,
      range: draft.isRange ? 'from' : null,
    );
    if (!draft.isRange) {
      return LocalDateInline(spec: start, formatter: formatter);
    }
    final end = spec(date: draft.endDate!, time: draft.endTime, range: 'to');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LocalDateInline(spec: start, to: end, formatter: formatter),
        const Text(' → '),
        LocalDateInline(spec: end, from: start, formatter: formatter),
      ],
    );
  }
}

List<SourceRange> _localDateSyntaxRanges(String source) {
  final matches = _localDateOpening.allMatches(source).toList();
  if (matches.isEmpty) return const [];
  final code = markdownCodeRanges(source);
  return [
    for (final match in matches)
      if (!code.contains(match.start)) SourceRange(match.start, match.end),
  ];
}

final RegExp _localDateOpening = RegExp(
  r'\[(?:date-range|date)(?==|\s|\])',
  caseSensitive: false,
);
