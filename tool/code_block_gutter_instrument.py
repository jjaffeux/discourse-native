"""Temporarily instrument the ORIGINAL production source; never ship its output.

Usage: python3 tool/code_block_gutter_instrument.py
Restore lib/src/shell/code_block.dart after building the capture binary.
One binary runs baseline/fixed by GUTTER_MODE environment variable.
"""
from pathlib import Path

path = Path('lib/src/shell/code_block.dart')
s = path.read_text()
assert 'gutterWidth: _gutterWidth,' in s
s = s.replace("import 'dart:async';", "import 'dart:async';\nimport 'dart:io';")
s = s.replace('class CodeBlockData {', "final _profileFixedGutter = Platform.environment['GUTTER_MODE'] == 'fixed';\n\nclass CodeBlockData {")
s = s.replace('builder: (context, constraints) => DScrollBar(', '''builder: (context, constraints) {
              final profileWatch = Stopwatch()..start();
              final profileGutter = _profileFixedGutter ? _gutterWidth : null;
              final profileResult = DScrollBar(''')
s = s.replace('gutterWidth: _gutterWidth,', 'gutterWidth: _profileFixedGutter ? profileGutter : _gutterWidth,')
needle = '''            ),
          ),
        ],
      ),
    );
  }

  double? get _gutterWidth {'''
assert needle in s
s = s.replace(needle, '''            );
              profileWatch.stop();
              stdout.writeln('GUTTER_CALLBACK ${profileWatch.elapsedMicroseconds} ${data.lines.length}');
              return profileResult;
            },
          ),
        ],
      ),
    );
  }

  double? get _gutterWidth {''')
path.write_text(s)
