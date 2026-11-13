import '../../plugin_api/composer_target.dart';

abstract interface class ComposerRecipientTarget {
  ComposerTarget get target;
  bool get isCurrent;
  void setRecipients(Iterable<String> values);
}
