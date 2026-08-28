import 'package:html/dom.dart' as dom;

import '../../shell/cooked_dom.dart';
import 'local_date.dart';
import 'local_dates_contract.dart';

final class LocalDatesCookedTimeParser implements CookedTimeParser {
  const LocalDatesCookedTimeParser({required this.formatter});

  final LocalDateFormatter formatter;

  @override
  DateTime? parseDescendant(dom.Element scope) {
    final element = descendantWhere(
      scope,
      (candidate) =>
          candidate.localName == 'span' &&
          candidate.classes.contains('discourse-local-date'),
    );
    if (element == null) return null;

    final spec = LocalDateSpec.fromDataAttributes(
      element.attributes.map((key, value) => MapEntry('$key', value)),
      fallbackText: element.text,
    );
    return formatter.resolveInstant(spec);
  }
}
