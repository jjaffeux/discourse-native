import 'package:flutter/foundation.dart';

/// A link from the Start page that can open in another tab or panel.
@immutable
final class StartPageDrag {
  const StartPageDrag({
    required this.siteUrl,
    required this.path,
    required this.title,
  });

  final String siteUrl;
  final String path;
  final String title;
}
