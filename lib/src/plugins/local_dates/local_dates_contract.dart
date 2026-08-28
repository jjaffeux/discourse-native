import 'package:html/dom.dart' as dom;

import '../../plugin_api/plugin_manifest.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

/// Resolves the instant carried by a cooked Local Dates descendant.
///
/// The Local Dates module retains ownership of recognizing and resolving its
/// server markup. Consumers receive no formatter, settings, environment, or
/// widget implementation.
abstract interface class CookedTimeParser {
  DateTime? parseDescendant(dom.Element scope);
}

const localDatesCookedTimeParserService = PluginServiceKey<CookedTimeParser>(
  owner: localDatesPluginId,
  name: 'cooked-time-parser',
);
