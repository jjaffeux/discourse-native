import 'package:discourse_native/l10n/strings.dart';

/// Whether reading tabs share the list panel or occupy their own panel.
enum TopicPresentation {
  merged(),
  split();

  const TopicPresentation();
  String get label => switch (this) {
    merged => appL10n.keepTopicTabsWithTheList,
    split => appL10n.splitWithTheList,
  };
}
