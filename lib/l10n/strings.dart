import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Registers a locale dependency for widget builds, with an English fallback
/// for independently mounted Native components and lightweight test harnesses.
extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? appL10n;
}

final _catalogues = <String, AppLocalizations>{};

// Rows ask for messages per count and label as they build, and resolving a
// locale against the catalogues scans them, so the catalogue last resolved is
// kept for the locale it was resolved for. Resolution depends on that alone.
String? _resolvedLocale;
AppLocalizations? _resolvedCatalogue;

/// Messages for presenters, models and services outside the widget tree.
///
/// The application sets [Intl.defaultLocale] when Flutter resolves its locale.
/// A standalone component, test or background isolate falls back to English.
/// Zone overrides via [Intl.withLocale] are respected without mutating the app.
AppLocalizations get appL10n {
  final current = Intl.getCurrentLocale();
  if (current == _resolvedLocale) return _resolvedCatalogue!;
  final catalogue = _resolve(current);
  _resolvedLocale = current;
  _resolvedCatalogue = catalogue;
  return catalogue;
}

AppLocalizations _resolve(String current) {
  final parts = Intl.canonicalizedLocale(current).split('_');
  final requested = Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: parts.length > 1 && parts[1].length == 4 ? parts[1] : null,
    countryCode: parts.length > 1 && parts.last.length != 4 ? parts.last : null,
  );
  final locale = basicLocaleListResolution([
    requested,
  ], AppLocalizations.supportedLocales);
  return _catalogues.putIfAbsent(locale.toLanguageTag(), () {
    // The bundled initializer installs symbols synchronously, including in
    // headless tests and isolates that have not built Flutter's delegates.
    unawaited(initializeDateFormatting(locale.toLanguageTag()));
    return lookupAppLocalizations(locale);
  });
}

/// Resolves only locales for which the application has a message catalogue.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  final locale = basicLocaleListResolution(preferred, supported.toList());
  Intl.defaultLocale = locale.toLanguageTag();
  return locale;
}

/// Sentinel for optional labels where an explicit null disables semantics.
const defaultLocalizedLabel = '\u0000localized-default';
