# Color profile fixture

`display_p3.icc` was generated with Little CMS 2.19.1 by
`generate_display_p3.py`. It uses D65 white, Display P3 primaries, and the sRGB
transfer curve from Little CMS's generated sRGB profile. It contains no copied
OS profile data. Tests read this committed fixture and need no native library.

To regenerate with Little CMS installed, run
`python3 test/fixtures/color_profiles/generate_display_p3.py [path-to-lcms2-library]`.
The profile creation timestamp can change between runs.
