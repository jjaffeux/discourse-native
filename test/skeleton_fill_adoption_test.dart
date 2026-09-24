import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/control_adoption.dart';

final _region = RegExp(r'\bDSkeletonRegion\s*\(');
final _shape = RegExp(r'\bDSkeleton(?:\.circle)?\s*\(');
final _color = RegExp(r'\bcolor\s*:');
final _shared = RegExp(r'\bcolor\s*:\s*skeletonFill\b');

void main() {
  test('application skeletons take their fill from skeletonFill', () {
    final regions = <String>[];
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      // The UI kit and its styleguide keep the kit's own muted default.
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path.startsWith('lib/src/ui/') ||
          entity.path.startsWith('lib/src/styleguide/')) {
        continue;
      }
      final code = controlCode(entity.readAsStringSync());
      String at(Match match) =>
          '${entity.path}:'
          '${'\n'.allMatches(code.substring(0, match.start)).length + 1}';
      for (final region in _region.allMatches(code)) {
        regions.add(at(region));
        if (!_shared.hasMatch(_arguments(code, region.end))) {
          offenders.add('${at(region)}: a region without skeletonFill');
        }
      }
      // A shape inherits its region's fill; one that sets a colour of its
      // own must still take it from skeletonFill.
      for (final shape in _shape.allMatches(code)) {
        final arguments = _arguments(code, shape.end);
        if (_color.hasMatch(arguments) && !_shared.hasMatch(arguments)) {
          offenders.add('${at(shape)}: a shape with its own fill');
        }
      }
    }

    // A scan that stops matching would pass without checking anything.
    expect(regions, isNotEmpty);
    expect(
      offenders,
      isEmpty,
      reason:
          'The kit fill disappears on sidebars and panels, which paint it '
          'themselves, and on dark pages. Pass skeletonFill for the surface '
          'the placeholders sit on.\n${offenders.join('\n')}',
    );
  });
}

/// The top-level arguments of the call whose opening parenthesis ends at
/// [start]; nested calls and collections are blanked out.
String _arguments(String code, int start) {
  final arguments = StringBuffer();
  var depth = 1;
  for (var index = start; index < code.length && depth > 0; index++) {
    final character = code[index];
    if ('([{'.contains(character)) depth++;
    if (')]}'.contains(character)) depth--;
    arguments.write(depth == 1 ? character : ' ');
  }
  return arguments.toString();
}
