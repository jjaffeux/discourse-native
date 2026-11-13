import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:html/dom.dart' as dom;

import 'local_date.dart';
import 'local_dates_contract.dart';

final class LocalDatesCookedTimeParser implements CookedTimeParser {
  const LocalDatesCookedTimeParser({required this.formatter});

  final LocalDateFormatter formatter;

  @override
  DateTime? parseDescendant(dom.Element scope) {
    DateTime? instant;
    descendantWhere(scope, (candidate) {
      if (candidate.localName != 'span' ||
          !candidate.classes.contains('discourse-local-date')) {
        return false;
      }
      final spec = LocalDateSpec.fromDataAttributes(
        candidate.attributes.map((key, value) => MapEntry('$key', value)),
        fallbackText: candidate.text,
      );
      instant = formatter.resolveInstant(spec);
      return instant != null;
    });
    return instant;
  }
}
