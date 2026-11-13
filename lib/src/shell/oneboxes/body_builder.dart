import 'package:flutter/widgets.dart';

typedef OneboxBodyBuilder = Widget Function({
  required String html,
  String? siteUrl,
  TextStyle? textStyle,
  TextStyle? linkStyle,
  bool compactParagraphs,
});
